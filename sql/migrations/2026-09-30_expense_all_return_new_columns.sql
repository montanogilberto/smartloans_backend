-- =============================================================================
-- dbo.sp_expense_all — return expenseType, employeeId, notes, receiptUrl
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database --
-- run manually against smartloansbackend's live DB.
--
-- WHY: 2026-09-02_add_expense_type_notes_receipturl.sql and
-- 2026-09-03_add_expense_payroll.sql both added columns to dbo.expenses
-- (expenseType, notes, receiptUrl, employeeId) but explicitly left
-- sp_expense_all's SELECT list unchanged (see that file's own note: "its
-- current definition wasn't available when either migration was written").
-- The columns exist and are populated (e.g. a payroll expense row has
-- expenseType='payroll', employeeId=1002), but GET /all_expense never
-- returned them -- the frontend's Egresos list always fell back to
-- expenseType='inventory' and a blank '-- ' company name for every payroll
-- row, since employeeId was never in the payload to resolve.
--
-- WHAT: adds expenseType, employeeId, notes, receiptUrl to the existing
-- SELECT list. No table changes -- those columns already exist live.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

CREATE OR ALTER PROC [dbo].[sp_expense_all]
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM [dbo].[expenses])
    BEGIN
        SELECT
            e.expenseId,
            e.orderId,
            e.total,
            e.paymentMethod,
            e.paymentDate,
            e.userId,
            e.supplierId,
            e.companyId,
            e.expenseType,
            e.employeeId,
            e.notes,
            e.receiptUrl
        FROM [dbo].[expenses] e
        FOR JSON AUTO, ROOT('expenses');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [expenses]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
GO
