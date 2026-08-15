-- ============================================================
-- transferEvidence — HAND-AUTHORED (documented posgmo-factory exception)
-- Table:    transferEvidence
-- SP:       sp_transferEvidence
-- Actions:  create | list | one
-- ============================================================
-- Why hand-authored: two posgmo-factory export-only runs (2026-08-15)
-- failed before reaching database generation at all -- run 1 hard-blocked
-- on a false-positive "FK target 'companies' does not exist" (companies
-- plainly exists; every sibling table in this backend references it), run
-- 2 produced an empty architect specification ("No specification found in
-- session state"). Different failure each time -- generator-side
-- flakiness, not a spec problem. Same resolution as sp_paymentIntents.sql
-- and sp_fundingTransactions.sql: hand-author directly against the RFCs.
--
-- Source contracts for everything below:
--   - docs/rfcs/RFC-002-funding-workflow.md §3 ("clave de rastreo + fecha +
--     banco origen (+ comprobante opcional) -> fundingTransactions +
--     transferEvidence estructurada")
--   - docs/rfcs/RFC-003-payment-intents.md §3, §6 (D15 datos estructurados +
--     hash SHA-256 en vez de PDF como evidencia primaria; clave de rastreo
--     obligatoria y única por company = idempotencia), §"Seguridad" (adjunto
--     en blob privado + SAS; monto vs intent +/-$1; rate-limit 5
--     declaraciones/día/préstamo)
--
-- Shared table (RFC-002 + RFC-003): one row of evidence can back either a
-- fundingTransactions declaration (referenceType='FUNDING') or a future
-- loanPayments declaration (referenceType IN INSTALLMENT|PARTIAL|PAYOFF).
-- loanPayments doesn't exist yet (separate, not-yet-built PR) -- referenceId
-- for those types is intentionally NOT a hard FK yet; the 'FUNDING' case IS
-- fully validated below (existence + amount-vs-intent tolerance) since
-- fundingTransactions/paymentIntents already exist.
--
-- Non-custodial boundary: this table stores PROOF a transfer happened
-- outside SmartLoans (the clave de rastreo is issued by the sender's own
-- bank/STP, not by us) -- nothing here moves money.
-- ============================================================

-- ── Table ────────────────────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'transferEvidence')
CREATE TABLE [dbo].[transferEvidence] (
    transferEvidenceId INT IDENTITY(1,1) NOT NULL,
    companyId           INT NOT NULL,
    referenceType       NVARCHAR(12) NOT NULL,
    referenceId         INT NOT NULL,
    claveRastreo        NVARCHAR(40) NOT NULL,
    transferDate        DATETIME2 NOT NULL,
    bankFrom             NVARCHAR(100) NULL,
    amountMXN           DECIMAL(18,2) NOT NULL,
    evidenceFileUrl      NVARCHAR(500) NULL,
    -- D15: hash of the structured data (claveRastreo+transferDate+bankFrom+
    -- amountMXN concatenation), not a hash of any uploaded file -- the CEP
    -- is meant to be regenerable FROM the structured data.
    evidenceHash        NVARCHAR(64) NULL,
    uploadedByClientId  INT NOT NULL,
    created_At          DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT PK_transferEvidence PRIMARY KEY CLUSTERED (transferEvidenceId ASC),
    CONSTRAINT FK_transferEvidence_UploadedBy FOREIGN KEY (uploadedByClientId)
        REFERENCES dbo.clients(clientId),
    -- RFC-003 §3: "Clave única por company = idempotencia."
    CONSTRAINT UQ_transferEvidence_claveRastreo UNIQUE (companyId, claveRastreo),
    CONSTRAINT CK_transferEvidence_referenceType CHECK (
        referenceType IN ('FUNDING','INSTALLMENT','PARTIAL','PAYOFF')
    ),
    CONSTRAINT CK_transferEvidence_amount CHECK (amountMXN > 0)
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_transferEvidence_companyId')
    CREATE NONCLUSTERED INDEX IX_transferEvidence_companyId ON dbo.transferEvidence (companyId);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_transferEvidence_reference')
    CREATE NONCLUSTERED INDEX IX_transferEvidence_reference ON dbo.transferEvidence (referenceType, referenceId);
GO

-- ── SP ───────────────────────────────────────────────────────
IF OBJECT_ID('dbo.sp_transferEvidence', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_transferEvidence;
GO

CREATE PROCEDURE [dbo].[sp_transferEvidence]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action    NVARCHAR(40) = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].action')
    DECLARE @companyId INT          = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].companyId')

    -- ── create ───────────────────────────────────────────────
    IF @action = 'create'
    BEGIN
        DECLARE @referenceType      NVARCHAR(12)   = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].referenceType')
        DECLARE @referenceId        INT            = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].referenceId')
        DECLARE @claveRastreo       NVARCHAR(40)   = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].claveRastreo')
        DECLARE @transferDate       DATETIME2      = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].transferDate')
        DECLARE @bankFrom            NVARCHAR(100)  = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].bankFrom')
        DECLARE @amountMXN          DECIMAL(18,2)  = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].amountMXN')
        DECLARE @evidenceFileUrl     NVARCHAR(500)  = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].evidenceFileUrl')
        DECLARE @evidenceHash       NVARCHAR(64)   = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].evidenceHash')
        DECLARE @uploadedByClientId INT            = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].uploadedByClientId')

        IF @claveRastreo IS NULL OR LEN(@claveRastreo) = 0
        BEGIN
            SELECT '{"error":"claveRastreo es obligatoria."}' AS [jsonResult]
            RETURN
        END

        -- RFC-003 "Seguridad": rate-limit 5 declaraciones/día/préstamo.
        -- Scoped by (referenceType, referenceId) as the closest proxy to
        -- "per loan" available at this table's level.
        IF (
            SELECT COUNT(*) FROM dbo.transferEvidence
            WHERE referenceType = @referenceType AND referenceId = @referenceId
              AND created_At >= DATEADD(DAY, -1, GETUTCDATE())
        ) >= 5
        BEGIN
            SELECT '{"error":"Límite de 5 declaraciones por día alcanzado para esta referencia."}' AS [jsonResult]
            RETURN
        END

        -- FUNDING is fully validated (fundingTransactions/paymentIntents
        -- already exist): must be a real PENDING_CONFIRMATION funding row,
        -- and the declared amount must be within +/-$1 of the linked
        -- intent's expected amount (RFC-003 "Seguridad").
        IF @referenceType = 'FUNDING'
        BEGIN
            DECLARE @intentExpected DECIMAL(18,2)
            SELECT @intentExpected = pi.expectedAmountMXN
            FROM dbo.fundingTransactions ft
            JOIN dbo.paymentIntents pi ON pi.paymentIntentId = ft.intentId
            WHERE ft.fundingTransactionId = @referenceId AND ft.companyId = @companyId
              AND ft.status = 'PENDING_CONFIRMATION'

            IF @intentExpected IS NULL
            BEGIN
                SELECT '{"error":"No existe una declaración de fondeo PENDING_CONFIRMATION para esa referencia."}' AS [jsonResult]
                RETURN
            END
            IF ABS(@amountMXN - @intentExpected) > 1.00
            BEGIN
                SELECT '{"error":"El monto declarado no coincide con el esperado (tolerancia +/-$1)."}' AS [jsonResult]
                RETURN
            END
        END
        -- ELSE (INSTALLMENT|PARTIAL|PAYOFF): loanPayments doesn't exist yet
        -- -- accepted without cross-validation until that PR lands.

        INSERT INTO dbo.transferEvidence
            (companyId, referenceType, referenceId, claveRastreo, transferDate,
             bankFrom, amountMXN, evidenceFileUrl, evidenceHash, uploadedByClientId)
        VALUES
            (@companyId, @referenceType, @referenceId, @claveRastreo, @transferDate,
             @bankFrom, @amountMXN, @evidenceFileUrl, @evidenceHash, @uploadedByClientId)

        DECLARE @newEvidenceId INT = SCOPE_IDENTITY()

        SELECT (
            SELECT transferEvidenceId, companyId, referenceType, referenceId, claveRastreo,
                   CONVERT(NVARCHAR, transferDate, 127) AS transferDate,
                   bankFrom, amountMXN, evidenceFileUrl, evidenceHash, uploadedByClientId,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM dbo.transferEvidence WHERE transferEvidenceId = @newEvidenceId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── list ─────────────────────────────────────────────────
    ELSE IF @action = 'list'
    BEGIN
        DECLARE @listReferenceType NVARCHAR(12) = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].referenceType')
        DECLARE @listReferenceId   INT          = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].referenceId')

        SELECT ISNULL(
            (SELECT transferEvidenceId, companyId, referenceType, referenceId, claveRastreo,
                    CONVERT(NVARCHAR, transferDate, 127) AS transferDate,
                    bankFrom, amountMXN, evidenceFileUrl, evidenceHash, uploadedByClientId,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM dbo.transferEvidence
             WHERE companyId = @companyId
               AND (@listReferenceType IS NULL OR referenceType = @listReferenceType)
               AND (@listReferenceId IS NULL OR referenceId = @listReferenceId)
             ORDER BY created_At DESC
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── one ──────────────────────────────────────────────────
    ELSE IF @action = 'one'
    BEGIN
        DECLARE @oneId INT = JSON_VALUE(@pjsonfile, '$.transferEvidence[0].transferEvidenceId')

        SELECT (
            SELECT transferEvidenceId, companyId, referenceType, referenceId, claveRastreo,
                   CONVERT(NVARCHAR, transferDate, 127) AS transferDate,
                   bankFrom, amountMXN, evidenceFileUrl, evidenceHash, uploadedByClientId,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM dbo.transferEvidence
            WHERE transferEvidenceId = @oneId AND companyId = @companyId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            SELECT '{"error":"Esta clave de rastreo ya fue registrada (posible duplicado)."}' AS [jsonResult]
        ELSE
            SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO
