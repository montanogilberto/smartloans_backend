-- =============================================================================
-- Drop the deprecated alias dbo.sp_products_save
-- =============================================================================
-- Run ONLY after 2026-10-26_products_unify_sp_products.sql AND after the backend
-- that calls dbo.sp_products is deployed to DEV, QA and PROD (they share this DB).
-- The DB cannot see the backend: confirm on GitHub that modules/products.py calls
-- dbo.sp_products on development, qa AND main before running this file.
-- Undo: re-run section 2 of 2026-10-26_products_unify_sp_products.sql.
-- =============================================================================

-- Guard 1: the alias from 2026-10-26_products_unify_sp_products.sql must be live.
-- If sp_products_save still holds the full logic, the unify migration was not run
-- (or only sql_logic/sp_products.sql was), and the deployed backend may still call it.
IF OBJECT_ID('dbo.sp_products_save') IS NOT NULL
   AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_products_save')) NOT LIKE '%EXEC dbo.sp_products @pjsonfile%'
BEGIN
    RAISERROR('sp_products_save is not the alias yet: run 2026-10-26_products_unify_sp_products.sql first; not dropped.', 16, 1);
    SET NOEXEC ON;
END
-- Guard 2: no other SQL module may EXEC it (a plain mention of the name does not count).
ELSE IF EXISTS (SELECT 1 FROM sys.sql_modules m
                WHERE m.definition LIKE '%EXEC%sp[_]products[_]save%'
                  AND m.object_id <> OBJECT_ID('dbo.sp_products_save'))
BEGIN
    RAISERROR('sp_products_save is still executed by another SQL module; not dropped.', 16, 1);
    SET NOEXEC ON;
END
GO

DROP PROCEDURE IF EXISTS dbo.sp_products_save;
GO

SET NOEXEC OFF;
GO
