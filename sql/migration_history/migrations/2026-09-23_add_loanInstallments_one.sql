-- =============================================================================
-- Add dbo.sp_loanInstallments_one — one installment row, tenant-scoped
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: two modules read dbo.loanInstallments with raw SQL because
-- sp_loanInstallments' 'list' action omits clientId/lenderId/dueDate/paidAt:
--   - modules/automatedPayments.py::pay_installment_spei (ownership check +
--     lender counterpart before moving money)
--   - modules/rewardBenefits.py::_installment_is_on_time (on-time points)
-- Backend rule: modules never issue raw SQL — when an SP's projection is
-- missing columns, extend the SP layer instead of bypassing it.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Same convention as sp_loanInstallments: @pjsonfile NVARCHAR(MAX),
--     fields via JSON_VALUE on $.installments[0], one [jsonResult] column,
--     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER.
--   - Caller passes {"installments":[{"installmentId":N,"companyId":N,
--     "loanId":N}]}. installmentId + companyId required (multi-tenancy);
--     loanId optional (automatedPayments also pins the loan).
--   - Not found -> '{}'.
--   - dueDate / paidDate returned as 'YYYY-MM-DD' (the on-time rule compares
--     dates only; paidAt's time component was never used).
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_loanInstallments_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @installmentId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.installments[0].installmentId'));
        DECLARE @companyId     INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.installments[0].companyId'));
        DECLARE @loanId        INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.installments[0].loanId'));

        IF @installmentId IS NULL OR @companyId IS NULL
        BEGIN
            SELECT '{"error":"installmentId and companyId are required"}' AS [jsonResult];
            RETURN;
        END

        SELECT ISNULL(
            (SELECT installmentId, loanId, clientId, lenderId, companyId,
                    installmentNumber,
                    CONVERT(VARCHAR(10), dueDate, 23) AS dueDate,
                    amount, principal, interest, status, attemptCount,
                    CONVERT(VARCHAR(10), paidAt, 23)  AS paidDate
               FROM dbo.loanInstallments
              WHERE installmentId = @installmentId
                AND companyId     = @companyId
                AND (@loanId IS NULL OR loanId = @loanId)
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
            '{}'
        ) AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO
