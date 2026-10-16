-- =============================================================================
-- Add dbo.sp_income_monthly — current-month, single-company income read
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: GET /all_income (dbo.sp_income_all) returns every income row ever
-- recorded, across every company, with no filter at all. The POS Dashboard
-- only needs the current month's numbers for its own company, but was still
-- paying to transfer and parse the entire history (674+ rows and growing)
-- on every load/refresh. dbo.sp_income_all is left untouched — the Incomes
-- module (src/pages/finance/IncomesPage.tsx, MovementsPage.tsx) still needs
-- the full history for browsing/searching past records.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Factory convention: every SP (reads included) takes a single
--     @pjsonfile VARCHAR(MAX) and pulls its fields via JSON_VALUE/OPENJSON —
--     no typed SQL parameters. Caller passes {"income":[{"companyId": N}]},
--     matching the JSON root key sp_income/sp_income_all already use for
--     this module.
--   - companyId is mandatory (multi-tenancy rule — never return
--     cross-company data). sp_income_all's lack of a companyId filter is a
--     pre-existing gap this migration does not attempt to fix.
--   - "Current month" is computed in Hermosillo local time (UTC-7, no DST),
--     matching src/utils/format.ts::toHermosilloDate on the frontend — the
--     same convention used for every other monthly total in the app.
--     paymentDate is stored as UTC (no offset marker), so the month boundary
--     is converted back to UTC before filtering.
--   - Same output shape/columns as sp_income_all, so the frontend can reuse
--     its existing Income type.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_income_monthly] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN
    DECLARE @companyId INT;
    SET @companyId = TRY_CONVERT(INT,
        (SELECT TOP 1 JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.income'))
    );

    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7,
        DATEFROMPARTS(YEAR(@HermosilloNow), MONTH(@HermosilloNow), 1));
    DECLARE @MonthEndUtc DATETIME = DATEADD(MONTH, 1, @MonthStartUtc);

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
            ISNULL(i.discountAmount,0) AS discountAmount
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
