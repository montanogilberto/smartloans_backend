-- ============================================================
-- Credit Score tables + stored procedures
-- ============================================================

-- ── Table: creditScores ─────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'creditScores')
CREATE TABLE [dbo].[creditScores] (
    scoreId     INT IDENTITY PRIMARY KEY,
    clientId    INT NOT NULL,
    companyId   INT NOT NULL,
    score       INT NOT NULL,
    label       NVARCHAR(20) NOT NULL,
    breakdown   NVARCHAR(MAX) NULL,   -- JSON breakdown stored as text
    computedAt  DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_creditScores_client UNIQUE (clientId, companyId)
)
GO

-- ── Table: creditScoreHistory (append-only audit log) ───────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'creditScoreHistory')
CREATE TABLE [dbo].[creditScoreHistory] (
    historyId   INT IDENTITY PRIMARY KEY,
    clientId    INT NOT NULL,
    companyId   INT NOT NULL,
    score       INT NOT NULL,
    label       NVARCHAR(20) NOT NULL,
    computedAt  DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
)
GO

-- ============================================================
-- sp_creditScore_data — aggregate inputs for score computation
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

        -- Payment history from stripeTransactions
        DECLARE @totalPayments INT = (
            SELECT COUNT(*) FROM [dbo].[stripeTransactions]
            WHERE fromClientId = @clientId AND companyId = @companyId
              AND paymentType = 'loan_repayment'
        )
        DECLARE @onTimePayments INT = (
            SELECT COUNT(*) FROM [dbo].[stripeTransactions] st
            INNER JOIN [dbo].[loanInstallments] li
                ON st.stripePaymentIntentId = li.stripePaymentIntentId
            WHERE st.fromClientId = @clientId AND st.companyId = @companyId
              AND st.paymentType = 'loan_repayment' AND st.status = 'succeeded'
              AND li.paidAt <= DATEADD(DAY, 3, li.dueDate)  -- 3-day grace period
        )
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
            SELECT ISNULL(
                DATEDIFF(MONTH,
                    MIN(created_At),
                    GETUTCDATE()),
                0)
            FROM [dbo].[loans]
            WHERE clientId = @clientId AND companyId = @companyId
        )

        -- Recent proposals (hard inquiries)
        DECLARE @proposalsLast90 INT = (
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

        -- Follow-up risk flags
        DECLARE @followUpAtRisk INT = (
            SELECT COUNT(*) FROM [dbo].[clientFollowUps]
            WHERE clientId = @clientId AND companyId = @companyId AND riskStatus = 'at_risk'
        )
        DECLARE @followUpDefault INT = (
            SELECT COUNT(*) FROM [dbo].[clientFollowUps]
            WHERE clientId = @clientId AND companyId = @companyId AND riskStatus = 'default'
        )

        -- Biometric & legal flags
        DECLARE @isVerified      BIT = (SELECT TOP 1 isVerified      FROM [dbo].[clientFaceRecognitions] WHERE clientId = @clientId AND companyId = @companyId ORDER BY createdAt DESC)
        DECLARE @pagareAccepted  BIT = (SELECT TOP 1 pagareAccepted  FROM [dbo].[clientFaceRecognitions] WHERE clientId = @clientId AND companyId = @companyId ORDER BY createdAt DESC)
        DECLARE @contractAccepted BIT= (SELECT TOP 1 contractAccepted FROM [dbo].[clientFaceRecognitions] WHERE clientId = @clientId AND companyId = @companyId ORDER BY createdAt DESC)

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

-- ============================================================
-- sp_creditScores (upsert / get / history)
-- ============================================================
IF OBJECT_ID('dbo.sp_creditScores', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_creditScores;
GO

CREATE PROCEDURE [dbo].[sp_creditScores]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action    NVARCHAR(10)   = JSON_VALUE(@pjsonfile, '$.creditScores[0].action')
        DECLARE @clientId  INT            = JSON_VALUE(@pjsonfile, '$.creditScores[0].clientId')
        DECLARE @companyId INT            = JSON_VALUE(@pjsonfile, '$.creditScores[0].companyId')
        DECLARE @score     INT            = JSON_VALUE(@pjsonfile, '$.creditScores[0].score')
        DECLARE @label     NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.creditScores[0].label')
        DECLARE @breakdown NVARCHAR(MAX)  = JSON_VALUE(@pjsonfile, '$.creditScores[0].breakdown')
        DECLARE @computedAt DATETIME2     = ISNULL(JSON_VALUE(@pjsonfile, '$.creditScores[0].computedAt'), GETUTCDATE())

        IF @action = 'upsert'
        BEGIN
            -- Derive label if not provided
            IF @label IS NULL
                SET @label = CASE
                    WHEN @score >= 750 THEN 'Excelente'
                    WHEN @score >= 700 THEN 'Muy bueno'
                    WHEN @score >= 650 THEN 'Bueno'
                    WHEN @score >= 600 THEN 'Regular'
                    WHEN @score >= 550 THEN 'Bajo'
                    ELSE 'Muy bajo' END

            MERGE [dbo].[creditScores] AS target
            USING (SELECT @clientId AS clientId, @companyId AS companyId) AS src
                ON target.clientId = src.clientId AND target.companyId = src.companyId
            WHEN MATCHED THEN
                UPDATE SET score=@score, label=@label, breakdown=@breakdown, computedAt=@computedAt
            WHEN NOT MATCHED THEN
                INSERT (clientId, companyId, score, label, breakdown, computedAt)
                VALUES (@clientId, @companyId, @score, @label, @breakdown, @computedAt);

            -- Always append history row
            INSERT INTO [dbo].[creditScoreHistory] (clientId, companyId, score, label, computedAt)
            VALUES (@clientId, @companyId, @score, @label, @computedAt)

            SELECT (SELECT TOP 1 score, label, breakdown, CONVERT(NVARCHAR,computedAt,127) AS computedAt
                    FROM [dbo].[creditScores]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'get'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 1 score, label, breakdown, CONVERT(NVARCHAR,computedAt,127) AS computedAt
                 FROM [dbo].[creditScores]
                 WHERE clientId=@clientId AND companyId=@companyId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{}'
            ) AS [jsonResult]
        END

        ELSE IF @action = 'history'
        BEGIN
            SELECT ISNULL(
                (SELECT score, label, CONVERT(NVARCHAR,computedAt,127) AS computedAt
                 FROM [dbo].[creditScoreHistory]
                 WHERE clientId=@clientId AND companyId=@companyId
                 ORDER BY computedAt ASC
                 FOR JSON PATH, ROOT('history')),
                '{"history":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
