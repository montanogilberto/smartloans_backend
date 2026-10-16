-- =============================================================================
-- Company token ledger — prepaid AI-token balance per company
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB.
--
-- WHY: reading a ticket / chatting with a support agent costs real Gemini
-- tokens, and nothing recorded them (the agents service never stored usage; the
-- agentCostLog PRD was authored but never built). The POS needs to show how many
-- tokens each company has left.
--
-- WHAT: one APPEND-ONLY ledger. Top-ups are positive rows, each agent call is a
-- negative row carrying its real input/output/thought token counts. The balance
-- is SUM(tokensDelta), so the usage log and the balance can never disagree and a
-- correction is a new 'adjustment' row, never an edit.
--   * dbo.companyTokenLedger
--   * sp_companyTokens_record   — one agent call's usage (called by LoanAgents)
--   * sp_companyTokens_topup    — add tokens to a company's balance
--   * sp_companyTokens_balance  — balance + used today / this month (Hermosillo)
-- All JSON in / JSON out via @pjsonfile like the rest of the codebase.
-- Starts at balance 0: nothing is granted automatically — top up explicitly.
-- ROLLBACK: DROP the three procedures, then the table (loses the ledger).
-- =============================================================================

IF OBJECT_ID('dbo.companyTokenLedger', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.companyTokenLedger (
        ledgerId       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_companyTokenLedger PRIMARY KEY,
        companyId      INT            NOT NULL,
        -- + top-up / adjustment in, - usage out
        tokensDelta    BIGINT         NOT NULL,
        entryType      VARCHAR(20)    NOT NULL,
        agentName      NVARCHAR(100)  NULL,
        endpointName   NVARCHAR(100)  NULL,
        model          NVARCHAR(100)  NULL,
        inputTokens    INT            NULL,
        outputTokens   INT            NULL,
        thoughtsTokens INT            NULL,
        reference      NVARCHAR(100)  NULL,
        notes          NVARCHAR(300)  NULL,
        createdBy      INT            NULL,
        createdAt      DATETIME       NOT NULL CONSTRAINT DF_companyTokenLedger_createdAt DEFAULT GETUTCDATE(),
        CONSTRAINT CK_companyTokenLedger_type CHECK (entryType IN ('topup', 'usage', 'adjustment')),
        CONSTRAINT FK_companyTokenLedger_company FOREIGN KEY (companyId) REFERENCES dbo.companies (companyId)
    );
    CREATE INDEX IX_companyTokenLedger_company_date ON dbo.companyTokenLedger (companyId, createdAt) INCLUDE (tokensDelta, entryType);
END
GO

CREATE OR ALTER PROC [dbo].[sp_companyTokens_record] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT, @agentName NVARCHAR(100), @endpointName NVARCHAR(100), @model NVARCHAR(100),
            @input INT, @output INT, @thoughts INT, @reference NVARCHAR(100);

    SELECT TOP 1
        @companyId    = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @agentName    = JSON_VALUE(value, '$.agentName'),
        @endpointName = JSON_VALUE(value, '$.endpointName'),
        @model        = JSON_VALUE(value, '$.model'),
        @input        = TRY_CONVERT(INT, JSON_VALUE(value, '$.inputTokens')),
        @output       = TRY_CONVERT(INT, JSON_VALUE(value, '$.outputTokens')),
        @thoughts     = TRY_CONVERT(INT, JSON_VALUE(value, '$.thoughtsTokens')),
        @reference    = JSON_VALUE(value, '$.reference')
    FROM OPENJSON(@pjsonfile, '$.tokens');

    IF @companyId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.companies WHERE companyId = @companyId)
    BEGIN
        SELECT CAST(0 AS BIT) AS recorded, N'companyId inválido' AS error FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    DECLARE @total BIGINT = COALESCE(@input, 0) + COALESCE(@output, 0) + COALESCE(@thoughts, 0);
    IF @total <= 0
    BEGIN
        SELECT CAST(0 AS BIT) AS recorded, N'sin tokens que registrar' AS error FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    INSERT INTO dbo.companyTokenLedger
        (companyId, tokensDelta, entryType, agentName, endpointName, model, inputTokens, outputTokens, thoughtsTokens, reference)
    VALUES
        (@companyId, -@total, 'usage', @agentName, @endpointName, @model, @input, @output, @thoughts, @reference);

    SELECT CAST(1 AS BIT) AS recorded,
           @total AS tokens,
           (SELECT SUM(tokensDelta) FROM dbo.companyTokenLedger WHERE companyId = @companyId) AS balance
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO

