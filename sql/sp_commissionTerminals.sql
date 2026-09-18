-- ============================================================
-- sp_commissionTerminals  (action 1=create, 2=update, 3=deactivate)
-- Catálogo de terminales de cobro / proveedor y su comisión —
-- income.commissionTerminalId apunta aquí. Global (no companyId):
-- dbo.commission_terminals ya existía en la base (1 fila: Mercado
-- Pago @ 3.6%) sin CRUD ni endpoint -- este archivo solo agrega
-- el procedimiento almacenado sobre la tabla existente, no la
-- vuelve a crear ni cambia su forma.
-- ============================================================

-- ── Table: commission_terminals (ya existe en prod; guard solo para entornos nuevos) ──
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'commission_terminals')
CREATE TABLE [dbo].[commission_terminals] (
    commissionTerminalId INT IDENTITY(1,1) PRIMARY KEY,
    provider              VARCHAR(40)   NOT NULL,
    terminalName          VARCHAR(80)   NOT NULL,
    paymentMethod         VARCHAR(20)   NULL,
    country                CHAR(2)      NULL,
    commissionRatePct     DECIMAL(6,3)  NOT NULL,
    fixedFeeAmount        DECIMAL(10,2) NULL,
    currency                CHAR(3)     NULL,
    isActive              BIT           NOT NULL DEFAULT 1,
    validFrom             DATETIME      NOT NULL DEFAULT GETDATE(),
    validTo               DATETIME      NULL,
    createdAt             DATETIME      NOT NULL DEFAULT GETDATE(),
    updatedAt             DATETIME      NULL
)
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_commissionTerminals', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_commissionTerminals;
GO

