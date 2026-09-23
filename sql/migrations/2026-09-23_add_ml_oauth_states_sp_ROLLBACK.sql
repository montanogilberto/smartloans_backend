-- ROLLBACK for 2026-09-23_add_ml_oauth_states_sp.sql
-- Restore modules/mercadolibre.py's raw-SQL save_oauth_state /
-- pop_code_verifier first, or the MercadoLibre OAuth connect flow breaks.

IF OBJECT_ID(N'dbo.sp_mlOAuthStates', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_mlOAuthStates];
GO
