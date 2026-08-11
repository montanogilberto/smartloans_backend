-- ============================================================
-- paymentIntents — HAND-AUTHORED (documented posgmo-factory exception)
-- Table:    paymentIntents
-- SP:       sp_paymentIntents
-- Actions:  create | expire_due | cancel | list
-- ============================================================
-- Why hand-authored: two posgmo-factory export-only runs (2026-08-11)
-- confirmed the pipeline cannot yet propagate this module's requirements.
-- prd_paymentIntent.json.database.hints[] documents the state machine, the
-- expire_due action, the unique-FUNDING-per-loan invariant, and the CHECK
-- constraints -- but architect/prompt.py only forwards
-- prd.backend.endpoints[]/.database.tables[]/.database.storedProcedures[],
-- never .database.hints[], and decision_gate/rules.py's
-- _classify_backend_pattern() has no code path that ever returns
-- "ACTION_ROUTER" at all (only "CRUD_ONLY"/"CRUD_AND_CONNECTOR" exist today
-- even though database_agent's own prompt fully supports generating
-- ACTION_ROUTER SQL once that classification fires). Net effect: the run
-- gate-APPROVED a plain CRUD_ONLY specification that silently dropped every
-- one of those requirements. That generated SQL was discarded, not used
-- here. Tracked separately as posgmo-factory tech debt (out of scope for
-- this migration): add end-to-end support for database.hints propagation +
-- ACTION_ROUTER classification + deterministic invariant enforcement.
--
-- Source contracts for everything below:
--   - docs/p2p-direct-payments-architecture.md v1.2 (D12 5-day funding
--     expiry, D14 every declaration born from a paymentIntent)
--   - docs/rfcs/RFC-002-funding-workflow.md
--   - docs/rfcs/RFC-003-payment-intents.md
--   - posgmo-factory/tests/prd_paymentIntent.json (fields + database.hints)
--
-- Non-custodial boundary: this table only ever records the EXPECTATION of a
-- direct SPEI transfer between payerClientId and payeeClientId. No action
-- in this file charges Stripe, calls STP, or touches any wallet/platform
-- balance -- the real transfer is an external event the payer/payee execute
-- themselves; SmartLoans only records/orchestrates it (see fundingTransaction/
-- loanPayment, a later PR, for the declare/confirm evidence flow this
-- intent feeds into).
-- ============================================================

-- ── Table ────────────────────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'paymentIntents')
CREATE TABLE [dbo].[paymentIntents] (
    paymentIntentId       INT IDENTITY(1,1) NOT NULL,
    companyId             INT NOT NULL,
    loanId                INT NOT NULL,
    installmentId         INT NULL,
    intentType            NVARCHAR(12) NOT NULL,
    expectedAmountMXN     DECIMAL(10,2) NOT NULL,
    payerClientId         INT NOT NULL,
    payeeClientId         INT NOT NULL,
    beneficiarySnapshotId INT NOT NULL,
    suggestedReference    NVARCHAR(40) NOT NULL,
    expiresAt             DATETIME2 NULL,
    status                NVARCHAR(12) NOT NULL DEFAULT 'OPEN',
    created_At            DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at            DATETIME2 NULL,
    CONSTRAINT PK_paymentIntents PRIMARY KEY CLUSTERED (paymentIntentId ASC),
    CONSTRAINT FK_paymentIntents_loans FOREIGN KEY (loanId)
        REFERENCES dbo.loans(loanId),
    CONSTRAINT FK_paymentIntents_loanInstallments FOREIGN KEY (installmentId)
        REFERENCES dbo.loanInstallments(installmentId),
    CONSTRAINT FK_paymentIntents_payerClients FOREIGN KEY (payerClientId)
        REFERENCES dbo.clients(clientId),
    CONSTRAINT FK_paymentIntents_payeeClients FOREIGN KEY (payeeClientId)
        REFERENCES dbo.clients(clientId),
    CONSTRAINT FK_paymentIntents_bankAccountSnapshots FOREIGN KEY (beneficiarySnapshotId)
        REFERENCES dbo.bankAccountSnapshots(snapshotId),
    -- database.hints: "intentType and status allowed values are CHECK
    -- constraints, not lookup tables."
    CONSTRAINT CK_paymentIntents_intentType CHECK (
        intentType IN ('FUNDING','INSTALLMENT','PARTIAL','PAYOFF')
    ),
    -- database.hints: "Status machine: OPEN -> DECLARED | EXPIRED |
    -- CANCELLED. Any other transition must return an error." (transition
    -- enforcement itself lives in the SP below -- this CHECK only bounds
    -- the allowed value set.)
    CONSTRAINT CK_paymentIntents_status CHECK (
        status IN ('OPEN','DECLARED','EXPIRED','CANCELLED')
    ),
    CONSTRAINT CK_paymentIntents_amount CHECK (expectedAmountMXN > 0),
    -- FUNDING intents fund the whole loan (no installment); every other
    -- intentType is scoped to one installment.
    CONSTRAINT CK_paymentIntents_installmentId CHECK (
        (intentType = 'FUNDING' AND installmentId IS NULL) OR
        (intentType <> 'FUNDING' AND installmentId IS NOT NULL)
    )
)
GO

