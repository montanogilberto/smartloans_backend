-- =============================================================================
-- Step 2 — extend the base chart of accounts for the Balance General
-- =============================================================================
-- Forward-only, additive. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 2 (§7.2).
-- Test:    sql/tests/2026-10-01c_chartOfAccounts_ensure_base_test.sql
--
-- NEW ACCOUNTS (owner decisions 2026-10-01: inventory expensed → no 1115;
-- IVA not tracked → no 1118/2118; payroll accrual undecided → no 2110 yet):
--   1101 Caja                                ASSET   D  (cash, separate from 1105 Bancos)
--   3205 Resultados de ejercicios anteriores EQUITY  C  (prior years, after closing)
--   3210 Resultado del ejercicio             EQUITY  C  (target of a future closing entry)
-- Code convention for current/non-current (no schema change):
--   11xx circulante · 12xx no circulante · 21xx corto plazo · 22xx largo plazo.
--
-- CHANGE: sp_chartOfAccounts_seed goes from "do nothing if the company has ANY
-- account" to "insert whichever BASE account code the company is missing":
--   - never updates or deletes an existing account (ids, names, isActive kept);
--   - custom accounts a company added are untouched;
--   - classes first, then leaves (parent resolved by the class code);
--   - idempotent: a second run inserts nothing.
-- Then runs it for every company (dbo.companies) and for any companyId that
-- already has a chart, so existing companies get the 3 new accounts and any
-- company created after the 2026-09-03 backfill gets its full catalog.
--
-- Output: BEFORE and AFTER per-company summaries + a validation result set
-- (expect issues = 0 rows).
-- Idempotent: CREATE OR ALTER + insert-if-missing. sql/sp_chartOfAccounts.sql
-- carries the same seed body.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ── BEFORE ───────────────────────────────────────────────────────────────────
SELECT 'BEFORE' AS phase,
       COUNT(DISTINCT companyId) AS companiesWithChart,
       COUNT(*) AS accounts,
       SUM(CASE WHEN code = '1101' THEN 1 ELSE 0 END) AS has1101,
       SUM(CASE WHEN code = '3205' THEN 1 ELSE 0 END) AS has3205,
       SUM(CASE WHEN code = '3210' THEN 1 ELSE 0 END) AS has3210
FROM dbo.chartOfAccounts;

SELECT 'BEFORE: companies without any account' AS phase, COUNT(*) AS companies
FROM dbo.companies c
WHERE NOT EXISTS (SELECT 1 FROM dbo.chartOfAccounts a WHERE a.companyId = c.companyId);
GO

-- ── Seed = ensure base catalog ───────────────────────────────────────────────
CREATE OR ALTER PROCEDURE [dbo].[sp_chartOfAccounts_seed]
    @companyId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF @companyId IS NULL RETURN;

    DECLARE @base TABLE (
        code NVARCHAR(20), name NVARCHAR(150), accountType NVARCHAR(20),
        normalBalance NVARCHAR(1), parentCode NVARCHAR(20) NULL, isPostable BIT, level INT
    );
    INSERT INTO @base (code, name, accountType, normalBalance, parentCode, isPostable, level) VALUES
        ('1',    'ACTIVO',                              'ASSET',     'D', NULL, 0, 1),
        ('2',    'PASIVO',                              'LIABILITY', 'C', NULL, 0, 1),
        ('3',    'CAPITAL',                             'EQUITY',    'C', NULL, 0, 1),
        ('4',    'INGRESOS',                            'INCOME',    'C', NULL, 0, 1),
        ('5',    'GASTOS',                              'EXPENSE',   'D', NULL, 0, 1),
        ('1101', 'Caja',                                'ASSET',     'D', '1',  1, 2),
        ('1105', 'Bancos',                              'ASSET',     'D', '1',  1, 2),
        ('2105', 'Cuentas por pagar',                   'LIABILITY', 'C', '2',  1, 2),
        ('3105', 'Capital social',                      'EQUITY',    'C', '3',  1, 2),
        ('3205', 'Resultados de ejercicios anteriores', 'EQUITY',    'C', '3',  1, 2),
        ('3210', 'Resultado del ejercicio',             'EQUITY',    'C', '3',  1, 2),
        ('4105', 'Ingresos por ventas',                 'INCOME',    'C', '4',  1, 2),
        ('4110', 'Intereses ganados',                   'INCOME',    'C', '4',  1, 2),
        ('4115', 'Comisiones cobradas',                 'INCOME',    'C', '4',  1, 2),
        ('4199', 'Otros ingresos',                      'INCOME',    'C', '4',  1, 2),
        ('5105', 'Gastos de operación',                 'EXPENSE',   'D', '5',  1, 2),
        ('5110', 'Nómina',                              'EXPENSE',   'D', '5',  1, 2),
        ('5115', 'Servicios',                           'EXPENSE',   'D', '5',  1, 2),
        ('5120', 'Comisiones bancarias',                'EXPENSE',   'D', '5',  1, 2),
        ('5199', 'Otros gastos',                        'EXPENSE',   'D', '5',  1, 2);

    -- Classes (level 1) the company is missing.
    INSERT INTO [dbo].[chartOfAccounts] (companyId, code, name, accountType, normalBalance, isPostable, level)
    SELECT @companyId, b.code, b.name, b.accountType, b.normalBalance, b.isPostable, b.level
    FROM @base b
    WHERE b.parentCode IS NULL
      AND NOT EXISTS (SELECT 1 FROM [dbo].[chartOfAccounts] a
                      WHERE a.companyId = @companyId AND a.code = b.code);

    -- Leaves the company is missing, under its class.
    INSERT INTO [dbo].[chartOfAccounts] (companyId, code, name, accountType, normalBalance, parentAccountId, isPostable, level)
    SELECT @companyId, b.code, b.name, b.accountType, b.normalBalance, p.accountId, b.isPostable, b.level
    FROM @base b
    JOIN [dbo].[chartOfAccounts] p ON p.companyId = @companyId AND p.code = b.parentCode
    WHERE b.parentCode IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM [dbo].[chartOfAccounts] a
                      WHERE a.companyId = @companyId AND a.code = b.code);
END
GO

-- ── Apply to every company ───────────────────────────────────────────────────
DECLARE @cid INT;
DECLARE comp CURSOR LOCAL FAST_FORWARD FOR
    SELECT companyId FROM dbo.companies
    UNION
    SELECT DISTINCT companyId FROM dbo.chartOfAccounts WHERE companyId > 0;
OPEN comp;
FETCH NEXT FROM comp INTO @cid;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @cid;
    FETCH NEXT FROM comp INTO @cid;
END
CLOSE comp; DEALLOCATE comp;
GO

-- ── AFTER ────────────────────────────────────────────────────────────────────
SELECT 'AFTER' AS phase,
       COUNT(DISTINCT companyId) AS companiesWithChart,
       COUNT(*) AS accounts,
       SUM(CASE WHEN code = '1101' THEN 1 ELSE 0 END) AS has1101,
       SUM(CASE WHEN code = '3205' THEN 1 ELSE 0 END) AS has3205,
       SUM(CASE WHEN code = '3210' THEN 1 ELSE 0 END) AS has3210
FROM dbo.chartOfAccounts;

-- ── VALIDATION (expect 0 rows) ───────────────────────────────────────────────
;WITH base AS (
    SELECT * FROM (VALUES
        ('1','ASSET','D',0),('2','LIABILITY','C',0),('3','EQUITY','C',0),('4','INCOME','C',0),('5','EXPENSE','D',0),
        ('1101','ASSET','D',1),('1105','ASSET','D',1),('2105','LIABILITY','C',1),('3105','EQUITY','C',1),
        ('3205','EQUITY','C',1),('3210','EQUITY','C',1),('4105','INCOME','C',1),('4110','INCOME','C',1),
        ('4115','INCOME','C',1),('4199','INCOME','C',1),('5105','EXPENSE','D',1),('5110','EXPENSE','D',1),
        ('5115','EXPENSE','D',1),('5120','EXPENSE','D',1),('5199','EXPENSE','D',1)
    ) v(code, accountType, normalBalance, isPostable)
),
companiesToCheck AS (
    SELECT companyId FROM dbo.companies
    UNION SELECT DISTINCT companyId FROM dbo.chartOfAccounts WHERE companyId > 0
)
SELECT c.companyId, b.code, 'missing base account' AS issue
FROM companiesToCheck c CROSS JOIN base b
WHERE NOT EXISTS (SELECT 1 FROM dbo.chartOfAccounts a WHERE a.companyId = c.companyId AND a.code = b.code)
UNION ALL
SELECT a.companyId, a.code, 'wrong type/naturaleza/postable'
FROM dbo.chartOfAccounts a JOIN base b ON b.code = a.code
WHERE a.companyId > 0
  AND (a.accountType <> b.accountType OR a.normalBalance <> b.normalBalance OR a.isPostable <> b.isPostable)
UNION ALL
SELECT a.companyId, a.code, 'leaf parent is not its class'
FROM dbo.chartOfAccounts a
JOIN base b ON b.code = a.code AND b.isPostable = 1
LEFT JOIN dbo.chartOfAccounts p ON p.accountId = a.parentAccountId
WHERE a.companyId > 0
  AND (p.accountId IS NULL OR p.companyId <> a.companyId OR p.code <> LEFT(a.code, 1))
UNION ALL
SELECT companyId, code, 'duplicate code'
FROM dbo.chartOfAccounts
WHERE companyId > 0
GROUP BY companyId, code
HAVING COUNT(*) > 1
ORDER BY 1, 2;
GO
