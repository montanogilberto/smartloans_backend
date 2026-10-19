-- ============================================================
-- 2026-10-18c: idempotent POST /income (action 1).
--
-- A POS retry (network timeout, double tap) used to insert a second sale,
-- and with it a second coupon use, reward redemption and points EARN — the
-- per-incomeId guards can't see a new incomeId. The POS now sends one
-- clientRequestId (a UUID) per checkout attempt, the same on every retry.
--
-- modules/income.py stores it on the new sale right after sp_income (sp_income
-- itself is unchanged) and, when a sale with the same (companyId,
-- clientRequestId) already exists, returns that sale instead of inserting.
-- Concurrent retries are serialized by an app lock on the key; this unique
-- index is the backstop. Sales without a key (older POS builds, other
-- callers) are not affected.
--
-- Filtered index: writes to dbo.income need ANSI_NULLS / QUOTED_IDENTIFIER ON
-- (same requirement as UQ_posRewardCatalogItems_company_code). Safe to re-run.
-- ============================================================

IF COL_LENGTH('dbo.income', 'clientRequestId') IS NULL
    ALTER TABLE [dbo].[income] ADD clientRequestId NVARCHAR(64) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_income_company_clientRequestId'
                                           AND object_id = OBJECT_ID('dbo.income'))
    CREATE UNIQUE INDEX UQ_income_company_clientRequestId
        ON [dbo].[income] (companyId, clientRequestId) WHERE clientRequestId IS NOT NULL;
GO