-- database.hints: "Only ONE intent with intentType='FUNDING' per loanId
-- (unique filtered index)." Scoped to status='OPEN' specifically: a
-- CANCELLED or EXPIRED FUNDING intent must not block creating a new one for
-- the same loan (e.g. after expiry, the loan returns to the marketplace and
-- a new lender can fund it) -- the real invariant is "one *unresolved*
-- FUNDING intent per loan", not "one ever".
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_paymentIntents_openFunding')
    CREATE UNIQUE INDEX UQ_paymentIntents_openFunding
        ON dbo.paymentIntents (companyId, loanId)
        WHERE intentType = 'FUNDING' AND status = 'OPEN';
GO

-- database.hints: "Index (status, expiresAt) for the expiry cron sweep."
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_paymentIntents_expirySweep')
    CREATE NONCLUSTERED INDEX IX_paymentIntents_expirySweep
        ON dbo.paymentIntents (status, expiresAt)
        WHERE status = 'OPEN';
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_paymentIntents_companyId')
    CREATE NONCLUSTERED INDEX IX_paymentIntents_companyId ON dbo.paymentIntents (companyId);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_paymentIntents_loanId')
    CREATE NONCLUSTERED INDEX IX_paymentIntents_loanId ON dbo.paymentIntents (loanId);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_paymentIntents_installmentId')
    CREATE NONCLUSTERED INDEX IX_paymentIntents_installmentId ON dbo.paymentIntents (installmentId);
GO

