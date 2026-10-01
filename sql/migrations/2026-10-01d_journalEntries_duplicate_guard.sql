-- =============================================================================
-- Step 3 — sp_journalEntries: reject a second POSTED entry for the same movement
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 3 (§7.3).
-- Test:    sql/tests/2026-10-01d_journalEntries_duplicate_guard_test.sql
-- Python:  modules/journalEntries.py posting map (cash → 1101 Caja, card/transfer
--          → 1105 Bancos; expense by type) — unit test tests/test_journal_posting_map.py.
--
-- WHY: the auto-post hooks are best-effort and the Step 4/7 backfills will
-- re-run over history; without a guard the same income/expense could be booked
-- twice. The guard lives in the SP (atomic, under UPDLOCK/HOLDLOCK) rather than
-- in Python, and rather than a filtered unique index (which would make every
-- writer of journalEntries depend on its QUOTED_IDENTIFIER setting — the
-- sp_suppliers 1934 trap).
--
-- RULE: for referenceType IN ('income','expense','income_commission') with a
-- referenceId, at most one POSTED entry per companyId. VOID entries are ignored
-- (a voided movement may be re-posted). Manual/adjustment/opening_balance
-- entries are not affected.
--
-- SAFETY: the body below is sql/sp_journalEntries.sql's body + the guard. The
-- script first checks the LIVE definition still has the repo's markers; if not
-- (someone changed it outside the repo) it stops before altering anything.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ── Pre-checks ───────────────────────────────────────────────────────────────
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries'));
SELECT
    CASE WHEN @def LIKE '%Asiento no balanceado%' THEN 1 ELSE 0 END AS hasBalanceCheck,
    CASE WHEN @def LIKE '%UPDLOCK, HOLDLOCK%'     THEN 1 ELSE 0 END AS hasFolioLock,
    CASE WHEN @def LIKE '%POSTED -> VOID%'        THEN 1 ELSE 0 END AS hasVoidRule,
    CASE WHEN @def LIKE '%duplicado rechazado%'   THEN 1 ELSE 0 END AS alreadyHasGuard;

-- Existing duplicates in live data (expect 0 rows; the guard does not repair them).
SELECT companyId, referenceType, referenceId, COUNT(*) AS postedEntries
FROM dbo.journalEntries
WHERE status = 'POSTED' AND referenceId IS NOT NULL
  AND referenceType IN ('income', 'expense', 'income_commission')
GROUP BY companyId, referenceType, referenceId
HAVING COUNT(*) > 1;

IF @def IS NULL
   OR @def NOT LIKE '%Asiento no balanceado%'
   OR @def NOT LIKE '%UPDLOCK, HOLDLOCK%'
   OR @def NOT LIKE '%POSTED -> VOID%'
BEGIN
    RAISERROR('Live sp_journalEntries does not match the repo version — NOT altering. Compare OBJECT_DEFINITION with sql/sp_journalEntries.sql first.', 16, 1);
    SET NOEXEC ON;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    -- Sample payload (action=1 — post)
    DECLARE @pjsonfile NVARCHAR(MAX) = '
    {
      "journalEntries": [
        {
          "action": 1,
          "companyId": 1008,
          "entryDate": "2026-09-02",
          "description": "Venta #10234",
          "referenceType": "income",
          "referenceId": 10234,
          "createdByUserId": null,
          "lines": [
            { "accountId": 5,  "debit": 4500.00, "credit": 0,       "lineDescription": "Cobro en banco" },
            { "accountId": 12, "debit": 0,        "credit": 4500.00,"lineDescription": "Venta de producto" }
          ]
        }
      ]
    }';

    -- Sample payload (action=2 — void)
    DECLARE @pjsonfile NVARCHAR(MAX) = '
    {"journalEntries":[{"action":2,"entryId":123,"companyId":1008,"status":"VOID"}]}';
    */

    DECLARE @Error NVARCHAR(500) = N'';

    BEGIN TRY
        DECLARE @action    INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].action'));
        IF @action IS NULL RAISERROR('Invalid or missing action.', 16, 1);

        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId'));
        IF @companyId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.companies WHERE companyId = @companyId)
            RAISERROR('companyId es requerido y debe existir.', 16, 1);

        IF @action = 1
        BEGIN
            --------------------------------------------------------------
            -- Header
            --------------------------------------------------------------
            DECLARE
                @entryDate       DATE          = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].entryDate')),
                @description     NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].description'),
                @referenceType   NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.journalEntries[0].referenceType'),
                @referenceId     INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].referenceId')),
                @createdByUserId INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].createdByUserId'));

            IF @entryDate IS NULL OR @description IS NULL
                RAISERROR('entryDate y description son requeridos.', 16, 1);

            --------------------------------------------------------------
            -- Lines
            --------------------------------------------------------------
            DECLARE @Lines TABLE (
                idx             INT IDENTITY(1,1) PRIMARY KEY,
                accountId       INT           NOT NULL,
                debit           DECIMAL(12,2) NOT NULL,
                credit          DECIMAL(12,2) NOT NULL,
                lineDescription NVARCHAR(255) NULL
            );

            INSERT INTO @Lines (accountId, debit, credit, lineDescription)
            SELECT
                TRY_CONVERT(INT, JSON_VALUE(L.value, '$.accountId')),
                ISNULL(TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(L.value, '$.debit')), 0),
                ISNULL(TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(L.value, '$.credit')), 0),
                JSON_VALUE(L.value, '$.lineDescription')
            FROM OPENJSON(JSON_QUERY(@pjsonfile, '$.journalEntries[0].lines')) L;

            IF (SELECT COUNT(*) FROM @Lines) < 2
                RAISERROR('Un asiento contable necesita al menos 2 líneas (Debe y Haber).', 16, 1);

            IF EXISTS (SELECT 1 FROM @Lines WHERE accountId IS NULL)
                RAISERROR('Todas las líneas requieren accountId.', 16, 1);

            IF EXISTS (SELECT 1 FROM @Lines WHERE debit > 0 AND credit > 0)
                RAISERROR('Una línea no puede tener Debe y Haber al mismo tiempo.', 16, 1);

            IF EXISTS (SELECT 1 FROM @Lines WHERE debit = 0 AND credit = 0)
                RAISERROR('Cada línea debe tener un monto en Debe o en Haber.', 16, 1);

            IF EXISTS (
                SELECT 1 FROM @Lines Ln
                LEFT JOIN [dbo].[chartOfAccounts] A
                    ON A.accountId = Ln.accountId AND A.companyId = @companyId
                       AND A.isPostable = 1 AND A.isActive = 1
                WHERE A.accountId IS NULL
            )
                RAISERROR('Una o más accountId no son cuentas postulables activas de esta empresa.', 16, 1);

            DECLARE @sumDebit  DECIMAL(12,2) = (SELECT SUM(debit)  FROM @Lines);
            DECLARE @sumCredit DECIMAL(12,2) = (SELECT SUM(credit) FROM @Lines);

            IF ROUND(@sumDebit, 2) <> ROUND(@sumCredit, 2)
            BEGIN
                -- RAISERROR's %s placeholder only accepts (n)varchar args, never a
                -- DECIMAL directly — cast first or SQL Server rejects the RAISERROR itself.
                DECLARE @sumDebitStr  NVARCHAR(30) = CONVERT(NVARCHAR(30), @sumDebit);
                DECLARE @sumCreditStr NVARCHAR(30) = CONVERT(NVARCHAR(30), @sumCredit);
                RAISERROR('Asiento no balanceado: Debe (%s) <> Haber (%s).', 16, 1, @sumDebitStr, @sumCreditStr);
            END

            BEGIN TRAN;

            -- One POSTED entry per movement (Step 3, 2026-10-01): a retried
            -- auto-post hook or a backfill must never book the same income,
            -- expense or commission twice. VOID entries don't count, so a
            -- voided movement can be re-posted. The lock keeps two concurrent
            -- posts of the same reference from both passing the check.
            IF @referenceId IS NOT NULL
               AND @referenceType IN ('income', 'expense', 'income_commission')
               AND EXISTS (SELECT 1 FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                           WHERE companyId = @companyId AND referenceType = @referenceType
                             AND referenceId = @referenceId AND status = 'POSTED')
            BEGIN
                DECLARE @refStr NVARCHAR(60) = @referenceType + N' #' + CONVERT(NVARCHAR(20), @referenceId);
                RAISERROR('Ya existe un asiento POSTED para %s (duplicado rechazado).', 16, 1, @refStr);
            END

            -- Folio consecutivo por empresa; UPDLOCK+HOLDLOCK evita folios
            -- duplicados bajo inserciones concurrentes.
            DECLARE @entryNumber INT = (
                SELECT ISNULL(MAX(entryNumber), 0) + 1
                FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                WHERE companyId = @companyId
            );

            INSERT INTO [dbo].[journalEntries]
                (companyId, entryNumber, entryDate, description, referenceType, referenceId,
                 status, totalDebit, totalCredit, createdByUserId)
            VALUES
                (@companyId, @entryNumber, @entryDate, @description, @referenceType, @referenceId,
                 'POSTED', @sumDebit, @sumCredit, @createdByUserId);

            DECLARE @entryId INT = SCOPE_IDENTITY();

            INSERT INTO [dbo].[journalEntryLines] (journalEntryId, accountId, debit, credit, lineDescription)
            SELECT @entryId, accountId, debit, credit, lineDescription
            FROM @Lines;

            COMMIT TRAN;

            SELECT (SELECT TOP 1 entryId, companyId, entryNumber,
                           CONVERT(NVARCHAR, entryDate, 23) AS entryDate,
                           description, referenceType, referenceId, status,
                           totalDebit, totalCredit
                    FROM [dbo].[journalEntries]
                    WHERE entryId = @entryId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- VOID (única transición permitida: POSTED -> VOID)
        BEGIN
            DECLARE @entryIdToVoid INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].entryId'));
            DECLARE @newStatus     NVARCHAR(10) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].status');

            IF @entryIdToVoid IS NULL
                RAISERROR('entryId es requerido.', 16, 1);

            IF @newStatus IS NULL OR @newStatus <> 'VOID'
                RAISERROR('Solo se permite la transición POSTED -> VOID. entryDate/description/lines son inmutables una vez posteado.', 16, 1);

            IF NOT EXISTS (
                SELECT 1 FROM [dbo].[journalEntries]
                WHERE entryId = @entryIdToVoid AND companyId = @companyId AND status = 'POSTED'
            )
                RAISERROR('El asiento no existe, no pertenece a esta empresa, o ya no está POSTED.', 16, 1);

            UPDATE [dbo].[journalEntries]
            SET status = 'VOID', updated_at = GETUTCDATE()
            WHERE entryId = @entryIdToVoid AND companyId = @companyId;

            SELECT (SELECT TOP 1 entryId, entryNumber, status,
                           CONVERT(NVARCHAR, updated_at, 127) AS updated_at
                    FROM [dbo].[journalEntries]
                    WHERE entryId = @entryIdToVoid
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE — siempre rechazado
        BEGIN
            RAISERROR('DELETE no está permitido en journalEntries. Postea un asiento de reversión en su lugar.', 16, 1);
        END

        ELSE
            RAISERROR('Invalid action. Use 1=post, 2=void.', 16, 1);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        SET @Error = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- Verify (expect 1).
SELECT CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries')) LIKE '%duplicado rechazado%'
            THEN 1 ELSE 0 END AS duplicateGuardDeployed;
GO

SET NOEXEC OFF;
GO
