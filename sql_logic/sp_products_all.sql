SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[sp_products_all]
AS
SET NOCOUNT ON

BEGIN

    SELECT
       [productId]
      ,[name]
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
GO
