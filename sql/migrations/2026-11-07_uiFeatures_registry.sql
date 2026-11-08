-- =============================================================================
-- dbo.uiFeatures becomes the module/feature REGISTRY (2026-11-07).
--
-- Before: the list of modules shown in /setting ("Permisos por Rol") was
-- hardcoded in the frontend (Setting.tsx MODULES), and the factory only patched
-- that file + the ROLE_UI fallback — never the DB catalog that GET /roles
-- returns. So every factory-generated module shipped invisible until someone
-- hand-wrote a roleUiFeatures migration (see 2026-09-30_add_employees_ui_feature,
-- 2026-11-07_grant_clients_to_employee).
--
-- After: each feature row carries what /setting needs to render it, every new
-- factory module registers itself via sp_uiFeatures_register (emitted into the
-- module's SQL by the factory's feature_registry stage), and the frontend reads
-- the registry from GET /ui_features (sp_uiFeatures_all).
--
-- Columns added (all NULL — old rows and old callers keep working):
--   label      es-MX UI label (displayName stays the English catalog name)
--   section    /setting card: 'POS' | 'Catálogo' | 'Mensajes' | 'Administración' | 'IOT' | ...
--              NULL = not configurable in /setting (customer self-service features)
--   icon       ionicons outline name, e.g. 'peopleOutline'
--   route      frontend route, e.g. '/clients'
--   sortOrder  order inside the section
--
-- Run order: this file, then sql/sp_uiFeatures.sql. Idempotent.
-- =============================================================================

IF COL_LENGTH('dbo.uiFeatures', 'label') IS NULL
    ALTER TABLE [dbo].[uiFeatures] ADD [label] NVARCHAR(100) NULL;
GO
IF COL_LENGTH('dbo.uiFeatures', 'section') IS NULL
    ALTER TABLE [dbo].[uiFeatures] ADD [section] NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.uiFeatures', 'icon') IS NULL
    ALTER TABLE [dbo].[uiFeatures] ADD [icon] NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.uiFeatures', 'route') IS NULL
    ALTER TABLE [dbo].[uiFeatures] ADD [route] NVARCHAR(200) NULL;
GO
IF COL_LENGTH('dbo.uiFeatures', 'sortOrder') IS NULL
    ALTER TABLE [dbo].[uiFeatures] ADD [sortOrder] INT NULL;
GO

-- ── Backfill: what Setting.tsx MODULES hardcoded, plus staff features it was
--    missing (employees, services, posRewards, rewards, accounting,
--    notificationDispatchLog, game, arcade). Only fills NULLs, so re-running
--    never overwrites a value edited since. Codes missing from the table are
--    simply skipped (UPDATE ... JOIN).
UPDATE f
SET f.label     = COALESCE(f.label,     v.label),
    f.section   = COALESCE(f.section,   v.section),
    f.icon      = COALESCE(f.icon,      v.icon),
    f.route     = COALESCE(f.route,     v.route),
    f.sortOrder = COALESCE(f.sortOrder, v.sortOrder)
FROM [dbo].[uiFeatures] f
JOIN (VALUES
    ('pos',                     N'Vending POS',                          N'POS',            'cashOutline',            '/dashboard',                 10),
    ('scannerqr',               N'Lector QR',                            N'POS',            'qrCodeOutline',          NULL,                         20),
    ('laundry',                 N'Lavandería',                           N'POS',            'waterOutline',           NULL,                         30),
    ('posRewards',              N'Recompensas POS',                      N'POS',            'cartOutline',            '/pos-rewards',               40),
    ('rewards',                 N'Recompensas',                          N'POS',            'cartOutline',            '/rewards',                   50),
    ('clients',                 N'Clientes',                             N'Catálogo',       'peopleOutline',          '/clients',                   10),
    ('products',                N'Productos',                            N'Catálogo',       'cubeOutline',            '/products-management',       20),
    ('categories',              N'Categorías',                           N'Catálogo',       'gridOutline',            '/categories',                30),
    ('suppliers',               N'Proveedores',                          N'Catálogo',       'peopleOutline',          '/suppliers',                 40),
    ('services',                N'Servicios',                            N'Catálogo',       'cubeOutline',            '/services',                  50),
    ('clientDashboards',        N'Dashboard Cliente',                    N'Catálogo',       'peopleOutline',          NULL,                         60),
    ('alerts',                  N'Alertas',                              N'Mensajes',       'notificationsOutline',   '/alerts',                    10),
    ('emails',                  N'Correos',                              N'Mensajes',       'mailOutline',            '/emails',                    20),
    ('pushNotifications',       N'Notificaciones',                       N'Mensajes',       'notificationsOutline',   '/pushNotifications',         30),
    ('notificationDispatchLog', N'Bitácora de envíos',                   N'Mensajes',       'notificationsOutline',   '/notification-dispatch-log', 40),
    ('manufacturing',           N'Manufactura',                          N'Mensajes',       'cogOutline',             '/manufacturing',             50),
    ('users',                   N'Usuarios',                             N'Administración', 'personOutline',          '/users',                     10),
    ('employees',               N'Empleados',                            N'Administración', 'personOutline',          '/employees',                 20),
    ('companyPaymentAccounts',  N'Cuentas de cobro',                     N'Administración', 'cartOutline',            '/company-payment-accounts',  30),
    ('ingresos',                N'Ingresos',                             N'Administración', 'barChartOutline',        '/ingresos',                  40),
    ('egresos',                 N'Egresos',                              N'Administración', 'trendingDownOutline',    '/egresos',                   50),
    ('accounting',              N'Contabilidad',                         N'Administración', 'barChartOutline',        '/accounting',                60),
    ('sells',                   N'Ventas',                               N'Administración', 'cartOutline',            NULL,                         70),
    ('settings',                N'Configuración',                        N'Administración', 'settingsOutline',        '/setting',                   80),
    ('loans',                   N'Préstamos',                            N'Administración', 'cashOutline',            '/loans',                     90),
    ('clientFaceRecognitions',  N'Reconocimiento Facial',                N'Administración', 'shieldCheckmarkOutline', '/clientFaceRecognitions',   100),
    ('iot',                     N'Tablero IOT / LED Status / Water Tanks', N'IOT',          'bulbOutline',            '/iot-dashboard',             10),
    ('game',                    N'Juego',                                N'Entretenimiento','gameControllerOutline',  NULL,                         10),
    ('arcade',                  N'Arcade',                               N'Entretenimiento','gameControllerOutline',  '/arcade',                    20)
) v(featureCode, label, section, icon, route, sortOrder) ON v.featureCode = f.featureCode;
GO

-- Verify: every feature with its registry fields. section NULL = hidden from /setting.
SELECT featureCode, label, section, icon, route, sortOrder, active
FROM [dbo].[uiFeatures]
ORDER BY CASE WHEN section IS NULL THEN 1 ELSE 0 END, section, sortOrder, featureCode;
GO
