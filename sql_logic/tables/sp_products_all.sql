CREATE PROC [dbo].[sp_products_all]
AS
SET NOCOUNT ON

BEGIN

    SELECT
       [name]
      ,[code]
      ,[imageId]
      ,[dateOfExpire]
      ,[productFormId]
      ,[manufactureId]
      ,[description]
      ,[createdAt]
      ,[updatedAt]
  FROM [montanogilberto_smartloans].[dbo].[products]
  FOR JSON AUTO, ROOT('products');

END