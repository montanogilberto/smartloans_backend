-- ============================================================
-- roles / uiFeatures / signupGroups — authorization & UI
-- configuration layer. Moves the previously hardcoded frontend
-- role config (RoleCode / ROLE_LABELS / ROLE_DESCRIPTIONS /
-- ROLE_EMOJI / ROLE_UI / ROLE_GROUPS) into the database, modeled
-- as proper catalogs rather than free-form strings, so it can be
-- queried instead of shipped as a static TS file.
--
-- Architecture (this file implements the bottom two layers only --
-- clientTypes/modules are a deliberate follow-up, not built here):
--
--   clientTypes (future)  -- Laundry / Taco / Water / ...
--        v
--   modules (future)      -- POS / Laundry / Manufacturing / ...
--        v
--   uiFeatures             -- clients / sales / rewards / ... (catalog, this file)
--        v
--   roles                  -- admin / manager / employee / ... (pre-existing)
--        |
--        +-- roleUiFeatures -- what a role can see (FK'd to uiFeatures)
--        +-- roleGroups     -- which signup-wizard group(s) a role appears
--                              in (FK'd to signupGroups, not a CHECK list)
--
-- uiFeatures.moduleCode is a plain (non-FK'd) tag reserved for the
-- future `modules` catalog -- forward-compatible metadata, not a
-- real relationship yet. Nothing else here anticipates clientTypes.
--
-- dbo.roles already existed (feeds sp_login / userCompanies.roleId
-- via dbo.roles.code) and is left in place -- this file only adds
-- an `emoji` column to it and sets English name/description labels
-- (the pre-existing values were a stale English/Spanish mix that
-- nothing in the UI was reading from).
--
-- dbo.permissions / dbo.role_permissions are a separate, unrelated,
-- unused-by-app-code legacy pair -- not touched or reused here.
--
-- All seeding below is additive-only (INSERT ... WHERE NOT EXISTS):
-- re-running this file never deletes a row, including any grant
-- added later outside this script (e.g. by a future admin UI or by
-- the Factory itself). A validation section at the end reports any
-- role/feature left unassigned instead of silently allowing drift.
-- Run this single file once against the target DB; safe to re-run.
-- ============================================================

-- ── dbo.roles: add emoji, set display labels (English) ──────
IF NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.roles') AND name = 'emoji'
)
    ALTER TABLE [dbo].[roles] ADD [emoji] NVARCHAR(20) NULL;
GO

UPDATE [dbo].[roles] SET name = N'Administrator', description = N'Full access to the system.',            emoji = N'👑'      WHERE code = 'admin';
UPDATE [dbo].[roles] SET name = N'Manager',       description = N'Management, reports and operations.',    emoji = N'🧑‍💼'    WHERE code = 'manager';
UPDATE [dbo].[roles] SET name = N'Employee',      description = N'Basic POS operations.',                  emoji = N'👷'      WHERE code = 'employee';
UPDATE [dbo].[roles] SET name = N'Borrower',      description = N'Request loans and view my status.',      emoji = N'🙋'      WHERE code = 'borrower';
UPDATE [dbo].[roles] SET name = N'Lender',        description = N'Offer loans and receive payments.',      emoji = N'💼'      WHERE code = 'lender';
UPDATE [dbo].[roles] SET name = N'Business',      description = N'POS, sales and reward points.',          emoji = N'🏪'      WHERE code = 'business';
UPDATE [dbo].[roles] SET name = N'Viewer',        description = N'Read-only access to reports.',           emoji = N'👁️'      WHERE code = 'viewer';
UPDATE [dbo].[roles] SET name = N'Client',        description = N'View my account, purchases and rewards.', emoji = N'🛍️'      WHERE code = 'client';
GO

-- ── Table: uiFeatures (catalog -- replaces free-form ROLE_UI strings) ──
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'uiFeatures')
CREATE TABLE [dbo].[uiFeatures] (
    featureId   INT IDENTITY PRIMARY KEY,
    featureCode NVARCHAR(50)  NOT NULL,
    displayName NVARCHAR(100) NOT NULL,
    moduleCode  NVARCHAR(50)  NULL,  -- forward-compat tag for the future `modules` catalog; not FK'd yet
    active      BIT           NOT NULL DEFAULT 1
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_uiFeatures_featureCode')
    CREATE UNIQUE INDEX UQ_uiFeatures_featureCode ON [dbo].[uiFeatures] (featureCode);
GO

INSERT INTO [dbo].[uiFeatures] (featureCode, displayName, moduleCode)
SELECT v.featureCode, v.displayName, v.moduleCode
FROM (VALUES
    ('clients',                  'Clients',                    'pos'),
    ('products',                 'Products',                   'pos'),
    ('categories',               'Categories',                 'pos'),
    ('suppliers',                'Suppliers',                  'pos'),
    ('alerts',                   'Alerts',                      'admin'),
    ('emails',                   'Emails',                      'admin'),
    ('users',                    'Users',                       'admin'),
    ('ingresos',                 'Income',                      'accounting'),
    ('egresos',                  'Expenses',                    'accounting'),
    ('accounting',               'Accounting',                  'accounting'),
    ('iot',                      'IoT',                         'iot'),
    ('settings',                 'Settings',                    'admin'),
    ('sells',                    'Sales',                       'pos'),
    ('laundry',                  'Laundry',                     'laundry'),
    ('pos',                      'Point of Sale',                'pos'),
    ('posRewards',               'POS Rewards',                 'rewards'),
    ('scannerqr',                'QR Scanner',                  'pos'),
    ('loans',                    'Loans',                       'smartLoans'),
    ('clientFaceRecognitions',   'Client Face Recognition',     'smartLoans'),
    ('clientDashboards',         'Client Dashboards',           'smartLoans'),
    ('pushNotifications',        'Push Notifications',          'notifications'),
    ('notificationDispatchLog',  'Notification Dispatch Log',   'notifications'),
    ('manufacturing',            'Manufacturing',               'manufacturing'),
    ('rewards',                  'Rewards',                     'rewards'),
    ('loanChat',                 'Loan Chat',                   'smartLoans'),
    ('p2pLending',               'P2P Lending',                 'smartLoans'),
    ('game',                     'Game',                        'arcade'),
    ('arcade',                   'Arcade',                      'arcade'),
    ('myRewards',                'My Rewards',                  'rewards')
) v(featureCode, displayName, moduleCode)
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[uiFeatures] f WHERE f.featureCode = v.featureCode);
GO

-- ── Table: signupGroups (catalog -- replaces the groupCode CHECK list) ──
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'signupGroups')
CREATE TABLE [dbo].[signupGroups] (
    groupId     INT IDENTITY PRIMARY KEY,
    groupCode   NVARCHAR(20)  NOT NULL,
    displayName NVARCHAR(100) NOT NULL,
    active      BIT           NOT NULL DEFAULT 1
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_signupGroups_groupCode')
    CREATE UNIQUE INDEX UQ_signupGroups_groupCode ON [dbo].[signupGroups] (groupCode);
GO

INSERT INTO [dbo].[signupGroups] (groupCode, displayName)
SELECT v.groupCode, v.displayName
FROM (VALUES
    ('pos',    'POS signup wizard'),
    ('loans',  'Loans signup wizard'),
    ('custom', 'Custom / all-role wizard')
) v(groupCode, displayName)
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[signupGroups] g WHERE g.groupCode = v.groupCode);
GO

