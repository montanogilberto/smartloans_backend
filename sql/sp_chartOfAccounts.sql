-- ============================================================
-- sp_chartOfAccounts  (action 1=create, 2=update, 3=deactivate)
-- Catálogo de cuentas contables (plan de cuentas) por empresa —
-- la base contra la que se registran todos los journalEntries.
-- Spec: posgmo-factory/tests/prd_chartOfAccount.json
-- Módulo Contabilidad (Dashboard/Movimientos/Libro Diario/Libro
-- Mayor/Balanza/Reportes) — ver también sql/sp_journalEntries.sql.
-- ============================================================

-- ── Table: chartOfAccounts ──────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'chartOfAccounts')
CREATE TABLE [dbo].[chartOfAccounts] (
    accountId       INT IDENTITY PRIMARY KEY,
    companyId       INT            NOT NULL,
    code            NVARCHAR(20)   NOT NULL,
    name            NVARCHAR(150)  NOT NULL,
    accountType     NVARCHAR(20)   NOT NULL,  -- ASSET | LIABILITY | EQUITY | INCOME | EXPENSE
    normalBalance   NVARCHAR(1)    NOT NULL,  -- D (deudora) | C (acreedora) — derivado de accountType, nunca confiar en el valor del cliente
    -- Auto-referencia para la jerarquía Clase > Grupo > Cuenta > Subcuenta.
    -- Sin FK real: bloquearía el seed multi-nivel de una empresa nueva en un
    -- solo statement por statement; se valida la existencia en el SP.
    parentAccountId INT            NULL,
    level           INT            NULL,      -- 1 Clase, 2 Grupo, 3 Cuenta, 4 Subcuenta
    isPostable      BIT            NOT NULL DEFAULT 1,  -- false en cuentas de agrupación (Clase/Grupo)
    isActive        BIT            NOT NULL DEFAULT 1,  -- se desactiva, nunca se borra (rompería el historial de asientos)
    created_At      DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2      NULL,
    CONSTRAINT CK_chartOfAccounts_accountType
        CHECK (accountType IN ('ASSET','LIABILITY','EQUITY','INCOME','EXPENSE')),
    CONSTRAINT CK_chartOfAccounts_normalBalance
        CHECK (normalBalance IN ('D','C'))
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_chartOfAccounts_company_code')
    CREATE UNIQUE INDEX UQ_chartOfAccounts_company_code
        ON [dbo].[chartOfAccounts] (companyId, code);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_chartOfAccounts_company_type')
    CREATE INDEX IX_chartOfAccounts_company_type
        ON [dbo].[chartOfAccounts] (companyId, accountType, isActive);
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_chartOfAccounts', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_chartOfAccounts;
GO

CREATE PROCEDURE [dbo].[sp_chartOfAccounts]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action          INT           = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].action')
        DECLARE @accountId       INT           = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].accountId')
        DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].companyId')
        DECLARE @code            NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].code')
        DECLARE @name            NVARCHAR(150) = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].name')
        DECLARE @accountType     NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].accountType')
        DECLARE @parentAccountId INT           = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].parentAccountId')
        DECLARE @level           INT           = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].level')
        DECLARE @isPostable      BIT           = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].isPostable')
        DECLARE @isActive        BIT           = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].isActive')

        IF @action = 1 -- CREATE
        BEGIN
            IF @companyId IS NULL OR @code IS NULL OR @name IS NULL OR @accountType IS NULL
                RAISERROR('companyId, code, name y accountType son requeridos.', 16, 1);

            IF @accountType NOT IN ('ASSET','LIABILITY','EQUITY','INCOME','EXPENSE')
                RAISERROR('accountType inválido. Use ASSET, LIABILITY, EQUITY, INCOME o EXPENSE.', 16, 1);

            IF @parentAccountId IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM [dbo].[chartOfAccounts]
                WHERE accountId = @parentAccountId AND companyId = @companyId
            )
                RAISERROR('parentAccountId no existe para esta empresa.', 16, 1);

            -- normalBalance siempre se deriva de accountType — nunca del payload del cliente.
            DECLARE @normalBalance NVARCHAR(1) =
                CASE WHEN @accountType IN ('ASSET','EXPENSE') THEN 'D' ELSE 'C' END;

            INSERT INTO [dbo].[chartOfAccounts]
                (companyId, code, name, accountType, normalBalance, parentAccountId, level, isPostable, isActive)
            VALUES
                (@companyId, @code, @name, @accountType, @normalBalance, @parentAccountId, @level,
                 ISNULL(@isPostable, 1), ISNULL(@isActive, 1))

            SELECT (SELECT TOP 1 accountId, companyId, code, name, accountType, normalBalance,
                           parentAccountId, level, isPostable, isActive,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[chartOfAccounts]
                    WHERE accountId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE (name/jerarquía/estado — nunca code/accountType/normalBalance)
        BEGIN
            IF @accountId IS NULL OR @companyId IS NULL
                RAISERROR('accountId y companyId son requeridos.', 16, 1);

            IF @parentAccountId IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM [dbo].[chartOfAccounts]
                WHERE accountId = @parentAccountId AND companyId = @companyId
            )
                RAISERROR('parentAccountId no existe para esta empresa.', 16, 1);

            UPDATE [dbo].[chartOfAccounts]
            SET name            = ISNULL(@name, name),
                parentAccountId = ISNULL(@parentAccountId, parentAccountId),
                level           = ISNULL(@level, level),
                isPostable      = ISNULL(@isPostable, isPostable),
                isActive        = ISNULL(@isActive, isActive),
                updated_at      = GETUTCDATE()
            WHERE accountId = @accountId AND companyId = @companyId

            SELECT (SELECT TOP 1 accountId, code, name, accountType, normalBalance,
                           parentAccountId, level, isPostable, isActive
                    FROM [dbo].[chartOfAccounts]
                    WHERE accountId = @accountId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 3 -- DEACTIVATE (nunca DELETE — la cuenta puede ya tener journalEntryLines)
        BEGIN
            UPDATE [dbo].[chartOfAccounts]
            SET isActive = 0, updated_at = GETUTCDATE()
            WHERE accountId = @accountId AND companyId = @companyId

            SELECT '{"message":"deactivated","accountId":' + CAST(@accountId AS NVARCHAR(20)) + '}' AS [jsonResult]
        END

        ELSE
            SELECT '{"error":"Invalid action"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_chartOfAccounts_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_chartOfAccounts_all;
GO
CREATE PROCEDURE [dbo].[sp_chartOfAccounts_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId   INT          = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].companyId')
    DECLARE @accountType NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].accountType')

    -- Devuelve TODAS las cuentas (activas e inactivas) para que el Catálogo
    -- pueda mostrar el badge de estado; el frontend decide si las oculta.
    SELECT ISNULL(
        (SELECT accountId, companyId, code, name, accountType, normalBalance,
                parentAccountId, level, isPostable, isActive,
                CONVERT(NVARCHAR, created_At, 127) AS created_At
         FROM [dbo].[chartOfAccounts]
         WHERE companyId = @companyId
           AND (@accountType IS NULL OR accountType = @accountType)
         ORDER BY code
         FOR JSON PATH, ROOT('chartOfAccounts')),
        '{"chartOfAccounts":[]}'
    ) AS [jsonResult]
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_chartOfAccounts_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_chartOfAccounts_one;
GO
CREATE PROCEDURE [dbo].[sp_chartOfAccounts_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @accountId INT = JSON_VALUE(@pjsonfile, '$.chartOfAccounts[0].accountId')

    SELECT ISNULL(
        (SELECT TOP 1 accountId, companyId, code, name, accountType, normalBalance,
                parentAccountId, level, isPostable, isActive,
                CONVERT(NVARCHAR, created_At, 127) AS created_At
         FROM [dbo].[chartOfAccounts]
         WHERE accountId = @accountId
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        '{}'
    ) AS [jsonResult]
END
GO

-- ============================================================
-- sp_chartOfAccounts_seed  — catálogo base de una empresa ("ensure base").
-- Inserta SOLO las cuentas base cuyo código le falte a la empresa: nunca
-- actualiza ni borra una cuenta existente, no toca cuentas propias de la
-- empresa, y una segunda ejecución no inserta nada. (Hasta 2026-10-01 no
-- hacía nada si la empresa ya tenía cualquier cuenta — así no podía agregar
-- 1101 Caja / 3205 / 3210; ver sql/migrations/2026-10-01c_chartOfAccounts_ensure_base.sql.)
-- Hoy no existe hook de alta de empresa, así que este archivo la corre para
-- cada empresa existente (ver abajo).
-- ============================================================
IF OBJECT_ID('dbo.sp_chartOfAccounts_seed', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_chartOfAccounts_seed;
GO
CREATE PROCEDURE [dbo].[sp_chartOfAccounts_seed]
    @companyId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF @companyId IS NULL RETURN;

    DECLARE @base TABLE (
        code NVARCHAR(20), name NVARCHAR(150), accountType NVARCHAR(20),
        normalBalance NVARCHAR(1), parentCode NVARCHAR(20) NULL, isPostable BIT, level INT
    );
    INSERT INTO @base (code, name, accountType, normalBalance, parentCode, isPostable, level) VALUES
        ('1',    'ACTIVO',                              'ASSET',     'D', NULL, 0, 1),
        ('2',    'PASIVO',                              'LIABILITY', 'C', NULL, 0, 1),
        ('3',    'CAPITAL',                             'EQUITY',    'C', NULL, 0, 1),
        ('4',    'INGRESOS',                            'INCOME',    'C', NULL, 0, 1),
        ('5',    'GASTOS',                              'EXPENSE',   'D', NULL, 0, 1),
        ('1101', 'Caja',                                'ASSET',     'D', '1',  1, 2),
        ('1105', 'Bancos',                              'ASSET',     'D', '1',  1, 2),
        ('2105', 'Cuentas por pagar',                   'LIABILITY', 'C', '2',  1, 2),
        ('3105', 'Capital social',                      'EQUITY',    'C', '3',  1, 2),
        ('3205', 'Resultados de ejercicios anteriores', 'EQUITY',    'C', '3',  1, 2),
        ('3210', 'Resultado del ejercicio',             'EQUITY',    'C', '3',  1, 2),
        ('4105', 'Ingresos por ventas',                 'INCOME',    'C', '4',  1, 2),
        ('4110', 'Intereses ganados',                   'INCOME',    'C', '4',  1, 2),
        ('4115', 'Comisiones cobradas',                 'INCOME',    'C', '4',  1, 2),
        ('4199', 'Otros ingresos',                      'INCOME',    'C', '4',  1, 2),
        ('5105', 'Gastos de operación',                 'EXPENSE',   'D', '5',  1, 2),
        ('5110', 'Nómina',                              'EXPENSE',   'D', '5',  1, 2),
        ('5115', 'Servicios',                           'EXPENSE',   'D', '5',  1, 2),
        ('5120', 'Comisiones bancarias',                'EXPENSE',   'D', '5',  1, 2),
        ('5199', 'Otros gastos',                        'EXPENSE',   'D', '5',  1, 2);

    -- Classes (level 1) the company is missing.
    INSERT INTO [dbo].[chartOfAccounts] (companyId, code, name, accountType, normalBalance, isPostable, level)
    SELECT @companyId, b.code, b.name, b.accountType, b.normalBalance, b.isPostable, b.level
    FROM @base b
    WHERE b.parentCode IS NULL
      AND NOT EXISTS (SELECT 1 FROM [dbo].[chartOfAccounts] a
                      WHERE a.companyId = @companyId AND a.code = b.code);

    -- Leaves the company is missing, under its class.
    INSERT INTO [dbo].[chartOfAccounts] (companyId, code, name, accountType, normalBalance, parentAccountId, isPostable, level)
    SELECT @companyId, b.code, b.name, b.accountType, b.normalBalance, p.accountId, b.isPostable, b.level
    FROM @base b
    JOIN [dbo].[chartOfAccounts] p ON p.companyId = @companyId AND p.code = b.parentCode
    WHERE b.parentCode IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM [dbo].[chartOfAccounts] a
                      WHERE a.companyId = @companyId AND a.code = b.code);
END
GO

-- ============================================================
-- Backfill: asegura el catálogo base para cada empresa existente (agrega
-- solo las cuentas base que le falten). Seguro de re-ejecutar
-- (sp_chartOfAccounts_seed es idempotente por empresa).
-- ============================================================
DECLARE @seedCompanyId INT;
DECLARE seed_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT companyId FROM dbo.companies;
OPEN seed_cursor;
FETCH NEXT FROM seed_cursor INTO @seedCompanyId;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @seedCompanyId;
    FETCH NEXT FROM seed_cursor INTO @seedCompanyId;
END
CLOSE seed_cursor;
DEALLOCATE seed_cursor;
GO
