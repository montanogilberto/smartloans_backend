-- incomePayments: itemized payment-method breakdown for a split-payment
-- sale (e.g. 60% Efectivo + 40% Tarjeta on one ticket). dbo.income.total and
-- dbo.income.paymentMethod stay as the single source of truth for the sale
-- total and a summary label ("Dividido" for a split sale) -- this table adds
-- the itemized detail underneath, same split as sp_clientLoginCodes's
-- "business logic in Python, storage in a plain proc" pattern used
-- elsewhere in this backend.
--
-- KNOWN GAP (2026-10-01): card-terminal commission journaling
-- (modules/income.py::_apply_terminal_commission /
-- post_income_commission_journal_entry) only fires when
-- income.paymentMethod is exactly 'tarjeta'/'terminal'. A split sale's
-- paymentMethod is 'Dividido', so the card portion of a split payment does
-- NOT get a commission journal entry yet -- deliberate v1 scope, not an
-- oversight. Fix in a follow-up once the commission math for a partial
-- card amount (not the full income.total) is worked out.

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'incomePayments')
CREATE TABLE [dbo].[incomePayments] (
    incomePaymentId INT IDENTITY(1,1) NOT NULL,
    incomeId        INT NOT NULL,
    method          VARCHAR(20) NOT NULL,   -- 'efectivo' | 'tarjeta' | 'transferir'
    amount          DECIMAL(10,2) NOT NULL,
    cashPaid        DECIMAL(10,2) NULL,     -- only meaningful for method='efectivo'
    cashReturn      DECIMAL(10,2) NULL,
    created_At      DATETIME2(7) NOT NULL DEFAULT (GETUTCDATE()),
    CONSTRAINT PK_incomePayments PRIMARY KEY CLUSTERED (incomePaymentId)
);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_incomePayments_incomeId' AND object_id = OBJECT_ID('dbo.incomePayments'))
CREATE NONCLUSTERED INDEX IX_incomePayments_incomeId ON dbo.incomePayments (incomeId);
GO

-- action 1 -- bulk insert the payment lines for one incomeId.
--   Input: { "incomePayments": [{ "action": 1, "incomeId": int,
--             "payments": [{ "method": str, "amount": num,
--                             "cashPaid": num|null, "cashReturn": num|null }, ...] }] }
-- action 2 -- list the payment lines for one incomeId (receipts).
--   Input: { "incomePayments": [{ "action": 2, "incomeId": int }] }
--   Output: { "result": [{ "payments": [...] }] }
CREATE OR ALTER PROC [dbo].[sp_incomePayments] (@pjsonfile NVARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @Outputmessage NVARCHAR(MAX) = '{
      "result": [{ "value": "", "msg": "", "error": "" }]
    }'

    DECLARE @action   INT = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action')) FROM OPENJSON(@pjsonfile, '$.incomePayments'));
    DECLARE @incomeId INT = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.incomeId')) FROM OPENJSON(@pjsonfile, '$.incomePayments'));

    BEGIN TRY
        IF @incomeId IS NULL
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'incomeId es requerido.')
        END
        ELSE IF @action = 1
        BEGIN
            DECLARE @paymentsArray NVARCHAR(MAX) = (
                SELECT TOP 1 JSON_QUERY(value, '$.payments') FROM OPENJSON(@pjsonfile, '$.incomePayments')
            );

            INSERT INTO dbo.incomePayments (incomeId, method, amount, cashPaid, cashReturn)
            SELECT @incomeId, p.method, p.amount, p.cashPaid, p.cashReturn
            FROM OPENJSON(@paymentsArray)
            WITH (
                method     VARCHAR(20)   '$.method',
                amount     DECIMAL(10,2) '$.amount',
                cashPaid   DECIMAL(10,2) '$.cashPaid',
                cashReturn DECIMAL(10,2) '$.cashReturn'
            ) AS p;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully')
        END
        ELSE IF @action = 2
        BEGIN
            DECLARE @paymentsJson NVARCHAR(MAX) = (
                SELECT incomePaymentId, incomeId, method, amount, cashPaid, cashReturn, created_At
                FROM dbo.incomePayments
                WHERE incomeId = @incomeId
                FOR JSON PATH
            );
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].payments', JSON_QUERY(ISNULL(@paymentsJson, '[]')))
        END
        ELSE
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Unknown action.')
        END
    END TRY
    BEGIN CATCH
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE())
    END CATCH

    SELECT @Outputmessage AS jsonResult
END
GO
