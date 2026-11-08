-- =============================================================================
-- sp_roleUiFeatures_update — replace the UI features granted to one role.
--
-- Backs POST /roles/ui_features (the frontend /setting "Permisos por Rol"
-- screen, whose save was a console.log TODO until 2026-11-07). Extends the
-- hand-written roles module (sql/sp_roles.sql); dbo.roleUiFeatures is GLOBAL —
-- no companyId — so a change applies to that role in every company.
--
-- @pjsonfile: { "roleUiFeatures": [{ "roleCode": "employee",
--                                    "features": ["pos", "clients", ...] }] }
-- Returns one row: value (features now granted), msg, error ("0" ok, "1" refused).
--
-- Refuses: unknown/inactive role, the 'admin' role (always full access, the
-- screen locks it too), and any feature code not in dbo.uiFeatures (active).
-- Only ACTIVE features are replaced; grants of inactive features are kept,
-- since sp_roles never shows them and the screen can't have meant to drop them.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_roleUiFeatures_update] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @roleCode VARCHAR(50), @featuresJson NVARCHAR(MAX), @roleId INT;

    SELECT @roleCode     = LTRIM(RTRIM(LOWER(roleCode))),
           @featuresJson = features
    FROM OPENJSON(@pjsonfile, '$.roleUiFeatures')
    WITH (roleCode VARCHAR(50) '$.roleCode', features NVARCHAR(MAX) '$.features' AS JSON);

    SELECT @roleId = roleId FROM [dbo].[roles] WHERE code = @roleCode AND active = 1;

    IF @roleId IS NULL
    BEGIN
        SELECT 0 AS value, 'Unknown role' AS msg, '1' AS error;
        RETURN;
    END
    IF @roleCode = 'admin'
    BEGIN
        SELECT 0 AS value, 'The admin role always has every feature' AS msg, '1' AS error;
        RETURN;
    END
    IF @featuresJson IS NULL OR ISJSON(@featuresJson) = 0
    BEGIN
        SELECT 0 AS value, 'features must be an array' AS msg, '1' AS error;
        RETURN;
    END

    DECLARE @wanted TABLE (featureCode VARCHAR(100) PRIMARY KEY);
    INSERT INTO @wanted (featureCode)
    SELECT DISTINCT LTRIM(RTRIM(value)) FROM OPENJSON(@featuresJson) WHERE LTRIM(RTRIM(value)) <> '';

    IF EXISTS (SELECT 1 FROM @wanted w
               WHERE NOT EXISTS (SELECT 1 FROM [dbo].[uiFeatures] f
                                 WHERE f.featureCode = w.featureCode AND f.active = 1))
    BEGIN
        SELECT 0 AS value, 'Unknown feature code' AS msg, '1' AS error;
        RETURN;
    END

    BEGIN TRANSACTION;

        DELETE ruf
        FROM [dbo].[roleUiFeatures] ruf
        JOIN [dbo].[uiFeatures] f ON f.featureId = ruf.featureId
        WHERE ruf.roleId = @roleId
          AND f.active = 1
          AND f.featureCode NOT IN (SELECT featureCode FROM @wanted);

        INSERT INTO [dbo].[roleUiFeatures] (roleId, featureId)
        SELECT @roleId, f.featureId
        FROM @wanted w
        JOIN [dbo].[uiFeatures] f ON f.featureCode = w.featureCode AND f.active = 1
        WHERE NOT EXISTS (SELECT 1 FROM [dbo].[roleUiFeatures] ruf
                          WHERE ruf.roleId = @roleId AND ruf.featureId = f.featureId);

    COMMIT TRANSACTION;

    SELECT (SELECT COUNT(*) FROM [dbo].[roleUiFeatures] ruf
            JOIN [dbo].[uiFeatures] f ON f.featureId = ruf.featureId
            WHERE ruf.roleId = @roleId AND f.active = 1) AS value,
           'OK' AS msg, '0' AS error;
END
GO