-- ── SP ───────────────────────────────────────────────────────
IF OBJECT_ID('dbo.sp_paymentIntents', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_paymentIntents;
GO

CREATE PROCEDURE [dbo].[sp_paymentIntents]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action    NVARCHAR(40) = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].action')
    DECLARE @companyId INT          = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].companyId')

    -- ── create ───────────────────────────────────────────────
    -- database.hints: idempotency for FUNDING is the unique filtered index
    -- above (UQ_paymentIntents_openFunding) -- violating it raises SQL
    -- error 2601, surfaced as a friendly duplicate message below rather
    -- than a raw constraint-violation string.
    IF @action = 'create'
    BEGIN
        DECLARE @loanId                INT            = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].loanId')
        DECLARE @installmentId         INT            = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].installmentId')
        DECLARE @intentType            NVARCHAR(12)   = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].intentType')
        DECLARE @expectedAmountMXN     DECIMAL(10,2)  = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].expectedAmountMXN')
        DECLARE @payerClientId         INT            = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].payerClientId')
        DECLARE @payeeClientId         INT            = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].payeeClientId')
        DECLARE @beneficiarySnapshotId INT            = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].beneficiarySnapshotId')
        DECLARE @suggestedReference    NVARCHAR(40)   = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].suggestedReference')
        DECLARE @expiresAt             DATETIME2      = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].expiresAt')

        IF @intentType = 'FUNDING' AND EXISTS (
            SELECT 1 FROM dbo.paymentIntents
            WHERE companyId = @companyId AND loanId = @loanId
              AND intentType = 'FUNDING' AND status = 'OPEN'
        )
        BEGIN
            SELECT '{"error":"An OPEN FUNDING intent already exists for this loan."}' AS [jsonResult]
            RETURN
        END

        INSERT INTO dbo.paymentIntents
            (companyId, loanId, installmentId, intentType, expectedAmountMXN,
             payerClientId, payeeClientId, beneficiarySnapshotId,
             suggestedReference, expiresAt, status)
        VALUES
            (@companyId, @loanId, @installmentId, @intentType, @expectedAmountMXN,
             @payerClientId, @payeeClientId, @beneficiarySnapshotId,
             @suggestedReference, @expiresAt, 'OPEN')

        DECLARE @newIntentId INT = SCOPE_IDENTITY()

        SELECT (
            SELECT paymentIntentId, companyId, loanId, installmentId, intentType,
                   expectedAmountMXN, payerClientId, payeeClientId,
                   beneficiarySnapshotId, suggestedReference,
                   CONVERT(NVARCHAR, expiresAt, 127) AS expiresAt,
                   status,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM dbo.paymentIntents WHERE paymentIntentId = @newIntentId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── expire_due ───────────────────────────────────────────
    -- database.hints: "marks OPEN intents with expiresAt <= GETUTCDATE()
    -- as EXPIRED and returns the affected loanIds so the caller can
    -- transition loans to 'expired'." Cron-invoked; @companyId optional
    -- (a global sweep when omitted, matching how other cron sweeps in this
    -- codebase run -- see modules/automatedPayments.py charge_due_installments).
    ELSE IF @action = 'expire_due'
    BEGIN
        DECLARE @expired TABLE (paymentIntentId INT, loanId INT)

        UPDATE dbo.paymentIntents
        SET status = 'EXPIRED', updated_at = GETUTCDATE()
        OUTPUT inserted.paymentIntentId, inserted.loanId INTO @expired
        WHERE status = 'OPEN'
          AND expiresAt IS NOT NULL
          AND expiresAt <= GETUTCDATE()
          AND (@companyId IS NULL OR companyId = @companyId)

        SELECT ISNULL(
            (SELECT paymentIntentId, loanId FROM @expired FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── cancel ───────────────────────────────────────────────
    -- database.hints: "Any other transition must return an error." Only
    -- OPEN -> CANCELLED is valid here -- a DECLARED intent means the real
    -- SPEI may already be in flight (see fundingTransaction/loanPayment's
    -- own escalate/dispute flow for that case instead).
    ELSE IF @action = 'cancel'
    BEGIN
        DECLARE @cancelIntentId INT = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].paymentIntentId')

        IF NOT EXISTS (
            SELECT 1 FROM dbo.paymentIntents
            WHERE paymentIntentId = @cancelIntentId AND companyId = @companyId AND status = 'OPEN'
        )
        BEGIN
            SELECT '{"error":"Intent not found, not OPEN, or belongs to a different company -- cannot cancel."}' AS [jsonResult]
            RETURN
        END

        UPDATE dbo.paymentIntents
        SET status = 'CANCELLED', updated_at = GETUTCDATE()
        WHERE paymentIntentId = @cancelIntentId AND companyId = @companyId

        SELECT (
            SELECT @cancelIntentId AS paymentIntentId, 'CANCELLED' AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── list ─────────────────────────────────────────────────
    -- database.hints origin term: "list_for_loan" -- every intent for one
    -- loan, newest first.
    ELSE IF @action = 'list'
    BEGIN
        DECLARE @listLoanId INT = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].loanId')

        SELECT ISNULL(
            (SELECT paymentIntentId, loanId, installmentId, intentType,
                    expectedAmountMXN, payerClientId, payeeClientId,
                    beneficiarySnapshotId, suggestedReference,
                    CONVERT(NVARCHAR, expiresAt, 127) AS expiresAt,
                    status,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM dbo.paymentIntents
             WHERE companyId = @companyId AND loanId = @listLoanId
             ORDER BY created_At DESC
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            SELECT '{"error":"An OPEN FUNDING intent already exists for this loan."}' AS [jsonResult]
        ELSE
            SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO
