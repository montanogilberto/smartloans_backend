-- =============================================================================
-- Grant the 'employees' UI feature (Empleados catalog) via the DB-backed role catalog
-- =============================================================================
-- Forward-only, additive-only migration. EXECUTED against the live DB 2026-09-30
-- (it granted 'employee' too; revoked the same day, see the block at the end).
--
-- WHY: the frontend's hardcoded fallback (src/config/rolePermissions.ts)
-- already lists 'employees' under admin/manager, but GET /roles
-- (sp_roles, see sql/sp_roles.sql) is the actual runtime source of truth --
-- UserContext.tsx's loadRoleCatalog() overwrites the hardcoded ROLE_UI with
-- whatever this endpoint returns, on every app start. The 'employees' feature
-- was added to the frontend after sql/sp_roles.sql's original seed, so it was
-- never added to dbo.uiFeatures or granted to any role there -- admin/manager
-- see everything else but not the Empleados menu item.
--
-- WHAT:
--   1. dbo.uiFeatures: + 'employees' (moduleCode 'pos', same bucket as
--      clients/products/suppliers), only if not already present.
--   2. dbo.roleUiFeatures: grant ('admin','employees'), ('manager','employees'),
--      only for pairs not already granted. NOT the 'employee' role: the
--      module exposes every coworker's email/phone/address/emergency contacts
--      and allows edit/delete (PRD prd_employee.json: Admin + Manager).
-- Idempotent: every insert is WHERE NOT EXISTS, matching sql/sp_roles.sql's
-- own pattern -- never deletes or duplicates a row, safe to re-run.
-- =============================================================================

INSERT INTO [dbo].[uiFeatures] (featureCode, displayName, moduleCode)
SELECT 'employees', 'Employees', 'pos'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[uiFeatures] WHERE featureCode = 'employees');
GO

INSERT INTO [dbo].[roleUiFeatures] (roleId, featureId)
SELECT r.roleId, f.featureId
FROM (VALUES ('admin'), ('manager')) v(roleCode)
JOIN [dbo].[roles]      r ON r.code = v.roleCode
JOIN [dbo].[uiFeatures] f ON f.featureCode = 'employees'
WHERE NOT EXISTS (
    SELECT 1 FROM [dbo].[roleUiFeatures] ruf
    WHERE ruf.roleId = r.roleId AND ruf.featureId = f.featureId
);
GO

-- Revoke the 'employee' grant the first run of this script made (no-op otherwise).
DELETE ruf
FROM [dbo].[roleUiFeatures] ruf
JOIN [dbo].[roles]      r ON r.roleId = ruf.roleId
JOIN [dbo].[uiFeatures] f ON f.featureId = ruf.featureId
WHERE r.code = 'employee' AND f.featureCode = 'employees';
GO

-- Verify: should show 'employees' for admin and manager only.
SELECT r.code, f.featureCode
FROM [dbo].[roleUiFeatures] ruf
JOIN [dbo].[roles] r ON r.roleId = ruf.roleId
JOIN [dbo].[uiFeatures] f ON f.featureId = ruf.featureId
WHERE f.featureCode = 'employees'
ORDER BY r.code;
GO
