-- =============================================================================
-- sp_products_by_company: list every sellable product (not only ones with
-- options) and return the fields the product wizard edits
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-07_products_net_content_no_expire.sql (needs netContent /
-- unitOfMeasure / referencePrice) and 2026-10-11_products_auto_code.sql.
--
-- WHY:
--   1. The WHERE EXISTS(productOptions) filter hid every product without
--      options. Drinks/snacks are now plain products (barcode, stock, price),
--      so a new "Electrolit 1000 ml" saved fine but never appeared in the POS
--      menu nor in the admin Products page (both read this SP).
--      Supplies (isSupply=1) relied on that filter to stay out of the POS
--      menu — they are now excluded explicitly instead.
--   2. "Ver/Editar producto" showed precio $0, no code, no barcode: the wizard
--      reads details[0].salePrice/unitPrice/stockQuantity, code, barCode,
--      dateOfExpire, category, descriptions — this SP only returned `price`.
--
-- WHAT: same output shape as before (id, name, description, price, image,
-- categoryId, options[] with choices[]) — the POS menu keeps working — plus:
--   productId, code, barCode, dateOfExpire, netContent, unitOfMeasure,
--   referencePrice, companyId, details[] {productDetailId, stockQuantity,
--   unitPrice, salePrice}, category {productCategoryId, name},
--   descriptions[] {productDescriptionId, Dosage, measurementId, is_principal,
--   activeIngredientId}.
--   Filter: companyId + ISNULL(isSupply,0)=0. productDetails is now LEFT JOIN
--   (a product without a details row shows at price 0 instead of vanishing).
-- Base: live definition pasted by the user 2026-10-11 (identical to the repo copy).
-- ROLLBACK: 2026-10-11b_products_by_company_all_products_ROLLBACK.sql
-- =============================================================================

CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1" } ] }'
    */

    DECLARE @companyId INT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    SELECT
        p.productId AS [id],
        p.productId,
        p.name,
        p.description,
        ISNULL(pd.salePrice, 0) AS price,
        NULL AS [image],
        p.categoryId,
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
            WHERE c.productCategoryId = p.categoryId
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
    ORDER BY p.name
    FOR JSON PATH, ROOT('products');
END
GO
