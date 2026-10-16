-- =============================================================================
-- sp_products_by_company: filter by category again (optional categoryId)
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-15_products_productCategoryId.sql (uses products.productCategoryId).
--
-- WHY: /product/:categoryId (POS ProductListPage) sends
--   { companyId, categoryId } but the SP ignored categoryId (the filter was
--   commented out, and 2026-10-11b dropped it), so every category page listed
--   ALL of the company's products.
--
-- WHAT: reads optional "productCategoryId" (falls back to "categoryId");
--   when present (and not 0) adds  AND p.productCategoryId = @categoryId.
--   Callers that send only companyId (admin Products page, getProductsByCompany)
--   still get every product. Output shape unchanged.
-- ROLLBACK: 2026-10-15b_products_by_company_category_filter_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1" } ] }'                         -- all
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1", "categoryId": "1002" } ] }'  -- one category
    */

    DECLARE @companyId INT;
    DECLARE @categoryId INT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    -- Optional: productCategoryId (or legacy "categoryId"); missing/0 = all categories.
    SELECT TOP (1)
        @categoryId = NULLIF(TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'),
                                               JSON_VALUE(value, '$.categoryId')) AS INT), 0)
    FROM OPENJSON(@pjsonfile, '$.products');

    SELECT
        p.productId AS [id],
        p.productId,
        p.name,
        p.description,
        ISNULL(pd.salePrice, 0) AS price,
        NULL AS [image],
        p.productCategoryId AS categoryId,
        ISNULL(p.code, '') AS code,
        ISNULL(p.barCode, '') AS barCode,
        p.dateOfExpire,
        p.netContent,
        p.unitOfMeasure,
        p.referencePrice,
        p.companyId,
        (
            SELECT d.productDetailId, d.stockQuantity, d.unitPrice, d.salePrice
            FROM productDetails d
            WHERE d.productId = p.productId
            FOR JSON PATH
        ) AS details,
        JSON_QUERY((
            SELECT TOP 1 c.productCategoryId, c.name
            FROM productCategories c
            WHERE c.productCategoryId = p.productCategoryId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        )) AS category,
        (
            SELECT ds.productDescriptionId, ds.Dosage, ds.measurementId, ds.is_principal, ds.activeIngredientId
            FROM productsDescription ds
            WHERE ds.productId = p.productId
            FOR JSON PATH
        ) AS descriptions,
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
    OUTER APPLY (
        SELECT TOP 1 x.salePrice
        FROM productDetails x
        WHERE x.productId = p.productId
        ORDER BY x.productDetailId
    ) pd
    WHERE p.companyId = @companyId
      AND ISNULL(p.isSupply, 0) = 0
      AND (@categoryId IS NULL OR p.productCategoryId = @categoryId)
    ORDER BY p.name
    FOR JSON PATH, ROOT('products');
END
GO
