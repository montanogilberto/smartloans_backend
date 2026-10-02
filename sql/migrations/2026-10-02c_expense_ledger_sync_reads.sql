-- =============================================================================
-- Reads for the expense -> ledger sync, as SPs (no raw SQL in modules/)
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB, BEFORE deploying the
-- backend that calls these SPs (modules/journalEntries.py).
--
-- WHY: modules/journalEntries.py::_fetch_expense and
-- ::_fetch_posted_expense_entries (expense edit/delete -> ledger, "expenses
-- module v7") read dbo.expenses / dbo.journalEntries with raw SELECTs.
-- Backend rule: modules never issue raw SQL — only EXEC [dbo].[sp_*].
-- scripts/check_raw_sql.py flags both, which fails the deploy build on main.
--
-- SCOPE: two new read-only SPs, no table/column changes. Same convention as
-- sp_journalEntries / sp_journalEntries_one: @pjsonfile NVARCHAR(MAX), fields
-- via JSON_VALUE on $.<root>[0], one [jsonResult] column, FOR JSON PATH.
--
--   sp_expense_one  {"expenses":[{"expenseId":N,"companyId":N}]}
--     -> {"expenseId","companyId","total","paymentMethod","expenseType"}
--        or '{}' when the expense no longer exists (deleted) or belongs to
--        another company.
--
--   sp_journalEntries_byReference
--        {"journalEntries":[{"companyId":N,"referenceType":"expense",
--                            "referenceId":N,"status":"POSTED"}]}  (status optional)
--     -> [{"entryId","companyId","entryDate":"YYYY-MM-DD","amount",
--          "debitCode","creditCode"}, ...] ordered by entryId, or '[]'.
--        debitCode/creditCode = the account code of the first debit / credit
--        line — the 2-line shape the auto-post writes.
--
-- companyId is REQUIRED and filters both reads (multi-tenancy rule: never
-- return cross-company data). The backend passes the companyId of the
-- expense request being synced. Consequence, accepted 2026-10-02: an expense
-- moved to another company (sp_expense action 2 can still overwrite
-- companyId) is not followed across companies — its old company's entry is
-- left as-is. Closing that hole belongs in sp_expense (scope action 2/3 by
-- companyId and stop it changing companyId), not in these reads.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_expense_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @expenseId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].expenseId'));
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].companyId'));

        IF @expenseId IS NULL OR @companyId IS NULL
        BEGIN
            SELECT '{"error":"expenseId and companyId are required"}' AS [jsonResult];
            RETURN;
        END

        SELECT ISNULL(
            (SELECT expenseId, companyId, total, paymentMethod, expenseType
               FROM dbo.expenses
              WHERE expenseId = @expenseId
                AND companyId = @companyId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
            '{}'
        ) AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_byReference]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId     INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId'));
        DECLARE @referenceType NVARCHAR(30) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].referenceType');
        DECLARE @referenceId   INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].referenceId'));
        DECLARE @status        NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].status');

        IF @companyId IS NULL OR @referenceType IS NULL OR @referenceId IS NULL
        BEGIN
            SELECT '{"error":"companyId, referenceType and referenceId are required"}' AS [jsonResult];
            RETURN;
        END

        SELECT ISNULL(
            (SELECT e.entryId,
                    e.companyId,
                    CONVERT(VARCHAR(10), e.entryDate, 23) AS entryDate,
                    e.totalDebit AS amount,
                    (SELECT TOP 1 c.code
                       FROM dbo.journalEntryLines l
                       JOIN dbo.chartOfAccounts c ON c.accountId = l.accountId
                      WHERE l.journalEntryId = e.entryId AND l.debit > 0
                      ORDER BY l.journalEntryLineId) AS debitCode,
                    (SELECT TOP 1 c.code
                       FROM dbo.journalEntryLines l
                       JOIN dbo.chartOfAccounts c ON c.accountId = l.accountId
                      WHERE l.journalEntryId = e.entryId AND l.credit > 0
                      ORDER BY l.journalEntryLineId) AS creditCode
               FROM dbo.journalEntries e
              WHERE e.companyId     = @companyId
                AND e.referenceType = @referenceType
                AND e.referenceId   = @referenceId
                AND (@status IS NULL OR e.status = @status)
              ORDER BY e.entryId
             FOR JSON PATH, INCLUDE_NULL_VALUES),
            '[]'
        ) AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO
