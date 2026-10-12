-- ROLLBACK for 2026-10-11b_products_by_company_all_products.sql
-- Restores the live definition as of 2026-10-11 (only products WITH options,
-- minimal fields). Note: option-less products disappear from the POS again.

CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
SET NOCOUNT ON;

    DECLARE @companyId INT;
    DECLARE @categoryId INT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    SET @categoryId = CAST(
        (SELECT JSON_VALUE(value, '$.categoryId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    SELECT
		p.productId AS [id],
		p.name,
		p.description,
		pd.saleprice as price,
		NULL AS [image],
		p.categoryId,
		(
			SELECT
				o.productOptionId AS [productOptionId],
				o.name,
				o.type,
				(
					SELECT
						c.productOptionChoiceId AS [productOptionChoiceId],
						c.name,
						c.price
					FROM productOptionChoices c
					WHERE c.productOptionId = o.productOptionId
					FOR JSON PATH
				) AS choices
			FROM productOptions o
			WHERE o.productId = p.productId
			FOR JSON PATH
		) AS options
	FROM products p
	INNER JOIN productdetails pd ON p.productId = pd.productId
	WHERE EXISTS (
		SELECT 1 FROM productOptions o WHERE o.productId = p.productId
	)
    AND companyId = @companyId
	FOR JSON PATH, ROOT('products');

END
GO
