-- ============================================================
-- DEPLOY: sp_creditScore_data
-- ============================================================
-- RUN AGAINST THE APP'S DATABASE (from .env, used by databases.py):
--   Server:   sql.bsite.net\MSSQL2016
--   Database: montanogilberto_smartloans
-- NOT an Azure SQL DB — the app is hosted on Azure but its data is on bsite.net.
-- Running this anywhere else will "succeed" but the app won't see the change.
--
-- Fixes: credit engine returned kycEligible=false / availableCredit=0 for a
-- fully-verified client (e.g. 2116) because the deployed proc never read the
-- ClientFaceRecognitions KYC flags. Two problems are fixed here:
--   1) Real column names are snake_case (is_verified / pagare_accepted /
--      contract_accepted / created_At) — the camelCase names are JSON aliases.
--   2) Some auxiliary tables (loanProposals, stripeTransactions, clientFollowUps)
--      are not deployed in this DB. Each is guarded with OBJECT_ID and defaults
--      to 0 when absent, so the proc runs regardless of which tables exist.
--
-- Also HARDENS the KYC flags: all three come from the newest VERIFIED
-- expediente, so a newer unfinished re-KYC row can't shadow a verified one.
--
-- After running, verify:
--   POST /credit-score/available-credit  { "clientId":2116, "companyId":1008 }
--   expect: kycEligible:true, tier:PROMO_FIRST_TIME, availableCredit:3000,
--           internalScore:617 (was 567 without the +50 KYC bonuses)
-- ============================================================