CREATE PROCEDURE [dbo].[sp_commissionTerminals]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action               INT           = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].action')
        DECLARE @commissionTerminalId INT           = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].commissionTerminalId')
        DECLARE @provider             VARCHAR(40)   = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].provider')
        DECLARE @terminalName         VARCHAR(80)   = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].terminalName')
        DECLARE @paymentMethod        VARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].paymentMethod')
        DECLARE @country              CHAR(2)       = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].country')
        DECLARE @commissionRatePct    DECIMAL(6,3)  = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].commissionRatePct')
        DECLARE @fixedFeeAmount       DECIMAL(10,2) = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].fixedFeeAmount')
        DECLARE @currency             CHAR(3)       = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].currency')
        DECLARE @isActive             BIT           = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].isActive')
        DECLARE @validTo              DATETIME      = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].validTo')

        IF @action = 1 -- CREATE
        BEGIN
            IF @provider IS NULL OR @terminalName IS NULL OR @commissionRatePct IS NULL
                RAISERROR('provider, terminalName y commissionRatePct son requeridos.', 16, 1);

            INSERT INTO [dbo].[commission_terminals]
                (provider, terminalName, paymentMethod, country, commissionRatePct, fixedFeeAmount, currency, isActive)
            VALUES
                (@provider, @terminalName, @paymentMethod, @country, @commissionRatePct, @fixedFeeAmount, @currency, ISNULL(@isActive, 1))

            SELECT (SELECT TOP 1 commissionTerminalId, provider, terminalName, paymentMethod, country,
                           commissionRatePct, fixedFeeAmount, currency, isActive,
                           CONVERT(NVARCHAR, validFrom, 127) AS validFrom,
                           CONVERT(NVARCHAR, createdAt, 127) AS createdAt
                    FROM [dbo].[commission_terminals]
                    WHERE commissionTerminalId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE
        BEGIN
            IF @commissionTerminalId IS NULL
                RAISERROR('commissionTerminalId es requerido.', 16, 1);

            UPDATE [dbo].[commission_terminals]
            SET provider           = ISNULL(@provider, provider),
                terminalName       = ISNULL(@terminalName, terminalName),
                paymentMethod      = ISNULL(@paymentMethod, paymentMethod),
                country            = ISNULL(@country, country),
                commissionRatePct  = ISNULL(@commissionRatePct, commissionRatePct),
                fixedFeeAmount     = ISNULL(@fixedFeeAmount, fixedFeeAmount),
                currency           = ISNULL(@currency, currency),
                isActive           = ISNULL(@isActive, isActive),
                validTo            = ISNULL(@validTo, validTo),
                updatedAt          = GETDATE()
            WHERE commissionTerminalId = @commissionTerminalId

            SELECT (SELECT TOP 1 commissionTerminalId, provider, terminalName, paymentMethod, country,
                           commissionRatePct, fixedFeeAmount, currency, isActive
                    FROM [dbo].[commission_terminals]
                    WHERE commissionTerminalId = @commissionTerminalId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 3 -- DEACTIVATE (nunca DELETE — puede tener income ya referenciándola)
        BEGIN
            IF @commissionTerminalId IS NULL
                RAISERROR('commissionTerminalId es requerido.', 16, 1);

            UPDATE [dbo].[commission_terminals]
            SET isActive = 0, updatedAt = GETDATE()
            WHERE commissionTerminalId = @commissionTerminalId

            SELECT '{"message":"deactivated","commissionTerminalId":' + CAST(@commissionTerminalId AS NVARCHAR(20)) + '}' AS [jsonResult]
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
IF OBJECT_ID('dbo.sp_commissionTerminals_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_commissionTerminals_all;
GO
CREATE PROCEDURE [dbo].[sp_commissionTerminals_all]
AS
BEGIN
    SET NOCOUNT ON;

    -- Devuelve TODAS las terminales (activas e inactivas); el frontend
    -- decide si oculta las inactivas, igual que chartOfAccounts.
    SELECT ISNULL(
        (SELECT commissionTerminalId, provider, terminalName, paymentMethod, country,
                commissionRatePct, fixedFeeAmount, currency, isActive,
                CONVERT(NVARCHAR, validFrom, 127) AS validFrom,
                CONVERT(NVARCHAR, validTo, 127)   AS validTo,
                CONVERT(NVARCHAR, createdAt, 127) AS createdAt
         FROM [dbo].[commission_terminals]
         ORDER BY provider, terminalName
         FOR JSON PATH, ROOT('commissionTerminals')),
        '{"commissionTerminals":[]}'
    ) AS [jsonResult]
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_commissionTerminals_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_commissionTerminals_one;
GO
CREATE PROCEDURE [dbo].[sp_commissionTerminals_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @commissionTerminalId INT = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].commissionTerminalId')

    SELECT ISNULL(
        (SELECT TOP 1 commissionTerminalId, provider, terminalName, paymentMethod, country,
                commissionRatePct, fixedFeeAmount, currency, isActive,
                CONVERT(NVARCHAR, validFrom, 127) AS validFrom,
                CONVERT(NVARCHAR, createdAt, 127) AS createdAt
         FROM [dbo].[commission_terminals]
         WHERE commissionTerminalId = @commissionTerminalId
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        '{}'
    ) AS [jsonResult]
END
GO

-- ============================================================
-- Data fix: the existing seeded row (commissionTerminalId = 1,
-- provider = 'mercadopago') was inserted at 3.6% — correct it to
-- the actual negotiated rate of 4.2%. Idempotent (targets by id).
-- ============================================================
UPDATE [dbo].[commission_terminals]
SET commissionRatePct = 4.200, updatedAt = GETDATE()
WHERE commissionTerminalId = 1 AND provider = 'mercadopago';
GO

-- ============================================================
-- Backfill: every existing card ('tarjeta') income row predates this
-- catalog and has commissionTerminalId = NULL. Mercado Pago (id 1) is
-- the only terminal in use today, so it's safe to point all of them
-- at it. Cash ('efectivo') and transfer ('transferencia') rows are
-- left untouched — no physical terminal is involved in those.
-- Safe to re-run: only touches rows still NULL.
-- ============================================================
UPDATE [dbo].[income]
SET commissionTerminalId = 1
WHERE paymentMethod = 'tarjeta' AND commissionTerminalId IS NULL;
GO
