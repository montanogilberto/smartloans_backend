-- =============================================================================
-- TEST — Step 2: sp_chartOfAccounts_seed ("ensure base catalog")
-- Roadmap Step 2 gate (POSVending/docs/accounting-module.md §7.2)
-- =============================================================================
-- SAFE TO RUN ON PRODUCTION: one transaction, ALWAYS rolled back. Fake
-- companies -9101 / -9102 / -9103 only. Leaves no rows behind.
--
--   C1 -9101  empty company            → seed → full base catalog (20 accounts)
--   C2 -9102  legacy 17-account chart  → seed → +1101 +3205 +3210 only (21 incl.
--             + a custom 1106 account     the custom one); legacy ids unchanged
--   C3 -9103  never seeded             → must stay empty (isolation)
--   Seed runs twice on C1/C2           → second run inserts nothing
-- =============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

DECLARE @C1 INT = -9101, @C2 INT = -9102, @C3 INT = -9103;
DECLARE @checks TABLE (seq INT IDENTITY, name NVARCHAR(200), expected NVARCHAR(60), actual NVARCHAR(60));
DECLARE @legacyIds TABLE (accountId INT, code NVARCHAR(20));

INSERT INTO @checks (name, expected, actual)
SELECT N'seed SP deployed with 1101/3205/3210', '1',
       CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_chartOfAccounts_seed')) LIKE '%''1101''%'
             AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_chartOfAccounts_seed')) LIKE '%''3205''%'
             AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_chartOfAccounts_seed')) LIKE '%''3210''%'
            THEN '1' ELSE '0' END;

