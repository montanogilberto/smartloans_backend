-- =============================================================================
-- Add dbo.sp_income_one — single income row (total + applied promo discount)
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/income.py::_get_final_total_and_discount read back the
-- authoritative total/discountAmount/promotionCode (sp_income can recompute
-- total server-side for B2G1 promos) with a raw
-- "SELECT ... FROM dbo.income WHERE incomeId = %s". Backend rule: modules
-- never issue raw SQL — every read goes through an SP.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Factory convention: single @pjsonfile VARCHAR(MAX), fields pulled via
--     OPENJSON/JSON_VALUE. Caller passes
--     {"income":[{"incomeId": N, "companyId": N}]}, same root key as
--     sp_income/sp_income_all/sp_income_monthly.
--   - companyId is mandatory (multi-tenancy rule — never return
--     cross-company data).
--   - FOR JSON AUTO, ROOT('income'); no match → '[]' like sp_income_monthly.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_income_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN
    DECLARE @incomeId INT, @companyId INT;

    SELECT TOP 1
        @incomeId  = TRY_CONVERT(INT, JSON_VALUE(value, '$.incomeId')),
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId'))
    FROM OPENJSON(@pjsonfile, '$.income');

    IF EXISTS (
        SELECT 1 FROM [dbo].[income]
        WHERE incomeId = @incomeId AND companyId = @companyId
    )
    BEGIN
        SELECT
            i.incomeId,
            i.companyId,
            i.clientId,
            i.total,
            i.discountAmount,
            i.promotionCode
        FROM [dbo].[income] i
        WHERE i.incomeId = @incomeId
          AND i.companyId = @companyId
        FOR JSON AUTO, ROOT('income');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [income]
    END
END
GO
