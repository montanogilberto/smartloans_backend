-- =============================================================================
-- Register the "Agentes IA" UI feature (frontend routes /ai-agents and
-- /ai-agents/settings) and grant it to admin + manager.
--
-- Why: GET /roles REPLACES the frontend's hardcoded ROLE_UI, so a feature that
-- only exists in rolePermissions.ts never shows in the menu. The EXEC at the end
-- of sql/sp_agents.sql did not reach production (GET /ui_features had no
-- "agents" on 2026-11-18); this file is the standalone, re-runnable version.
--
-- Idempotent: sp_uiFeatures_register upserts by featureCode and never revokes.
-- Run once per environment (DEV → QA → PROD). Check the target DB first.
-- =============================================================================
EXEC [dbo].[sp_uiFeatures_register] @pjsonfile = N'{
  "uiFeatures": [{
    "featureCode": "agents",
    "displayName": "AI agents",
    "label": "Agentes IA",
    "moduleCode": "pos",
    "section": "Catálogo",
    "icon": "sparklesOutline",
    "route": "/ai-agents",
    "sortOrder": 95,
    "roles": ["admin", "manager"]
  }]
}';
GO