-- ── Table: roleUiFeatures (replaces ROLE_UI; FK'd to uiFeatures) ────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'roleUiFeatures')
CREATE TABLE [dbo].[roleUiFeatures] (
    roleUiFeatureId INT IDENTITY PRIMARY KEY,
    roleId          INT NOT NULL
        CONSTRAINT FK_roleUiFeatures_role   REFERENCES [dbo].[roles](roleId)       ON DELETE CASCADE,
    featureId       INT NOT NULL
        CONSTRAINT FK_roleUiFeatures_feature REFERENCES [dbo].[uiFeatures](featureId) ON DELETE CASCADE
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_roleUiFeatures_role_feature')
    CREATE UNIQUE INDEX UQ_roleUiFeatures_role_feature ON [dbo].[roleUiFeatures] (roleId, featureId);
GO

-- ── Table: roleGroups (replaces ROLE_GROUPS; FK'd to signupGroups) ──
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'roleGroups')
CREATE TABLE [dbo].[roleGroups] (
    roleGroupId INT IDENTITY PRIMARY KEY,
    roleId      INT NOT NULL
        CONSTRAINT FK_roleGroups_role  REFERENCES [dbo].[roles](roleId)        ON DELETE CASCADE,
    groupId     INT NOT NULL
        CONSTRAINT FK_roleGroups_group REFERENCES [dbo].[signupGroups](groupId) ON DELETE CASCADE
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_roleGroups_role_group')
    CREATE UNIQUE INDEX UQ_roleGroups_role_group ON [dbo].[roleGroups] (roleId, groupId);
GO

-- ── Seed: roleUiFeatures (additive-only; matches roles/features by code) ──
INSERT INTO [dbo].[roleUiFeatures] (roleId, featureId)
SELECT r.roleId, f.featureId
FROM (VALUES
    ('admin',    'laundry'),    ('admin',    'pos'),               ('admin',    'posRewards'),
    ('admin',    'scannerqr'),  ('admin',    'sells'),              ('admin',    'clients'),
    ('admin',    'products'),   ('admin',    'categories'),         ('admin',    'suppliers'),
    ('admin',    'alerts'),     ('admin',    'emails'),             ('admin',    'users'),
    ('admin',    'ingresos'),   ('admin',    'egresos'),            ('admin',    'accounting'),
    ('admin',    'iot'),        ('admin',    'settings'),           ('admin',    'loans'),
    ('admin',    'clientDashboards'),         ('admin', 'clientFaceRecognitions'),
    ('admin',    'manufacturing'),            ('admin', 'pushNotifications'),
    ('admin',    'notificationDispatchLog'),  ('admin', 'rewards'),
    ('admin',    'loanChat'),   ('admin',    'p2pLending'),         ('admin',    'game'),
    ('admin',    'arcade'),

    ('manager',  'laundry'),    ('manager',  'pos'),                ('manager',  'posRewards'),
    ('manager',  'scannerqr'),  ('manager',  'sells'),              ('manager',  'clients'),
    ('manager',  'products'),   ('manager',  'categories'),         ('manager',  'suppliers'),
    ('manager',  'ingresos'),   ('manager',  'egresos'),            ('manager',  'accounting'),
    ('manager',  'clientDashboards'),         ('manager', 'manufacturing'),
    ('manager',  'notificationDispatchLog'),  ('manager', 'rewards'),
    ('manager',  'game'),       ('manager',  'arcade'),

    ('employee', 'laundry'),    ('employee', 'pos'),                ('employee', 'posRewards'),
    ('employee', 'scannerqr'),  ('employee', 'sells'),              ('employee', 'rewards'),
    ('employee', 'game'),       ('employee', 'arcade'),

    ('borrower', 'clientDashboards'),         ('borrower', 'loanChat'),
    ('borrower', 'loans'),      ('borrower', 'p2pLending'),         ('borrower', 'game'),
    ('borrower', 'arcade'),

    ('lender',   'clientDashboards'),         ('lender', 'loanChat'),
    ('lender',   'p2pLending'), ('lender',   'loans'),              ('lender',   'game'),
    ('lender',   'arcade'),

    ('business', 'pos'),        ('business', 'posRewards'),         ('business', 'scannerqr'),
    ('business', 'sells'),      ('business', 'clients'),            ('business', 'products'),
    ('business', 'categories'), ('business', 'ingresos'),           ('business', 'egresos'),
    ('business', 'rewards'),    ('business', 'game'),               ('business', 'arcade'),

    ('viewer',   'ingresos'),   ('viewer',   'egresos'),            ('viewer',   'clientDashboards'),
    ('viewer',   'game'),       ('viewer',   'arcade'),

    ('client',   'game'),       ('client',   'arcade'),         ('client',   'myRewards')
) v(roleCode, featureCode)
JOIN [dbo].[roles]      r ON r.code = v.roleCode
JOIN [dbo].[uiFeatures] f ON f.featureCode = v.featureCode
WHERE NOT EXISTS (
    SELECT 1 FROM [dbo].[roleUiFeatures] ruf
    WHERE ruf.roleId = r.roleId AND ruf.featureId = f.featureId
);
GO

-- ── Seed: roleGroups (additive-only; matches roles/groups by code) ──
INSERT INTO [dbo].[roleGroups] (roleId, groupId)
SELECT r.roleId, g.groupId
FROM (VALUES
    ('admin',    'pos'),   ('admin',    'loans'), ('admin',    'custom'),
    ('manager',  'pos'),   ('manager',  'custom'),
    ('employee', 'pos'),   ('employee', 'custom'),
    ('business', 'pos'),   ('business', 'custom'),
    ('viewer',   'pos'),   ('viewer',   'loans'), ('viewer',   'custom'),
    ('borrower', 'loans'), ('borrower', 'custom'),
    ('lender',   'loans'), ('lender',   'custom')
) v(roleCode, groupCode)
JOIN [dbo].[roles]        r ON r.code = v.roleCode
JOIN [dbo].[signupGroups] g ON g.groupCode = v.groupCode
WHERE NOT EXISTS (
    SELECT 1 FROM [dbo].[roleGroups] rg
    WHERE rg.roleId = r.roleId AND rg.groupId = g.groupId
);
GO

-- ── Stored Procedure: sp_roles ───────────────────────────────
-- Returns a single JSON array (not the app's {"result":[...]} envelope --
-- that wrapping is done in FastAPI/modules/roles.py, so this procedure's
-- contract is just the data): [{ roleId, code, name, description, emoji,
-- active, uiFeatures: string[], groups: string[] }] for every active role.
IF OBJECT_ID('dbo.sp_roles', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_roles]
GO
CREATE PROCEDURE [dbo].[sp_roles]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ISNULL((
        SELECT
            r.roleId,
            r.code,
            r.name,
            r.description,
            r.emoji,
            r.active,
            JSON_QUERY(ISNULL((
                SELECT '[' + STRING_AGG('"' + f.featureCode + '"', ',')
                                WITHIN GROUP (ORDER BY f.featureCode) + ']'
                FROM [dbo].[roleUiFeatures] ruf
                JOIN [dbo].[uiFeatures] f ON f.featureId = ruf.featureId
                WHERE ruf.roleId = r.roleId AND f.active = 1
            ), '[]')) AS uiFeatures,
            JSON_QUERY(ISNULL((
                SELECT '[' + STRING_AGG('"' + g.groupCode + '"', ',')
                                WITHIN GROUP (ORDER BY g.groupCode) + ']'
                FROM [dbo].[roleGroups] rg
                JOIN [dbo].[signupGroups] g ON g.groupId = rg.groupId
                WHERE rg.roleId = r.roleId AND g.active = 1
            ), '[]')) AS groups
        FROM [dbo].[roles] r
        WHERE r.active = 1
        ORDER BY r.roleId
        FOR JSON PATH
    ), '[]') AS rolesJson;
END
GO

-- ============================================================
-- Validation -- each query below should return zero rows. A row
-- here means the seed/catalog drifted from what the app expects;
-- it does not fail the migration, it just surfaces the gap.
-- ============================================================

-- Active roles with no UI features assigned at all.
SELECT r.code AS roleCodeMissingUiFeatures
FROM [dbo].[roles] r
WHERE r.active = 1
  AND NOT EXISTS (SELECT 1 FROM [dbo].[roleUiFeatures] ruf WHERE ruf.roleId = r.roleId);

-- Active roles with no signup group assigned at all.
SELECT r.code AS roleCodeMissingGroups
FROM [dbo].[roles] r
WHERE r.active = 1
  AND NOT EXISTS (SELECT 1 FROM [dbo].[roleGroups] rg WHERE rg.roleId = r.roleId);

-- Catalog features never granted to any role (dead/unused feature codes).
SELECT f.featureCode AS unusedUiFeature
FROM [dbo].[uiFeatures] f
WHERE f.active = 1
  AND NOT EXISTS (SELECT 1 FROM [dbo].[roleUiFeatures] ruf WHERE ruf.featureId = f.featureId);

-- Catalog signup groups never assigned to any role.
SELECT g.groupCode AS unusedSignupGroup
FROM [dbo].[signupGroups] g
WHERE g.active = 1
  AND NOT EXISTS (SELECT 1 FROM [dbo].[roleGroups] rg WHERE rg.groupId = g.groupId);