IF OBJECT_ID('dbo.sp_creditScore_data', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_creditScore_data;
GO

CREATE PROCEDURE [dbo].[sp_creditScore_data]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.creditScore[0].clientId')
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.creditScore[0].companyId')
        DECLARE @today DATETIME2 = GETUTCDATE()
        DECLARE @90dAgo DATETIME2 = DATEADD(DAY, -90, @today)

        -- Payment history from stripeTransactions (optional table → guard)
        DECLARE @totalPayments  INT = 0
        DECLARE @onTimePayments INT = 0
        IF OBJECT_ID('dbo.stripeTransactions', 'U') IS NOT NULL
        BEGIN
            SET @totalPayments = (
                SELECT COUNT(*) FROM [dbo].[stripeTransactions]
                WHERE fromClientId = @clientId AND companyId = @companyId
                  AND paymentType = 'loan_repayment'
            )
            SET @onTimePayments = (
                SELECT COUNT(*) FROM [dbo].[stripeTransactions] st
                INNER JOIN [dbo].[loanInstallments] li
                    ON st.stripePaymentIntentId = li.stripePaymentIntentId
                WHERE st.fromClientId = @clientId AND st.companyId = @companyId
                  AND st.paymentType = 'loan_repayment' AND st.status = 'succeeded'
                  AND li.paidAt <= DATEADD(DAY, 3, li.dueDate)  -- 3-day grace period
            )
        END

        -- Installment status (loanInstallments exists in this DB)
        DECLARE @latePayments INT = (
            SELECT COUNT(*) FROM [dbo].[loanInstallments]
            WHERE clientId = @clientId AND companyId = @companyId
              AND status IN ('paid') AND paidAt > DATEADD(DAY, 3, dueDate)
        )
        DECLARE @defaults INT = (
            SELECT COUNT(*) FROM [dbo].[loanInstallments]
            WHERE clientId = @clientId AND companyId = @companyId AND status = 'delinquent'
        )

        -- Outstanding balance
        DECLARE @outstandingBalance DECIMAL(18,2) = (
            SELECT ISNULL(SUM(principalAmount), 0) FROM [dbo].[loans]
            WHERE clientId = @clientId AND companyId = @companyId
              AND loanStatus IN ('Active', 'active', 'Pending', 'pending')
        )
        DECLARE @totalCreditLimit DECIMAL(18,2) = (
            SELECT ISNULL(SUM(approvedAmount), 0) FROM [dbo].[loans]
            WHERE clientId = @clientId AND companyId = @companyId
        )

        -- Credit age
        DECLARE @creditAgeMonths INT = (
            SELECT ISNULL(DATEDIFF(MONTH, MIN(created_At), GETUTCDATE()), 0)
            FROM [dbo].[loans]
            WHERE clientId = @clientId AND companyId = @companyId
        )

        -- Recent proposals / hard inquiries (optional table → guard)
        DECLARE @proposalsLast90 INT = 0
        IF OBJECT_ID('dbo.loanProposals', 'U') IS NOT NULL
            SET @proposalsLast90 = (
                SELECT COUNT(*) FROM [dbo].[loanProposals]
                WHERE borrowerId = @clientId AND companyId = @companyId
                  AND created_At >= @90dAgo
            )

        -- Loan counts
        DECLARE @paidLoans INT = (
            SELECT COUNT(*) FROM [dbo].[loans]
            WHERE clientId = @clientId AND companyId = @companyId
              AND loanStatus IN ('Paid', 'paid', 'Completed', 'completed')
        )
        DECLARE @activeLoans INT = (
            SELECT COUNT(*) FROM [dbo].[loans]
            WHERE clientId = @clientId AND companyId = @companyId
              AND loanStatus IN ('Active', 'active')
        )

        -- Follow-up risk flags (optional table → guard)
        DECLARE @followUpAtRisk  INT = 0
        DECLARE @followUpDefault INT = 0
        IF OBJECT_ID('dbo.clientFollowUps', 'U') IS NOT NULL
        BEGIN
            SET @followUpAtRisk = (
                SELECT COUNT(*) FROM [dbo].[clientFollowUps]
                WHERE clientId = @clientId AND companyId = @companyId AND riskStatus = 'at_risk'
            )
            SET @followUpDefault = (
                SELECT COUNT(*) FROM [dbo].[clientFollowUps]
                WHERE clientId = @clientId AND companyId = @companyId AND riskStatus = 'default'
            )
        END

        -- Biometric & legal flags — read all three from the newest VERIFIED
        -- expediente, so a newer unfinished re-KYC row can't shadow it.
        -- NOTE: ClientFaceRecognitions columns are snake_case (is_verified /
        -- pagare_accepted / contract_accepted / created_At); the camelCase names
        -- below are only JSON OUTPUT aliases the Python engine reads.
        DECLARE @faceId INT = (
            SELECT TOP 1 clientFaceRecognitionId
            FROM   [dbo].[ClientFaceRecognitions]
            WHERE  clientId = @clientId AND companyId = @companyId AND is_verified = 1
            ORDER BY created_At DESC
        );
        DECLARE @isVerified       BIT = CASE WHEN @faceId IS NULL THEN 0 ELSE 1 END;
        DECLARE @pagareAccepted   BIT = ISNULL((SELECT pagare_accepted   FROM [dbo].[ClientFaceRecognitions] WHERE clientFaceRecognitionId = @faceId), 0);
        DECLARE @contractAccepted BIT = ISNULL((SELECT contract_accepted FROM [dbo].[ClientFaceRecognitions] WHERE clientFaceRecognitionId = @faceId), 0);

        SELECT (SELECT
            @totalPayments      AS totalPayments,
            @onTimePayments     AS onTimePayments,
            @latePayments       AS latePayments,
            @defaults           AS [defaults],
            @outstandingBalance AS outstandingBalance,
            @totalCreditLimit   AS totalCreditLimit,
            @creditAgeMonths    AS creditAgeMonths,
            @proposalsLast90    AS proposalsLast90Days,
            @paidLoans          AS paidLoans,
            @activeLoans        AS activeLoans,
            @followUpAtRisk     AS followUpAtRisk,
            @followUpDefault    AS followUpDefault,
            ISNULL(@isVerified, 0)       AS isVerified,
            ISNULL(@pagareAccepted, 0)   AS pagareAccepted,
            ISNULL(@contractAccepted, 0) AS contractAccepted
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- Smoke test (expect isVerified/pagareAccepted/contractAccepted = 1 for 2116):
-- EXEC [dbo].[sp_creditScore_data] @pjsonfile = N'{"creditScore":[{"clientId":2116,"companyId":1008}]}';
