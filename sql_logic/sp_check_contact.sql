-- sp_check_contact
-- Looks up a phone or email in dbo.clients (laundry customers) and dbo.users.
-- Returns the first matching record so the registration wizard can detect
-- existing accounts before creating a duplicate.
--
-- Usage:
--   EXEC sp_check_contact @contact = '+525512345678'
--   EXEC sp_check_contact @contact = 'customer@example.com'

CREATE OR ALTER PROC [dbo].[sp_check_contact]
    @contact NVARCHAR(100)
AS
SET NOCOUNT ON;

SELECT TOP 1
    c.clientId,
    c.first_name,
    c.last_name,
    c.cellphone,
    c.email,
    c.companyId,
    -- userId will be non-NULL if this client already has a user account linked
    u.userId,
    u.name        AS userName,
    CASE
        WHEN u.userId IS NOT NULL THEN 1
        ELSE 0
    END           AS hasAccount
FROM dbo.clients c
LEFT JOIN dbo.users u
    ON u.email = c.email
WHERE
    c.cellphone = @contact
    OR c.email   = @contact
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
GO
