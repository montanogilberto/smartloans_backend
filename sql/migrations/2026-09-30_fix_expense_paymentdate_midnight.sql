-- =============================================================================
-- Fix: expenses entered through the Egresos form show one day early
-- =============================================================================
-- Forward-only data fix. NOT YET EXECUTED — run manually against the live DB.
--
-- WHY: ExpenseForm sent `new Date('2026-09-29').toISOString()` — UTC midnight
-- of the picked Hermosillo day. paymentDate is read as UTC everywhere
-- (sp_expense_monthly, the frontend's toHermosilloDate), so 2026-09-29 00:00Z
-- = Sept 28 17:00 in Hermosillo (UTC-7): every form expense displayed a day
-- early, and one dated the 1st was counted in the previous month.
-- The form now sends that day's Hermosillo noon (`YYYY-MM-DDT19:00:00Z`).
--
-- WHICH ROWS: paymentDate exactly at 00:00:00.000. Only the form produced that
-- (CartPage and the backend use real timestamps); the stored DATE part IS the
-- day the user picked, so it is kept and moved to 19:00 UTC (noon Hermosillo).
-- journalEntries need no change: the accounting auto-post took the first 10
-- chars of the request ('YYYY-MM-DD'), which was already the picked day.
--
-- Idempotent: fixed rows are no longer at midnight, a re-run touches nothing.
-- =============================================================================

-- 1) Preview: rows that will change, with their new value.
SELECT expenseId, companyId, expenseType, total,
       paymentDate                                                       AS oldPaymentDate,
       DATEADD(HOUR, 19, CAST(CAST(paymentDate AS DATE) AS DATETIME))    AS newPaymentDate
FROM dbo.expenses
WHERE CAST(paymentDate AS TIME) = '00:00:00'
ORDER BY paymentDate;
GO

-- 2) Fix.
BEGIN TRANSACTION;

UPDATE dbo.expenses
SET paymentDate = DATEADD(HOUR, 19, CAST(CAST(paymentDate AS DATE) AS DATETIME))
WHERE CAST(paymentDate AS TIME) = '00:00:00';

SELECT @@ROWCOUNT AS rowsFixed;   -- should equal the preview's row count

COMMIT TRANSACTION;
GO

-- 3) Verify: 0 rows left at midnight.
SELECT COUNT(*) AS stillMidnight
FROM dbo.expenses
WHERE CAST(paymentDate AS TIME) = '00:00:00';
GO
