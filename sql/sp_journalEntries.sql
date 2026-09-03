-- ============================================================
-- sp_journalEntries  (action 1=post, 2=void, 3=REJECTED)
-- Asientos contables de partida doble — el registro central del
-- ciclo contable. Un asiento SIEMPRE debe cuadrar (Debe = Haber).
-- Spec: posgmo-factory/tests/prd_journalEntry.json
-- Requiere sql/sp_chartOfAccounts.sql (chartOfAccounts) ya aplicado.
-- ============================================================

-- ── Table: journalEntries (header) ──────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'journalEntries')
CREATE TABLE [dbo].[journalEntries] (
    entryId         INT IDENTITY PRIMARY KEY,
    companyId       INT            NOT NULL,
    entryNumber     INT            NOT NULL,  -- folio consecutivo por empresa
    entryDate       DATE           NOT NULL,
    description     NVARCHAR(255)  NOT NULL,
    referenceType   NVARCHAR(30)   NULL,      -- income | expense | manual | adjustment | opening_balance
    referenceId     INT            NULL,      -- income.incomeId / expenses.expenseId cuando aplica
    status          NVARCHAR(10)   NOT NULL DEFAULT 'POSTED',  -- POSTED | VOID
    -- Caché denormalizado de SUM(lines.debit)/SUM(lines.credit) al postear —
    -- la fuente de verdad siempre es journalEntryLines.
    totalDebit      DECIMAL(12,2)  NOT NULL DEFAULT 0,
    totalCredit     DECIMAL(12,2)  NOT NULL DEFAULT 0,
    createdByUserId INT            NULL,      -- NULL en asientos generados por el sistema
    created_At      DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2      NULL,
    CONSTRAINT CK_journalEntries_status CHECK (status IN ('POSTED','VOID'))
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_journalEntries_company_entryNumber')
    CREATE UNIQUE INDEX UQ_journalEntries_company_entryNumber
        ON [dbo].[journalEntries] (companyId, entryNumber);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_journalEntries_company_date')
    CREATE INDEX IX_journalEntries_company_date
        ON [dbo].[journalEntries] (companyId, entryDate DESC);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_journalEntries_reference')
    CREATE INDEX IX_journalEntries_reference
        ON [dbo].[journalEntries] (referenceType, referenceId);
GO

-- ── Table: journalEntryLines (Debe/Haber detail) ────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'journalEntryLines')
CREATE TABLE [dbo].[journalEntryLines] (
    journalEntryLineId INT IDENTITY PRIMARY KEY,
    journalEntryId      INT           NOT NULL,
    accountId            INT           NOT NULL,
    debit                DECIMAL(12,2) NOT NULL DEFAULT 0,
    credit               DECIMAL(12,2) NOT NULL DEFAULT 0,
    lineDescription      NVARCHAR(255) NULL,
    CONSTRAINT FK_journalEntryLines_entry
        FOREIGN KEY (journalEntryId) REFERENCES [dbo].[journalEntries](entryId),
    CONSTRAINT FK_journalEntryLines_account
        FOREIGN KEY (accountId) REFERENCES [dbo].[chartOfAccounts](accountId),
    -- Exactamente uno de (debit, credit) es > 0 por línea, nunca ambos, nunca ninguno.
    CONSTRAINT CK_journalEntryLines_oneSided
        CHECK (debit >= 0 AND credit >= 0 AND (debit + credit) > 0 AND (debit = 0 OR credit = 0))
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_journalEntryLines_entry')
    CREATE INDEX IX_journalEntryLines_entry
        ON [dbo].[journalEntryLines] (journalEntryId);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_journalEntryLines_account')
    CREATE INDEX IX_journalEntryLines_account
        ON [dbo].[journalEntryLines] (accountId);
GO

-- ============================================================
-- sp_journalEntries — action 1 acepta un array anidado "lines[]" en
-- @pjsonfile, igual patrón que sp_expense usa para products[]. La regla
-- de integridad más importante de todo el módulo: SUM(debit) debe ser
-- igual a SUM(credit) o el asiento completo se revierte.
-- ============================================================
IF OBJECT_ID('dbo.sp_journalEntries', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_journalEntries;
GO

CREATE PROCEDURE [dbo].[sp_journalEntries]
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

-- ============================================================
IF OBJECT_ID('dbo.sp_journalEntries_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_journalEntries_all;
GO
CREATE PROCEDURE [dbo].[sp_journalEntries_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    -- Libro Diario: lista de encabezados, sin líneas (usar sp_journalEntries_one
    -- para el drill-down Movimiento -> Asiento -> detalle).
    DECLARE @companyId     INT          = JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId')
    DECLARE @fromDate      DATE         = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].fromDate'))
    DECLARE @toDate        DATE         = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].toDate'))
    DECLARE @referenceType NVARCHAR(30) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].referenceType')
    DECLARE @status        NVARCHAR(10) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].status')

    SELECT ISNULL(
        (SELECT entryId, companyId, entryNumber,
                CONVERT(NVARCHAR, entryDate, 23) AS entryDate,
                description, referenceType, referenceId, status, totalDebit, totalCredit,
                createdByUserId,
                CONVERT(NVARCHAR, created_At, 127) AS created_At
         FROM [dbo].[journalEntries]
         WHERE companyId = @companyId
           AND (@fromDate IS NULL OR entryDate >= @fromDate)
           AND (@toDate IS NULL OR entryDate <= @toDate)
           AND (@referenceType IS NULL OR referenceType = @referenceType)
           AND (@status IS NULL OR status = @status)
         ORDER BY entryDate DESC, entryNumber DESC
         FOR JSON PATH, ROOT('journalEntries')),
        '{"journalEntries":[]}'
    ) AS [jsonResult]
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_journalEntries_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_journalEntries_one;
GO
CREATE PROCEDURE [dbo].[sp_journalEntries_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    -- Detalle del asiento: encabezado + líneas Debe/Haber con nombre de cuenta.
    -- Punto de entrada del drill-down Movimiento -> Asiento -> Libro Mayor.
    DECLARE @entryId INT = JSON_VALUE(@pjsonfile, '$.journalEntries[0].entryId')

    SELECT ISNULL(
        (SELECT TOP 1
                e.entryId, e.companyId, e.entryNumber,
                CONVERT(NVARCHAR, e.entryDate, 23) AS entryDate,
                e.description, e.referenceType, e.referenceId, e.status,
                e.totalDebit, e.totalCredit, e.createdByUserId,
                (SELECT l.journalEntryLineId, l.accountId, a.code AS accountCode,
                        a.name AS accountName, l.debit, l.credit, l.lineDescription
                 FROM [dbo].[journalEntryLines] l
                 JOIN [dbo].[chartOfAccounts] a ON a.accountId = l.accountId
                 WHERE l.journalEntryId = e.entryId
                 ORDER BY l.journalEntryLineId
                 FOR JSON PATH) AS lines
         FROM [dbo].[journalEntries] e
         WHERE e.entryId = @entryId
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        '{}'
    ) AS [jsonResult]
END
GO

-- ============================================================
-- sp_journalEntries_ledger — Libro Mayor (proyección de lectura, no
-- una tabla nueva): movimientos por cuenta con saldo corriente, dentro
-- de un rango de fechas. El frontend agrupa por accountId.
-- ============================================================
IF OBJECT_ID('dbo.sp_journalEntries_ledger', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_journalEntries_ledger;
GO
CREATE PROCEDURE [dbo].[sp_journalEntries_ledger]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT  = JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId')
    DECLARE @fromDate  DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].fromDate'))
    DECLARE @toDate    DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].toDate'))
    DECLARE @accountId INT  = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].accountId'))

    -- signedAmount: en cuentas de naturaleza deudora (D) un cargo suma y un
    -- abono resta; en cuentas de naturaleza acreedora (C) es al revés.
    SELECT ISNULL(
        (SELECT a.accountId, a.code AS accountCode, a.name AS accountName,
                a.accountType, a.normalBalance,
                e.entryId, e.entryNumber,
                CONVERT(NVARCHAR, e.entryDate, 23) AS entryDate,
                e.description, l.debit, l.credit,
                SUM(CASE WHEN a.normalBalance = 'D' THEN l.debit - l.credit ELSE l.credit - l.debit END)
                    OVER (PARTITION BY a.accountId ORDER BY e.entryDate, e.entryId, l.journalEntryLineId
                          ROWS UNBOUNDED PRECEDING) AS runningBalance
         FROM [dbo].[journalEntryLines] l
         JOIN [dbo].[journalEntries] e ON e.entryId = l.journalEntryId
         JOIN [dbo].[chartOfAccounts] a ON a.accountId = l.accountId
         WHERE e.companyId = @companyId
           AND e.status = 'POSTED'
           AND (@fromDate IS NULL OR e.entryDate >= @fromDate)
           AND (@toDate IS NULL OR e.entryDate <= @toDate)
           AND (@accountId IS NULL OR a.accountId = @accountId)
         ORDER BY a.code, e.entryDate, e.entryId
         FOR JSON PATH, ROOT('movements')),
        '{"movements":[]}'
    ) AS [jsonResult]
