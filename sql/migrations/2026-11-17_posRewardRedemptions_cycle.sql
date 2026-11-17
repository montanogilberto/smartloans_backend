-- =============================================================================
-- 2026-11-17 — stamp cards per cycle: dbo.posRewardRedemptions.productOptionChoiceId
-- =============================================================================
-- A stamp card (free_product) now fills per cycle of its product: 4 Servicio
-- Completo Básico earn 1 free Básico, separately from Medio / Carga Alta / …
-- The "cycle" is the choice of the product's required option (Ciclo, Tamaño);
-- products without a required option keep one card for the whole product.
-- The redemption records which cycle it consumed (NULL = product without
-- cycles, or an old redemption made without a sale).
--
-- Backfill: a redemption linked to a sale takes the cycle of that sale's first
-- line of the product (first cycle row) — the unit the old checkout made free.
-- Idempotent: safe to run twice. Run BEFORE deploying the new sp_posRewards.sql
-- (fn_posRewardStampVariants reads the column) and sp_income_applyDiscounts.sql.
-- =============================================================================
IF COL_LENGTH('dbo.posRewardRedemptions', 'productOptionChoiceId') IS NULL
    ALTER TABLE dbo.posRewardRedemptions ADD productOptionChoiceId INT NULL;
GO

UPDATE rd SET productOptionChoiceId = cy.productOptionChoiceId
FROM dbo.posRewardRedemptions rd
JOIN dbo.posRewardCatalogItems c ON c.catalogItemId = rd.catalogItemId AND c.rewardType = 'free_product'
CROSS APPLY (SELECT TOP 1 o.productOptionId FROM dbo.productOptions o
             WHERE o.productId = c.freeProductId AND o.isRequired = 1 AND o.isActive = 1
             ORDER BY o.productOptionId) so
CROSS APPLY (SELECT TOP 1 ido.productOptionChoiceId
             FROM dbo.incomeDetails d
             JOIN dbo.incomeDetailOptions ido ON ido.incomeDetailId = d.incomeDetailId
                                             AND ido.productOptionId = so.productOptionId
             WHERE d.incomeId = rd.incomeId AND d.productId = c.freeProductId
             ORDER BY d.incomeDetailId, ido.incomeDetailOptionId) cy
WHERE rd.incomeId IS NOT NULL AND rd.productOptionChoiceId IS NULL;
GO
