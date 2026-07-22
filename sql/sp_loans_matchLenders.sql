-- ============================================================
-- sp_loans_matchLenders — finds lenders eligible to be notified about a
-- new loan request (MVP matching: availableBalance >= requested amount).
-- Future matching criteria (risk profile, state/country) need new columns
-- on dbo.clients before they can be added here.
-- ============================================================
IF OBJECT_ID('dbo.sp_loans_matchLenders', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loans_matchLenders;
GO

CREATE PROCEDURE [dbo].[sp_loans_matchLenders]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT           = JSON_VALUE(@pjsonfile, '$.companyId')
        DECLARE @amount    DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.amount')

        SELECT ISNULL(
            (SELECT c.clientId, u.userId
             FROM dbo.clients c
             INNER JOIN dbo.clientWallets w ON w.clientId = c.clientId AND w.companyId = c.companyId
             INNER JOIN dbo.users u ON u.clientId = c.clientId
             WHERE c.companyId = @companyId
               AND c.clientType IN ('lender', 'both')
               AND w.availableBalance >= @amount
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
