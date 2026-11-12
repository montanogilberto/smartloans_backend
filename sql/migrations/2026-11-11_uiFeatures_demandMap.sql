-- =============================================================================
-- Register the "Mapa de demanda" UI feature (frontend route /demand-map) and
-- grant it to admin + manager.
--
-- Why: the frontend's hardcoded ROLE_UI defaults are REPLACED by each role's
-- uiFeatures from GET /roles, so a feature that only exists in
-- rolePermissions.ts never shows in the menu. It must be in dbo.uiFeatures and
-- granted in dbo.roleUiFeatures.
--
-- Idempotent: sp_uiFeatures_register upserts by featureCode and never revokes.
-- Run once per environment (DEV → QA → PROD). Check the target DB first.
-- =============================================================================
EXEC [dbo].[sp_uiFeatures_register] @pjsonfile = N'{
  "uiFeatures": [{
    "featureCode": "demandMap",
    "displayName": "Demand map",
    "label": "Mapa de demanda",
    "moduleCode": "pos",
    "section": "Catálogo",
    "icon": "mapOutline",
    "route": "/demand-map",
    "sortOrder": 100,
    "roles": ["admin", "manager"]
  }]
}';
