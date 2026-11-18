-- =============================================================================
-- Register the "Conversaciones WhatsApp" UI feature and grant it to
-- admin + manager + employee.
--
-- Why: employees attend customers but must not see the WhatsApp agent
-- dashboard, its setup or the dispatch log (all 'notificationDispatchLog').
-- 'whatsappChat' gates only the chat: /whatsapp-agent/conversations, the chat
-- dock, and Conversaciones on the client dashboard. GET /roles REPLACES the
-- frontend's hardcoded ROLE_UI, so without this row employees never see it.
--
-- Idempotent: sp_uiFeatures_register upserts by featureCode and never revokes.
-- Run once per environment (DEV → QA → PROD). Check the target DB first.
-- =============================================================================
EXEC [dbo].[sp_uiFeatures_register] @pjsonfile = N'{
  "uiFeatures": [{
    "featureCode": "whatsappChat",
    "displayName": "WhatsApp chat",
    "label": "Conversaciones WhatsApp",
    "moduleCode": "pos",
    "section": "Mensajes",
    "icon": "mailOutline",
    "route": "/whatsapp-agent/conversations",
    "sortOrder": 45,
    "roles": ["admin", "manager", "employee"]
  }]
}';
GO

-- Verify: admin, employee, manager.
SELECT r.code, f.featureCode
FROM [dbo].[roleUiFeatures] ruf
JOIN [dbo].[roles] r      ON r.roleId = ruf.roleId
JOIN [dbo].[uiFeatures] f ON f.featureId = ruf.featureId
WHERE f.featureCode = 'whatsappChat'
ORDER BY r.code;
GO
