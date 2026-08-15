-- ============================================================
-- fundingTransactions — HAND-AUTHORED (documented posgmo-factory exception)
-- Table:    fundingTransactions
-- SP:       sp_fundingTransactions
-- Actions:  declare | confirm | reject | escalate_due | resolve_escalation | list | one
-- ============================================================
-- Why hand-authored: same posgmo-factory gap already documented in
-- sql/sp_paymentIntents.sql -- an export-only run (2026-08-15, prompt fixed
-- first per that file's incident note) still produced a generic CRUD
-- action=1/2/3 scaffold instead of the state-machine actions this table
-- needs (its own generated SP admitted the gap in a comment: "paymentHistory
-- table not found in schema. This action is omitted."). The generated
-- create_table.sql WAS usable and is the basis for the table below
-- (pr_export/fundingTransaction/create_table.sql, 2026-08-15) -- only the SP
-- was discarded and rewritten by hand.
--
-- Source contracts for everything below:
--   - docs/p2p-direct-payments-architecture.md v1.2 (D5 never auto-confirm,
--     D13 funding creates the active loan, D16 every transition is an
--     INSERT into paymentHistory, D17 beneficiary verification warning)
--   - docs/rfcs/RFC-002-funding-workflow.md (APROBADO 2026-08-01)
--   - posgmo-factory/tests/prd_fundingTransaction.json
--
-- Non-custodial boundary: this table only ever RECORDS a declaration the
-- lender makes about a SPEI transfer they already sent from their own bank,
-- and the borrower's confirmation of having received it. No action in this
-- file calls STP, Stripe, or touches any wallet/platform balance -- the
-- money movement itself happens entirely outside SmartLoans.
--
-- Not yet built (tracked separately, do not block this PR on them):
--   - transferEvidence (clave de rastreo, bank, optional CEP/screenshot) --
--     RFC-002 §3 pairs this with every declare; declare below accepts a
--     bare @transferDate/@amountMXN only until that table exists.
--   - paymentHistory (D16 append-only audit of every status change) -- each
--     action below is commented with where that INSERT will go.
--   - sp_loans transition matrix (pending_funding -> funded -> active) and
--     the LoanActivated event -- orchestration lives in the Python module
--     that calls this SP, not in the SP itself.
-- ============================================================

-- ── Table ────────────────────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'fundingTransactions')
CREATE TABLE [dbo].[fundingTransactions] (
    fundingTransactionId INT IDENTITY(1,1) NOT NULL,
    companyId             INT NOT NULL,
    loanId                INT NOT NULL,
    intentId              INT NOT NULL,
    lenderClientId        INT NOT NULL,
    borrowerClientId      INT NOT NULL,
    amountMXN             DECIMAL(18,2) NOT NULL,
    transferDate          DATETIME2 NOT NULL,
    status                NVARCHAR(25) NOT NULL DEFAULT 'PENDING_CONFIRMATION',
    declaredAt            DATETIME2 NULL,
    confirmedAt           DATETIME2 NULL,
    confirmedByClientId   INT NULL,
    rejectReason          NVARCHAR(300) NULL,
    escalatedAt           DATETIME2 NULL,
    created_At            DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at            DATETIME2 NULL,
    CONSTRAINT PK_fundingTransactions PRIMARY KEY CLUSTERED (fundingTransactionId ASC),
    CONSTRAINT FK_fundingTransactions_Loans FOREIGN KEY (loanId)
        REFERENCES dbo.loans(loanId),
    CONSTRAINT FK_fundingTransactions_PaymentIntents FOREIGN KEY (intentId)
        REFERENCES dbo.paymentIntents(paymentIntentId),
    CONSTRAINT FK_fundingTransactions_LenderClients FOREIGN KEY (lenderClientId)
        REFERENCES dbo.clients(clientId),
    CONSTRAINT FK_fundingTransactions_BorrowerClients FOREIGN KEY (borrowerClientId)
        REFERENCES dbo.clients(clientId),
    -- RFC-002: "tabla propia, UNIQUE loanId" -- one loan can only ever have
    -- one funding transaction (matches paymentIntents' one-OPEN-FUNDING
    -- invariant one level down the chain).
    CONSTRAINT UQ_fundingTransactions_loanId UNIQUE NONCLUSTERED (loanId),
    CONSTRAINT CK_fundingTransactions_amount CHECK (amountMXN > 0),
    -- database.hints (this file): status machine is
    -- PENDING_CONFIRMATION -> CONFIRMED | REJECTED | ESCALATED,
    -- ESCALATED -> CONFIRMED | CANCELLED (support-resolved only, D5). Any
    -- other transition must return an error -- enforced in the SP below,
    -- this CHECK only bounds the allowed value set.
    CONSTRAINT CK_fundingTransactions_status CHECK (
        status IN ('PENDING_CONFIRMATION','CONFIRMED','REJECTED','ESCALATED','CANCELLED')
    )
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_fundingTransactions_companyId')
    CREATE NONCLUSTERED INDEX IX_fundingTransactions_companyId ON dbo.fundingTransactions (companyId);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_fundingTransactions_intentId')
    CREATE NONCLUSTERED INDEX IX_fundingTransactions_intentId ON dbo.fundingTransactions (intentId);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_fundingTransactions_lenderClientId')
    CREATE NONCLUSTERED INDEX IX_fundingTransactions_lenderClientId ON dbo.fundingTransactions (lenderClientId);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_fundingTransactions_borrowerClientId')
    CREATE NONCLUSTERED INDEX IX_fundingTransactions_borrowerClientId ON dbo.fundingTransactions (borrowerClientId);
GO
-- escalate_due cron sweep: PENDING_CONFIRMATION rows old enough to escalate.
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_fundingTransactions_escalateSweep')
    CREATE NONCLUSTERED INDEX IX_fundingTransactions_escalateSweep
        ON dbo.fundingTransactions (status, declaredAt)
        WHERE status = 'PENDING_CONFIRMATION';
GO

-- ── SP ───────────────────────────────────────────────────────
IF OBJECT_ID('dbo.sp_fundingTransactions', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_fundingTransactions;
GO

CREATE PROCEDURE [dbo].[sp_fundingTransactions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action    NVARCHAR(40) = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].action')
    DECLARE @companyId INT          = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].companyId')

    -- ── declare ──────────────────────────────────────────────
    -- Lender already sent the SPEI from their own bank; this just records
    -- it. Requires the paymentIntent (RFC-002 D14) to still be OPEN and of
    -- type FUNDING for this exact loan/lender/borrower -- refuses to create
    -- an orphan declaration nobody expected.
    IF @action = 'declare'
    BEGIN
        DECLARE @loanId           INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].loanId')
        DECLARE @intentId         INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].intentId')
        DECLARE @lenderClientId   INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].lenderClientId')
        DECLARE @borrowerClientId INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].borrowerClientId')
        DECLARE @amountMXN        DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].amountMXN')
        DECLARE @transferDate     DATETIME2     = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].transferDate')

        IF NOT EXISTS (
            SELECT 1 FROM dbo.paymentIntents
            WHERE paymentIntentId = @intentId AND companyId = @companyId AND loanId = @loanId
              AND intentType = 'FUNDING' AND status = 'OPEN'
              AND payerClientId = @lenderClientId AND payeeClientId = @borrowerClientId
        )
        BEGIN
            SELECT '{"error":"No hay un paymentIntent FUNDING abierto para este préstamo/prestamista/prestatario."}' AS [jsonResult]
            RETURN
        END

        IF EXISTS (SELECT 1 FROM dbo.fundingTransactions WHERE loanId = @loanId)
        BEGIN
            SELECT '{"error":"Este préstamo ya tiene una declaración de fondeo."}' AS [jsonResult]
            RETURN
        END

        BEGIN TRANSACTION;

        INSERT INTO dbo.fundingTransactions
            (companyId, loanId, intentId, lenderClientId, borrowerClientId,
             amountMXN, transferDate, status, declaredAt)
        VALUES
            (@companyId, @loanId, @intentId, @lenderClientId, @borrowerClientId,
             @amountMXN, @transferDate, 'PENDING_CONFIRMATION', GETUTCDATE())

        DECLARE @newFundingId INT = SCOPE_IDENTITY()

        -- sp_paymentIntents has no 'declare' action yet (only
        -- create/expire_due/cancel/list) -- direct UPDATE here until that's
        -- added; CK_paymentIntents_status already allows 'DECLARED'.
        UPDATE dbo.paymentIntents
        SET status = 'DECLARED', updated_at = GETUTCDATE()
        WHERE paymentIntentId = @intentId

        -- TODO(paymentHistory, D16): INSERT audit row here once that table
        -- exists — entity='fundingTransactions', action='DECLARE'.

        COMMIT TRANSACTION;

        SELECT (
            SELECT fundingTransactionId, companyId, loanId, intentId, lenderClientId,
                   borrowerClientId, amountMXN,
                   CONVERT(NVARCHAR, transferDate, 127) AS transferDate,
                   status,
                   CONVERT(NVARCHAR, declaredAt, 127) AS declaredAt,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM dbo.fundingTransactions WHERE fundingTransactionId = @newFundingId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── confirm ──────────────────────────────────────────────
    -- D5: only the BORROWER confirms — it's their money that arrived, the
    -- system never auto-confirms on the lender's word alone.
    ELSE IF @action = 'confirm'
    BEGIN
        DECLARE @confirmId       INT = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].fundingTransactionId')
        DECLARE @confirmByClient INT = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].confirmedByClientId')

        DECLARE @confirmBorrowerId INT, @confirmLoanId INT
        SELECT @confirmBorrowerId = borrowerClientId, @confirmLoanId = loanId
        FROM dbo.fundingTransactions
        WHERE fundingTransactionId = @confirmId AND companyId = @companyId AND status = 'PENDING_CONFIRMATION'

        IF @confirmBorrowerId IS NULL
        BEGIN
            SELECT '{"error":"Declaración no encontrada o ya resuelta."}' AS [jsonResult]
            RETURN
        END
        IF @confirmByClient <> @confirmBorrowerId
        BEGIN
            SELECT '{"error":"Solo el prestatario puede confirmar la recepción del depósito."}' AS [jsonResult]
            RETURN
        END

        UPDATE dbo.fundingTransactions
        SET status = 'CONFIRMED', confirmedAt = GETUTCDATE(),
            confirmedByClientId = @confirmByClient, updated_at = GETUTCDATE()
        WHERE fundingTransactionId = @confirmId

        -- TODO(paymentHistory, D16) + TODO(sp_loans transition, D13):
        -- orchestrated by the calling Python module, not here — this SP
        -- stays scoped to its own table.

        SELECT (
            SELECT @confirmId AS fundingTransactionId, @confirmLoanId AS loanId, 'CONFIRMED' AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── reject ───────────────────────────────────────────────
    -- Borrower says the money never arrived. Also borrower-only, mirroring
    -- confirm — the payee is the one with standing to dispute non-receipt.
    ELSE IF @action = 'reject'
    BEGIN
        DECLARE @rejectId       INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].fundingTransactionId')
        DECLARE @rejectByClient INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].rejectedByClientId')
        DECLARE @rejectReason   NVARCHAR(300) = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].rejectReason')

        DECLARE @rejectBorrowerId INT
        SELECT @rejectBorrowerId = borrowerClientId
        FROM dbo.fundingTransactions
        WHERE fundingTransactionId = @rejectId AND companyId = @companyId AND status = 'PENDING_CONFIRMATION'

        IF @rejectBorrowerId IS NULL
        BEGIN
            SELECT '{"error":"Declaración no encontrada o ya resuelta."}' AS [jsonResult]
            RETURN
        END
        IF @rejectByClient <> @rejectBorrowerId
        BEGIN
            SELECT '{"error":"Solo el prestatario puede rechazar una declaración de depósito."}' AS [jsonResult]
            RETURN
        END

        UPDATE dbo.fundingTransactions
        SET status = 'REJECTED', rejectReason = @rejectReason, updated_at = GETUTCDATE()
        WHERE fundingTransactionId = @rejectId

        SELECT (
            SELECT @rejectId AS fundingTransactionId, 'REJECTED' AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── escalate_due ─────────────────────────────────────────
    -- Cron-invoked, mirrors sp_paymentIntents' expire_due shape.
    -- @escalateAfterDays is caller-supplied, not hardcoded: RFC-002's own
    -- "Alternativas descartadas" leaves the exact threshold as an open,
    -- business-tunable parameter, not an architecture decision.
    -- NOTE: RFC-002 §6 says this only fires when evidence exists
    -- (transferEvidence, not yet built) — until then this sweeps ALL
    -- overdue PENDING_CONFIRMATION rows regardless of evidence; tighten
    -- this WHERE clause once transferEvidence exists.
    ELSE IF @action = 'escalate_due'
    BEGIN
        DECLARE @escalateAfterDays INT = ISNULL(JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].escalateAfterDays'), 2)
        DECLARE @escalated TABLE (fundingTransactionId INT, loanId INT)

        UPDATE dbo.fundingTransactions
        SET status = 'ESCALATED', escalatedAt = GETUTCDATE(), updated_at = GETUTCDATE()
        OUTPUT inserted.fundingTransactionId, inserted.loanId INTO @escalated
        WHERE status = 'PENDING_CONFIRMATION'
          AND declaredAt IS NOT NULL
          AND declaredAt <= DATEADD(DAY, -@escalateAfterDays, GETUTCDATE())
          AND (@companyId IS NULL OR companyId = @companyId)

        SELECT ISNULL(
            (SELECT fundingTransactionId, loanId FROM @escalated FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── resolve_escalation ───────────────────────────────────
    -- Support/admin only — D5 applies here too: a human resolves with real
    -- evidence (CEP), the system still never auto-confirms.
    ELSE IF @action = 'resolve_escalation'
    BEGIN
        DECLARE @resolveId         INT          = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].fundingTransactionId')
        DECLARE @resolution        NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].resolution')

        IF @resolution NOT IN ('CONFIRMED', 'CANCELLED')
        BEGIN
            SELECT '{"error":"resolution debe ser CONFIRMED o CANCELLED."}' AS [jsonResult]
            RETURN
        END
        IF NOT EXISTS (
            SELECT 1 FROM dbo.fundingTransactions
            WHERE fundingTransactionId = @resolveId AND companyId = @companyId AND status = 'ESCALATED'
        )
        BEGIN
            SELECT '{"error":"Declaración no encontrada o no está escalada."}' AS [jsonResult]
            RETURN
        END

        UPDATE dbo.fundingTransactions
        SET status = @resolution,
            confirmedAt = CASE WHEN @resolution = 'CONFIRMED' THEN GETUTCDATE() ELSE confirmedAt END,
            updated_at = GETUTCDATE()
        WHERE fundingTransactionId = @resolveId

        SELECT (
            SELECT @resolveId AS fundingTransactionId, @resolution AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── list ─────────────────────────────────────────────────
    ELSE IF @action = 'list'
    BEGIN
        DECLARE @listLoanId INT = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].loanId')

        SELECT ISNULL(
            (SELECT fundingTransactionId, loanId, intentId, lenderClientId, borrowerClientId,
                    amountMXN, CONVERT(NVARCHAR, transferDate, 127) AS transferDate,
                    status,
                    CONVERT(NVARCHAR, declaredAt, 127) AS declaredAt,
                    CONVERT(NVARCHAR, confirmedAt, 127) AS confirmedAt,
                    confirmedByClientId, rejectReason,
                    CONVERT(NVARCHAR, escalatedAt, 127) AS escalatedAt,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM dbo.fundingTransactions
             WHERE companyId = @companyId AND (@listLoanId IS NULL OR loanId = @listLoanId)
             ORDER BY created_At DESC
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── one ──────────────────────────────────────────────────
    ELSE IF @action = 'one'
    BEGIN
        DECLARE @oneId INT = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].fundingTransactionId')

        SELECT (
            SELECT fundingTransactionId, loanId, intentId, lenderClientId, borrowerClientId,
                   amountMXN, CONVERT(NVARCHAR, transferDate, 127) AS transferDate,
                   status,
                   CONVERT(NVARCHAR, declaredAt, 127) AS declaredAt,
                   CONVERT(NVARCHAR, confirmedAt, 127) AS confirmedAt,
                   confirmedByClientId, rejectReason,
                   CONVERT(NVARCHAR, escalatedAt, 127) AS escalatedAt,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM dbo.fundingTransactions
            WHERE fundingTransactionId = @oneId AND companyId = @companyId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2601, 2627)
            SELECT '{"error":"Este préstamo ya tiene una declaración de fondeo."}' AS [jsonResult]
        ELSE
            SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO
