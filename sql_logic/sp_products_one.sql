
CREATE PROC [dbo].[sp_products_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
        "productId": "1"
        }
     ]
    }'
    */

    DECLARE @productId INT;

    SET @productId = CAST((SELECT JSON_VALUE(value, '$.productId') FROM OPENJSON(@pjsonfile, '$.products')) AS INT);

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
    FROM
        [montanogilberto_smartloans].[dbo].[products]
    WHERE
        productId = @productId
    FOR JSON AUTO, ROOT('products');

END