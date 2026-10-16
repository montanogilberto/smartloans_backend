-- ROLLBACK for 2026-10-02c_company_token_ledger.sql
-- Drops the three procedures and the ledger table. DESTRUCTIVE: the ledger
-- (every top-up and every recorded agent usage) is lost. Export it first if it has data.
DROP PROCEDURE IF EXISTS dbo.sp_companyTokens_balance;
DROP PROCEDURE IF EXISTS dbo.sp_companyTokens_topup;
DROP PROCEDURE IF EXISTS dbo.sp_companyTokens_record;
DROP TABLE IF EXISTS dbo.companyTokenLedger;