END
GO

-- ============================================================
-- sp_journalEntries_trialBalance — Balanza de Comprobación (proyección
-- de lectura): Debe y Haber acumulados por cuenta a una fecha de corte,
-- más el total general. "balanced" debe ser siempre true si los asientos
-- que la alimentan pasaron la validación de sp_journalEntries action=1.
-- ============================================================
IF OBJECT_ID('dbo.sp_journalEntries_trialBalance', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_journalEntries_trialBalance;
GO
CREATE PROCEDURE [dbo].[sp_journalEntries_trialBalance]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT  = JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId')
    DECLARE @toDate    DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].toDate'))

    DECLARE @accountsJson NVARCHAR(MAX) = (
        SELECT a.accountId, a.code AS accountCode, a.name AS accountName, a.accountType,
               a.normalBalance,
               ISNULL(SUM(l.debit), 0)  AS debitTotal,
               ISNULL(SUM(l.credit), 0) AS creditTotal
        FROM [dbo].[chartOfAccounts] a
        LEFT JOIN [dbo].[journalEntryLines] l ON l.accountId = a.accountId
        LEFT JOIN [dbo].[journalEntries] e
            ON e.entryId = l.journalEntryId AND e.status = 'POSTED'
               AND (@toDate IS NULL OR e.entryDate <= @toDate)
        WHERE a.companyId = @companyId AND a.isPostable = 1
        GROUP BY a.accountId, a.code, a.name, a.accountType, a.normalBalance
        HAVING ISNULL(SUM(l.debit), 0) <> 0 OR ISNULL(SUM(l.credit), 0) <> 0
        ORDER BY a.code
        FOR JSON PATH
    );

    DECLARE @totalDebit DECIMAL(14,2), @totalCredit DECIMAL(14,2);
    SELECT @totalDebit = ISNULL(SUM(l.debit), 0), @totalCredit = ISNULL(SUM(l.credit), 0)
    FROM [dbo].[journalEntryLines] l
    JOIN [dbo].[journalEntries] e ON e.entryId = l.journalEntryId
    WHERE e.companyId = @companyId AND e.status = 'POSTED'
      AND (@toDate IS NULL OR e.entryDate <= @toDate);

    SELECT
        ISNULL(@accountsJson, '[]') AS accountsJson,
        @totalDebit AS totalDebit,
        @totalCredit AS totalCredit,
        CASE WHEN ROUND(@totalDebit, 2) = ROUND(@totalCredit, 2) THEN 1 ELSE 0 END AS balanced
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
END
GO
