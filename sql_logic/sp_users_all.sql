CREATE PROC [dbo].[sp_users_all]
AS
SET NOCOUNT ON

BEGIN

    SELECT
       [userId]
      ,[name]
      ,[email]
      ,[password]
      ,[created_at]
      ,[active]
  FROM [montanogilberto_smartloans].[dbo].[users]
  FOR JSON AUTO, ROOT('users');

END