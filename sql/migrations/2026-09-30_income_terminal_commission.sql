-- =============================================================================
-- Store the card-terminal commission on every income row
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB, top to bottom.
--
-- WHY: card sales are charged a terminal commission (Mercado Pago, 4.2%,
-- dbo.commissionTerminals row 1) that was never recorded anywhere, so every
-- income figure on /dashboard overstated what actually reached the bank.
-- Storing it per sale — rate snapshot + amount — keeps history exact: a
-- future rate change applies to new sales only and never rewrites the past.
--
-- WHAT:
--   1. dbo.income: + commissionRatePct DECIMAL(6,3) NULL
--                  + commissionAmount  DECIMAL(10,2) NULL
--      NULL = no commission applies (cash / transfer). Net = total - ISNULL(commissionAmount, 0).
--   2. dbo.sp_income_applyCommission — stamps one sale ({"income":[{"incomeId":N}]})
--      ({"income":[{"incomeId":N,"commissionTerminalId":N?}]}) or backfills
--      every unstamped card sale ({"income":[{"backfill":1}]}).
--      Called by modules/income.py right after sp_income inserts a sale
--      (same best-effort hook pattern as the journal entry / reward points),
--      so sp_income itself — the sale path with the B2G1 promo engine — is
--      not touched.
--   3. Backfill: every existing card sale, at the current catalog rate (4.2%,
--      per the owner 2026-09-30: "apply it to all income paid with Tarjeta").
--   4. dbo.sp_income_monthly: also returns commissionTerminalId,
--      commissionRatePct, commissionAmount (body otherwise identical to
--      2026-09-29_income_monthly_any_month.sql).
--
-- RULES (sp_income_applyCommission):
--   - Card sale = paymentMethod IN ('tarjeta', 'terminal'). The POS cart
--     sends 'tarjeta'; 'terminal' is accepted for future/other clients.
--   - Terminal = income.commissionTerminalId if set, else the active terminal
--     the POS sent with the sale (hook passes it; sp_income drops it), else
--     the active catalog terminal whose paymentMethod = 'tarjeta' (lowest id). The chosen id is
--     written back, so every stamped row says which terminal charged it.
--   - commissionAmount = ROUND(total * rate / 100, 2) + ISNULL(fixedFeeAmount, 0).
--     income.total is the amount actually charged (sp_income already applied
--     any promo discount to it), which is what the terminal takes its cut of.
--   - Idempotent: only rows with commissionAmount IS NULL are touched, so a
--     retried hook or a re-run backfill never double-charges or re-prices.
-- Idempotent as a whole: column adds are guarded; SPs use CREATE OR ALTER.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ── 1. Columns ────────────────────────────────────────────────────────────
IF COL_LENGTH('dbo.income', 'commissionRatePct') IS NULL
    ALTER TABLE [dbo].[income] ADD [commissionRatePct] DECIMAL(6,3) NULL;
GO
IF COL_LENGTH('dbo.income', 'commissionAmount') IS NULL
    ALTER TABLE [dbo].[income] ADD [commissionAmount] DECIMAL(10,2) NULL;
GO

-- ── 2. Stamp SP ───────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE [dbo].[sp_income_applyCommission]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @incomeId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.income[0].incomeId'));
        DECLARE @backfill BIT = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.income[0].backfill')), 0);
        -- Terminal the POS says charged this sale (sp_income does not persist
        -- it, so the backend passes it through here). Ignored for backfill.
        DECLARE @requestedTerminalId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.income[0].commissionTerminalId'));

        IF @incomeId IS NULL AND @backfill = 0
        BEGIN
            SELECT '{"error":"incomeId (or backfill: 1) is required"}' AS [jsonResult];
            RETURN;
        END

        DECLARE @defaultTerminalId INT = (
            SELECT TOP 1 commissionTerminalId
            FROM dbo.commissionTerminals
            WHERE isActive = 1 AND LOWER(paymentMethod) = 'tarjeta'
            ORDER BY commissionTerminalId
        );
        IF @backfill = 0 AND @requestedTerminalId IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.commissionTerminals
                        WHERE commissionTerminalId = @requestedTerminalId AND isActive = 1)
            SET @defaultTerminalId = @requestedTerminalId;

        UPDATE i
           SET i.commissionTerminalId = t.commissionTerminalId,
               i.commissionRatePct    = t.commissionRatePct,
               i.commissionAmount     = ROUND(i.total * t.commissionRatePct / 100.0, 2)
                                        + ISNULL(t.fixedFeeAmount, 0)
          FROM dbo.income i
          JOIN dbo.commissionTerminals t
            ON t.commissionTerminalId = ISNULL(i.commissionTerminalId, @defaultTerminalId)
         WHERE LOWER(LTRIM(RTRIM(i.paymentMethod))) IN ('tarjeta', 'terminal')
           AND i.commissionAmount IS NULL
           AND i.total IS NOT NULL
           AND (@backfill = 1 OR i.incomeId = @incomeId);

        DECLARE @stamped INT = @@ROWCOUNT;

        IF @backfill = 1
            SELECT (SELECT @stamped AS stamped FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult];
        ELSE
            SELECT ISNULL(
                (SELECT incomeId, commissionTerminalId, commissionRatePct, commissionAmount
                   FROM dbo.income
                  WHERE incomeId = @incomeId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
                '{}'
            ) AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO

-- ── 3. Backfill every existing card sale ─────────────────────────────────
EXEC [dbo].[sp_income_applyCommission] @pjsonfile = N'{"income":[{"backfill":1}]}';
GO

-- Check: card sales left unstamped (expect 0 rows; a row here means no
-- active 'tarjeta' terminal exists in dbo.commissionTerminals).
SELECT incomeId, companyId, paymentMethod, total, commissionTerminalId
  FROM dbo.income
 WHERE LOWER(LTRIM(RTRIM(paymentMethod))) IN ('tarjeta', 'terminal')
   AND commissionAmount IS NULL;
GO

-- ── 4. sp_income_monthly returns the commission ───────────────────────────
CREATE OR ALTER PROC [dbo].[sp_income_monthly] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT, @year INT, @month INT;

    SELECT TOP 1
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @year      = TRY_CONVERT(INT, JSON_VALUE(value, '$.year')),
        @month     = TRY_CONVERT(INT, JSON_VALUE(value, '$.month'))
    FROM OPENJSON(@pjsonfile, '$.income');

    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    IF @year IS NULL OR @month IS NULL OR @month NOT BETWEEN 1 AND 12 OR @year NOT BETWEEN 2000 AND 2100
    BEGIN
        SET @year  = YEAR(@HermosilloNow);
        SET @month = MONTH(@HermosilloNow);
    END

    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7, DATEFROMPARTS(@year, @month, 1));
    DECLARE @MonthEndUtc   DATETIME = DATEADD(MONTH, 1, @MonthStartUtc);

    IF EXISTS (
        SELECT 1 FROM [dbo].[income]
        WHERE companyId = @companyId
          AND paymentDate >= @MonthStartUtc
          AND paymentDate < @MonthEndUtc
    )
    BEGIN
        SELECT
            i.incomeId,
            i.orderId,
            i.total,
            i.paymentMethod,
            i.paymentDate,
            i.userId,
            i.clientId,
            i.companyId,
            ISNULL(i.discountAmount,0) AS discountAmount,
            i.commissionTerminalId,
            i.commissionRatePct,
            ISNULL(i.commissionAmount,0) AS commissionAmount
        FROM [dbo].[income] i
        WHERE i.companyId = @companyId
          AND i.paymentDate >= @MonthStartUtc
          AND i.paymentDate < @MonthEndUtc
        FOR JSON AUTO, ROOT('income');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [income]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
GO