BEGIN TRANSACTION;
BEGIN TRY
    IF EXISTS (SELECT 1 FROM dbo.chartOfAccounts WHERE companyId IN (@C1, @C2, @C3))
        RAISERROR('Test companies -9101/-9102/-9103 already have accounts — aborting.', 16, 1);

    -- ── C2 fixture: the legacy (pre-2026-10-01) 17-account catalog + a custom account
    DECLARE @a INT, @l INT, @e INT, @i INT, @x INT;
    INSERT INTO dbo.chartOfAccounts (companyId, code, name, accountType, normalBalance, isPostable, level) VALUES (@C2, '1', 'ACTIVO',   'ASSET',     'D', 0, 1); SET @a = SCOPE_IDENTITY();
    INSERT INTO dbo.chartOfAccounts (companyId, code, name, accountType, normalBalance, isPostable, level) VALUES (@C2, '2', 'PASIVO',   'LIABILITY', 'C', 0, 1); SET @l = SCOPE_IDENTITY();
    INSERT INTO dbo.chartOfAccounts (companyId, code, name, accountType, normalBalance, isPostable, level) VALUES (@C2, '3', 'CAPITAL',  'EQUITY',    'C', 0, 1); SET @e = SCOPE_IDENTITY();
    INSERT INTO dbo.chartOfAccounts (companyId, code, name, accountType, normalBalance, isPostable, level) VALUES (@C2, '4', 'INGRESOS', 'INCOME',    'C', 0, 1); SET @i = SCOPE_IDENTITY();
    INSERT INTO dbo.chartOfAccounts (companyId, code, name, accountType, normalBalance, isPostable, level) VALUES (@C2, '5', 'GASTOS',   'EXPENSE',   'D', 0, 1); SET @x = SCOPE_IDENTITY();
    INSERT INTO dbo.chartOfAccounts (companyId, code, name, accountType, normalBalance, parentAccountId, isPostable, level) VALUES
        (@C2, '1105', 'Bancos',              'ASSET',     'D', @a, 1, 2),
        (@C2, '2105', 'Cuentas por pagar',   'LIABILITY', 'C', @l, 1, 2),
        (@C2, '3105', 'Capital social',      'EQUITY',    'C', @e, 1, 2),
        (@C2, '4105', 'Ingresos por ventas', 'INCOME',    'C', @i, 1, 2),
        (@C2, '4110', 'Intereses ganados',   'INCOME',    'C', @i, 1, 2),
        (@C2, '4115', 'Comisiones cobradas', 'INCOME',    'C', @i, 1, 2),
        (@C2, '4199', 'Otros ingresos',      'INCOME',    'C', @i, 1, 2),
        (@C2, '5105', 'Gastos de operación', 'EXPENSE',   'D', @x, 1, 2),
        (@C2, '5110', 'Nómina',              'EXPENSE',   'D', @x, 1, 2),
        (@C2, '5115', 'Servicios',           'EXPENSE',   'D', @x, 1, 2),
        (@C2, '5120', 'Comisiones bancarias','EXPENSE',   'D', @x, 1, 2),
        (@C2, '5199', 'Otros gastos',        'EXPENSE',   'D', @x, 1, 2),
        (@C2, '1106', 'Bancos USD (custom)', 'ASSET',     'D', @a, 1, 2);
    INSERT INTO @legacyIds SELECT accountId, code FROM dbo.chartOfAccounts WHERE companyId = @C2;

    -- ── Act ──────────────────────────────────────────────────────────────────
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @C1;
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @C2;

    DECLARE @c1First INT = (SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId = @C1);
    DECLARE @c2First INT = (SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId = @C2);

    EXEC dbo.sp_chartOfAccounts_seed @companyId = @C1;   -- second run: must be a no-op
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @C2;

    -- ── Expected base catalog ────────────────────────────────────────────────
    DECLARE @base TABLE (code NVARCHAR(20), accountType NVARCHAR(20), normalBalance NVARCHAR(1), isPostable BIT, level INT);
    INSERT INTO @base VALUES
        ('1','ASSET','D',0,1),('2','LIABILITY','C',0,1),('3','EQUITY','C',0,1),('4','INCOME','C',0,1),('5','EXPENSE','D',0,1),
        ('1101','ASSET','D',1,2),('1105','ASSET','D',1,2),('2105','LIABILITY','C',1,2),('3105','EQUITY','C',1,2),
        ('3205','EQUITY','C',1,2),('3210','EQUITY','C',1,2),('4105','INCOME','C',1,2),('4110','INCOME','C',1,2),
        ('4115','INCOME','C',1,2),('4199','INCOME','C',1,2),('5105','EXPENSE','D',1,2),('5110','EXPENSE','D',1,2),
        ('5115','EXPENSE','D',1,2),('5120','EXPENSE','D',1,2),('5199','EXPENSE','D',1,2);

    -- ── C1: empty company gets the full catalog ─────────────────────────────
    INSERT INTO @checks (name, expected, actual) SELECT N'C1 empty company → 20 accounts', '20', CAST(@c1First AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'C1 missing base codes', '0',
        CAST((SELECT COUNT(*) FROM @base b WHERE NOT EXISTS (SELECT 1 FROM dbo.chartOfAccounts a WHERE a.companyId=@C1 AND a.code=b.code)) AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'C1 type/naturaleza/postable/level mismatches', '0',
        CAST((SELECT COUNT(*) FROM dbo.chartOfAccounts a JOIN @base b ON b.code=a.code
              WHERE a.companyId=@C1 AND (a.accountType<>b.accountType OR a.normalBalance<>b.normalBalance
                                         OR a.isPostable<>b.isPostable OR a.level<>b.level)) AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'C1 leaves whose parent is not their class', '0',
        CAST((SELECT COUNT(*) FROM dbo.chartOfAccounts a LEFT JOIN dbo.chartOfAccounts p ON p.accountId=a.parentAccountId
              WHERE a.companyId=@C1 AND a.level=2
                AND (p.accountId IS NULL OR p.companyId<>@C1 OR p.code<>LEFT(a.code,1))) AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'C1 1101 Caja = ASSET/D/postable/level 2', 'ASSET/D/1/2',
        ISNULL((SELECT accountType + '/' + normalBalance + '/' + CAST(isPostable AS NVARCHAR(1)) + '/' + CAST(level AS NVARCHAR(2))
                FROM dbo.chartOfAccounts WHERE companyId=@C1 AND code='1101'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'C1 3205 / 3210 = EQUITY/C', 'EQUITY/C|EQUITY/C',
        ISNULL((SELECT accountType + '/' + normalBalance FROM dbo.chartOfAccounts WHERE companyId=@C1 AND code='3205'), '(none)') + '|' +
        ISNULL((SELECT accountType + '/' + normalBalance FROM dbo.chartOfAccounts WHERE companyId=@C1 AND code='3210'), '(none)');

    -- ── C2: legacy company gets only the 3 new accounts ─────────────────────
    INSERT INTO @checks (name, expected, actual) SELECT N'C2 legacy 17 + custom 1 + new 3 = 21', '21', CAST(@c2First AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'C2 legacy/custom account ids unchanged', '18',
        CAST((SELECT COUNT(*) FROM @legacyIds li JOIN dbo.chartOfAccounts a ON a.accountId=li.accountId AND a.code=li.code AND a.companyId=@C2) AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'C2 custom 1106 untouched', 'Bancos USD (custom)',
        ISNULL((SELECT name FROM dbo.chartOfAccounts WHERE companyId=@C2 AND code='1106'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'C2 new accounts added', '1101,3205,3210',
        ISNULL((SELECT STUFF((SELECT ',' + a.code FROM dbo.chartOfAccounts a
                              WHERE a.companyId=@C2 AND a.accountId NOT IN (SELECT accountId FROM @legacyIds)
                              ORDER BY a.code FOR XML PATH('')), 1, 1, '')), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'C2 new accounts under their class', '0',
        CAST((SELECT COUNT(*) FROM dbo.chartOfAccounts a LEFT JOIN dbo.chartOfAccounts p ON p.accountId=a.parentAccountId
              WHERE a.companyId=@C2 AND a.code IN ('1101','3205','3210')
                AND (p.accountId IS NULL OR p.companyId<>@C2 OR p.code<>LEFT(a.code,1))) AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'C2 missing base codes', '0',
        CAST((SELECT COUNT(*) FROM @base b WHERE NOT EXISTS (SELECT 1 FROM dbo.chartOfAccounts a WHERE a.companyId=@C2 AND a.code=b.code)) AS NVARCHAR(10));

    -- ── Idempotency, duplicates, isolation ──────────────────────────────────
    INSERT INTO @checks (name, expected, actual) SELECT N'second run is a no-op (C1/C2 counts)', '20/21',
        CAST((SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId=@C1) AS NVARCHAR(10)) + '/' +
        CAST((SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId=@C2) AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'duplicate codes in C1/C2', '0',
        CAST((SELECT COUNT(*) FROM (SELECT companyId, code FROM dbo.chartOfAccounts WHERE companyId IN (@C1,@C2)
                                    GROUP BY companyId, code HAVING COUNT(*) > 1) d) AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'C3 untouched (isolation)', '0',
        CAST((SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId=@C3) AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'C1 parents never point to another company', '0',
        CAST((SELECT COUNT(*) FROM dbo.chartOfAccounts a JOIN dbo.chartOfAccounts p ON p.accountId=a.parentAccountId
              WHERE a.companyId IN (@C1,@C2) AND p.companyId<>a.companyId) AS NVARCHAR(10));
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @checks (name, expected, actual) VALUES (N'TEST ERROR: ' + @err, 'no error', 'error');
END CATCH

IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

SELECT seq, CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 'PASS' ELSE 'FAIL' END AS result,
       name, expected, actual
FROM @checks ORDER BY seq;

SELECT CASE WHEN SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) = 0
            THEN 'STEP 2 GATE: ALL ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS PASS'
            ELSE 'STEP 2 GATE: ' + CAST(SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) AS NVARCHAR(10))
                 + ' OF ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS FAIL' END AS summary,
       (SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId IN (-9101, -9102, -9103)) AS leftoverTestRows
FROM @checks;
