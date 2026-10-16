-- =============================================================================
-- Add dbo.sp_userCompanies_role — a user's active role in one company
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/fundingTransactions.py::_requester_role (the RBAC gate in
-- front of sp_fundingTransactions 'resolve_escalation') read
-- dbo.userCompanies with raw SQL. Backend rule: modules never issue raw SQL.
-- sp_users_one is NOT a substitute: it reads dbo.users (not the per-company
-- role sp_login uses) and returns the password hash.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Action-less read in the sp_loanInstallments convention:
--     @pjsonfile NVARCHAR(MAX), $.userCompanies[0], one [jsonResult] column.
--     Caller passes {"userCompanies":[{"userId":N,"companyId":N}]}.
--   - Returns {"roleName":"admin"} or '{}' when the user has no active
--     membership in that company (caller treats that as "no role" -> 403).
--   - active is VARCHAR(1): compared to '1' (the old raw SQL compared to the
--     int 1, forcing an implicit conversion on every row).
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_userCompanies_role]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @userId    INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.userCompanies[0].userId'));
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.userCompanies[0].companyId'));

        IF @userId IS NULL OR @companyId IS NULL
        BEGIN
            SELECT '{"error":"userId and companyId are required"}' AS [jsonResult];
            RETURN;
        END

        SELECT ISNULL(
            (SELECT TOP 1 roleName
               FROM dbo.userCompanies
              WHERE userId    = @userId
                AND companyId = @companyId
                AND active    = '1'
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            '{}'
        ) AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO
