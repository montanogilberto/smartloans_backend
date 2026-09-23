-- ROLLBACK for 2026-09-23_add_ml_tokens_sp.sql
-- Restore the raw-SQL upsert_tokens / get_latest_tokens in
-- modules/mercadolibre.py first, or every MercadoLibre worker call fails
-- with "No Mercado Libre tokens found".

IF OBJECT_ID(N'dbo.sp_mlTokens', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_mlTokens];
GO