CREATE OR ALTER PROC [dbo].[sp_companyTokens_topup] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT, @tokens BIGINT, @notes NVARCHAR(300), @userId INT, @entryType VARCHAR(20);

    SELECT TOP 1
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @tokens    = TRY_CONVERT(BIGINT, JSON_VALUE(value, '$.tokens')),
        @notes     = JSON_VALUE(value, '$.notes'),
        @userId    = TRY_CONVERT(INT, JSON_VALUE(value, '$.userId')),
        @entryType = COALESCE(JSON_VALUE(value, '$.entryType'), 'topup')
    FROM OPENJSON(@pjsonfile, '$.tokens');

    IF @companyId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.companies WHERE companyId = @companyId)
    BEGIN
        SELECT CAST(0 AS BIT) AS ok, N'companyId inválido' AS error FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END
    -- A top-up must add; only an explicit 'adjustment' may carry a negative correction.
    IF @tokens IS NULL OR @tokens = 0 OR (@tokens < 0 AND @entryType <> 'adjustment') OR @entryType NOT IN ('topup', 'adjustment')
    BEGIN
        SELECT CAST(0 AS BIT) AS ok, N'tokens inválidos' AS error FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    INSERT INTO dbo.companyTokenLedger (companyId, tokensDelta, entryType, notes, createdBy)
    VALUES (@companyId, @tokens, @entryType, @notes, @userId);

    SELECT CAST(1 AS BIT) AS ok,
           (SELECT SUM(tokensDelta) FROM dbo.companyTokenLedger WHERE companyId = @companyId) AS balance
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO

CREATE OR ALTER PROC [dbo].[sp_companyTokens_balance] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')) FROM OPENJSON(@pjsonfile, '$.tokens'));

    IF @companyId IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS ok, N'companyId requerido' AS error FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    -- "Today" and "this month" are Hermosillo calendar periods (UTC-7, no DST).
    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    DECLARE @TodayStartUtc DATETIME = DATEADD(HOUR, 7, CAST(CAST(@HermosilloNow AS DATE) AS DATETIME));
    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7, CAST(DATEFROMPARTS(YEAR(@HermosilloNow), MONTH(@HermosilloNow), 1) AS DATETIME));

    SELECT
        CAST(1 AS BIT) AS ok,
        @companyId AS companyId,
        COALESCE(SUM(tokensDelta), 0) AS balance,
        COALESCE(-SUM(CASE WHEN entryType = 'usage' AND createdAt >= @TodayStartUtc THEN tokensDelta END), 0) AS usedToday,
        COALESCE(-SUM(CASE WHEN entryType = 'usage' AND createdAt >= @MonthStartUtc THEN tokensDelta END), 0) AS usedThisMonth,
        COALESCE(SUM(CASE WHEN entryType = 'usage' AND createdAt >= @MonthStartUtc THEN 1 ELSE 0 END), 0) AS callsThisMonth,
        (SELECT TOP 1 tokensDelta FROM dbo.companyTokenLedger WHERE companyId = @companyId AND entryType = 'topup' ORDER BY createdAt DESC, ledgerId DESC) AS lastTopupTokens,
        (SELECT TOP 1 createdAt   FROM dbo.companyTokenLedger WHERE companyId = @companyId AND entryType = 'topup' ORDER BY createdAt DESC, ledgerId DESC) AS lastTopupAt
    FROM dbo.companyTokenLedger
    WHERE companyId = @companyId
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO
