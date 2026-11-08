-- =============================================================================
-- Module/feature registry SPs over dbo.uiFeatures (see
-- sql/migrations/2026-11-07_uiFeatures_registry.sql for the columns).
-- Part of the hand-written roles catalog (sql/sp_roles.sql), not a factory module.
--
--   sp_uiFeatures_register  — called by every factory-generated module's SQL
--                             (emitted by posgmo-factory's feature_registry stage)
--   sp_uiFeatures_all       — backs GET /ui_features
--   sp_roleUiFeatures_update (separate file) — the /setting "Guardar cambios" write
-- =============================================================================

-- ── sp_uiFeatures_register ───────────────────────────────────────────────────
-- @pjsonfile: { "uiFeatures": [{ "featureCode": "suppliers",
--                                "displayName": "Suppliers", "label": "Proveedores",
--                                "moduleCode": "pos", "section": "Catálogo",
--                                "icon": "peopleOutline", "route": "/suppliers",
--                                "sortOrder": 100, "roles": ["admin", "manager"] }] }
-- Upserts by featureCode (unique). On UPDATE only non-null fields overwrite, so a
-- re-run of a module's SQL never blanks what an admin set. Grants each listed
-- role if not already granted; NEVER revokes (a re-run must not undo /setting).
-- Returns one row: value (featureId), msg, error ("0" ok, "1" refused).
CREATE OR ALTER PROCEDURE [dbo].[sp_uiFeatures_register] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @featureCode NVARCHAR(50), @displayName NVARCHAR(100), @label NVARCHAR(100),
            @moduleCode NVARCHAR(50), @section NVARCHAR(50), @icon NVARCHAR(50),
            @route NVARCHAR(200), @sortOrder INT, @roles NVARCHAR(MAX), @featureId INT;

    SELECT @featureCode = LTRIM(RTRIM(featureCode)), @displayName = displayName, @label = label,
           @moduleCode = moduleCode, @section = section, @icon = icon, @route = route,
           @sortOrder = sortOrder, @roles = roles
    FROM OPENJSON(@pjsonfile, '$.uiFeatures')
    WITH (featureCode NVARCHAR(50)  '$.featureCode',
          displayName NVARCHAR(100) '$.displayName',
          label       NVARCHAR(100) '$.label',
          moduleCode  NVARCHAR(50)  '$.moduleCode',
          section     NVARCHAR(50)  '$.section',
          icon        NVARCHAR(50)  '$.icon',
          route       NVARCHAR(200) '$.route',
          sortOrder   INT           '$.sortOrder',
          roles       NVARCHAR(MAX) '$.roles' AS JSON);

    IF @featureCode IS NULL OR @featureCode = ''
    BEGIN
        SELECT 0 AS value, 'featureCode is required' AS msg, '1' AS error;
        RETURN;
    END

    BEGIN TRANSACTION;

        SELECT @featureId = featureId FROM [dbo].[uiFeatures] WITH (UPDLOCK, HOLDLOCK)
        WHERE featureCode = @featureCode;

        IF @featureId IS NULL
        BEGIN
            INSERT INTO [dbo].[uiFeatures] (featureCode, displayName, moduleCode, active,
                                            label, section, icon, route, sortOrder)
            VALUES (@featureCode, COALESCE(@displayName, @label, @featureCode), @moduleCode, 1,
                    @label, @section, @icon, @route, @sortOrder);
            SET @featureId = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [dbo].[uiFeatures]
            SET displayName = COALESCE(@displayName, displayName),
                moduleCode  = COALESCE(@moduleCode,  moduleCode),
                label       = COALESCE(@label,       label),
                section     = COALESCE(@section,     section),
                icon        = COALESCE(@icon,        icon),
                route       = COALESCE(@route,       route),
                sortOrder   = COALESCE(@sortOrder,   sortOrder),
                active      = 1
            WHERE featureId = @featureId;
        END

        IF @roles IS NOT NULL AND ISJSON(@roles) = 1
            INSERT INTO [dbo].[roleUiFeatures] (roleId, featureId)
            SELECT r.roleId, @featureId
            FROM OPENJSON(@roles) j
            JOIN [dbo].[roles] r ON r.code = LTRIM(RTRIM(LOWER(j.value))) AND r.active = 1
            WHERE NOT EXISTS (SELECT 1 FROM [dbo].[roleUiFeatures] ruf
                              WHERE ruf.roleId = r.roleId AND ruf.featureId = @featureId);

    COMMIT TRANSACTION;

    SELECT @featureId AS value, 'OK' AS msg, '0' AS error;
END
GO

-- ── sp_uiFeatures_all ────────────────────────────────────────────────────────
-- Every active feature with its registry fields, as a JSON array (wrapped in
-- the {"result": [...]} envelope by modules/roles.py, like sp_roles).
CREATE OR ALTER PROCEDURE [dbo].[sp_uiFeatures_all]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ISNULL((
        SELECT f.featureId, f.featureCode, f.displayName, f.label, f.moduleCode,
               f.section, f.icon, f.route, f.sortOrder
        FROM [dbo].[uiFeatures] f
        WHERE f.active = 1
        ORDER BY CASE WHEN f.section IS NULL THEN 1 ELSE 0 END, f.section,
                 ISNULL(f.sortOrder, 2147483647), f.featureCode
        FOR JSON PATH, INCLUDE_NULL_VALUES
    ), '[]') AS featuresJson;
END
GO
