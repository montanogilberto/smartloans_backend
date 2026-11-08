-- =============================================================================
-- Grant the 'clients' UI feature (Clientes + Mapa de clientes) to the
-- 'employee' role via the DB-backed role catalog.
--
-- Why a migration: the frontend fallback (config/rolePermissions.ts) is
-- overwritten on every app start by GET /roles, which reads
-- dbo.roleUiFeatures — so without this row the menu entry and the
-- /clients route stay hidden for employees no matter what the frontend says.
--
-- Idempotent: inserts only if the pair is not already granted.
-- =============================================================================

INSERT INTO [dbo].[roleUiFeatures] (roleId, featureId)
SELECT r.roleId, f.featureId
FROM [dbo].[roles]      r
JOIN [dbo].[uiFeatures] f ON f.featureCode = 'clients'
WHERE r.code = 'employee'
  AND NOT EXISTS (
    SELECT 1 FROM [dbo].[roleUiFeatures] ruf
    WHERE ruf.roleId = r.roleId AND ruf.featureId = f.featureId
);
GO

-- Verify: 'employee' should now appear.
SELECT r.code, f.featureCode
FROM [dbo].[roleUiFeatures] ruf
JOIN [dbo].[roles] r      ON r.roleId = ruf.roleId
JOIN [dbo].[uiFeatures] f ON f.featureId = ruf.featureId
WHERE f.featureCode = 'clients'
ORDER BY r.code;
GO
