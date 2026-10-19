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

-- ── sp_income_clientRequest: the key's lookups for modules/income.py ──
-- (backend rule: Python only EXECs stored procedures — scripts/check_raw_sql.py)
--   lock   / unlock  session-owned app lock on (companyId, key): serializes
--                    concurrent retries of one checkout; SELECTs sp_getapplock's code
--   find             SELECTs the incomeId already holding the key (no row = none)
--   store            stamps the key on @incomeId; a duplicate raises error 2601
IF OBJECT_ID('dbo.sp_income_clientRequest', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_income_clientRequest;
GO
CREATE PROCEDURE [dbo].[sp_income_clientRequest]
    @action          VARCHAR(10),
    @companyId       INT,
    @clientRequestId NVARCHAR(64),
    @incomeId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @resource NVARCHAR(255) = CONCAT(N'income:', @companyId, N':', @clientRequestId), @r INT;

    IF @action = 'lock'
    BEGIN
        EXEC @r = sp_getapplock @Resource = @resource, @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 15000;
        SELECT @r AS result;
    END
    ELSE IF @action = 'unlock'
    BEGIN
        IF APPLOCK_MODE('public', @resource, 'Session') <> 'NoLock'
            EXEC @r = sp_releaseapplock @Resource = @resource, @LockOwner = 'Session';
        SELECT ISNULL(@r, 0) AS result;
    END
    ELSE IF @action = 'find'
        SELECT incomeId FROM [dbo].[income] WHERE companyId = @companyId AND clientRequestId = @clientRequestId;
    ELSE IF @action = 'store'
    BEGIN
        UPDATE [dbo].[income] SET clientRequestId = @clientRequestId
        WHERE incomeId = @incomeId AND clientRequestId IS NULL;
        SELECT @@ROWCOUNT AS result;
    END
    ELSE
        RAISERROR('action must be lock, unlock, find or store', 16, 1);
END
GO
