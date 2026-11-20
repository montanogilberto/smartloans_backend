-- ============================================================
-- 2026-11-20 — Notificaciones: alcance por companyId + clientId + rol
--
-- 1) sp_pushNotifications_forUser (bandeja / campana):
--    - acepta { userId, companyId?, clientId? }.
--    - companyId: el que manda la app (contexto activo: Lavandería=1,
--      SmartLoans=1008); si no viene, se deriva como antes (clients primero,
--      users después — el bug conocido 1 vs 1008).
--    - clientId: si viene y pertenece a OTRO usuario, la bandeja sale vacía
--      (sesión cruzada/obsoleta nunca lee el inbox de otro).
--    - solo lista/cuenta notificaciones de ESA compañía
--      (ISNULL(targetCompanyId, companyId) = @companyId). Antes se colaban
--      broadcasts de Lavandería en el inbox de SmartLoans.
--    - materializa (lazy) broadcasts targetType='Role' para el rol del
--      usuario en esa compañía (userCompanies.roleId, o roles.code =
--      userCompanies.roleName cuando roleId es NULL). Así admin recibe las
--      notificaciones de sistema dirigidas a 'admin', prestamista las de
--      'lender', etc.
-- 2) sp_pushNotifications_markRead: mismo alcance por compañía (leer la
--    bandeja de SmartLoans no marca como leídas las del POS).
-- 3) sp_pushNotifications_activeUsers: acepta roleId opcional → usuarios
--    activos con ese rol en esa compañía (resuelve targetType 'Role' en el
--    envío push).
--
-- Llamadas sin los campos nuevos se comportan como antes (compatibles).
-- Nombres de tabla en minúsculas = definición viva (pushNotifications,
-- notificationDeliveries).
-- ============================================================

IF OBJECT_ID('dbo.sp_pushNotifications_forUser', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_pushNotifications_forUser;
GO
CREATE PROCEDURE [dbo].[sp_pushNotifications_forUser]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @userId    INT = JSON_VALUE(@pjsonfile, '$.userId');
    DECLARE @companyId INT = NULLIF(JSON_VALUE(@pjsonfile, '$.companyId'), 0);
    DECLARE @clientId  INT = NULLIF(JSON_VALUE(@pjsonfile, '$.clientId'), 0);

    -- clientId de OTRO usuario → bandeja vacía (nunca la de otro). Si el
    -- usuario no tiene clients ligado (staff/admin) no se bloquea.
    IF @clientId IS NOT NULL AND EXISTS (
        SELECT 1 FROM users WHERE clientId = @clientId AND userId <> @userId)
    BEGIN
        SELECT '{"unreadCount":0,"notifications":[]}' AS [jsonResult];
        RETURN;
    END

    -- Sin companyId explícito: derivarlo como antes (clients = fuente de
    -- verdad; users.companyId sigue en 1 para cuentas legacy de 1008).
    IF @companyId IS NULL
        SET @companyId = (
            SELECT TOP 1 ISNULL(c.companyId, u.companyId)
            FROM users u
            LEFT JOIN clients c ON c.clientId = u.clientId
            WHERE u.userId = @userId);

    -- Rol del usuario EN ESA compañía (roleId; si es NULL, por roleName→code).
    DECLARE @roleId INT = (
        SELECT TOP 1 ISNULL(uc.roleId, r.roleId)
        FROM userCompanies uc
        LEFT JOIN roles r ON r.code = uc.roleName
        WHERE uc.userId = @userId
          AND uc.companyId = @companyId
          AND uc.active = '1'
        ORDER BY uc.isDefault DESC, uc.userCompanyId);

    DECLARE @userCreatedAt DATETIME = ISNULL(
        (SELECT created_at FROM users WHERE userId = @userId), '1900-01-01');

    -- Materializa (lazy) las entregas de broadcasts 'Company' y 'Role': el
    -- envío masivo no crea filas por usuario (la DB es de 20MB), se crean
    -- aquí al abrir la bandeja. Solo broadcasts posteriores al registro del
    -- usuario (una cuenta nueva no recibe anuncios históricos).
    INSERT INTO notificationDeliveries (pushNotificationId, userId, isSent, isRead, sentAt, created_At)
    SELECT p.pushNotificationId, @userId, 1, 0, p.created_At, p.created_At
    FROM pushNotifications p
    WHERE ISNULL(p.targetCompanyId, p.companyId) = @companyId
      AND (   p.targetType = 'Company'
           OR (p.targetType = 'Role' AND @roleId IS NOT NULL AND p.targetRoleId = @roleId))
      AND p.created_At >= @userCreatedAt
      AND NOT EXISTS (SELECT 1 FROM notificationDeliveries d
                      WHERE d.pushNotificationId = p.pushNotificationId
                        AND d.userId = @userId);

    SELECT (SELECT
        (SELECT COUNT(*)
         FROM notificationDeliveries d
         INNER JOIN pushNotifications p ON p.pushNotificationId = d.pushNotificationId
         WHERE d.userId = @userId AND ISNULL(d.isRead, 0) = 0
           AND (@companyId IS NULL OR ISNULL(p.targetCompanyId, p.companyId) = @companyId)) AS unreadCount,
        JSON_QUERY(ISNULL((
            SELECT TOP 50
                d.notificationDeliveryId, d.pushNotificationId,
                ISNULL(d.isRead, 0) AS isRead,
                CONVERT(NVARCHAR(19), d.created_At, 120) AS receivedAt,
                p.title, p.message, p.notificationType, p.priority,
                p.navigationRoute
            FROM notificationDeliveries d
            INNER JOIN pushNotifications p ON p.pushNotificationId = d.pushNotificationId
            WHERE d.userId = @userId
              AND (@companyId IS NULL OR ISNULL(p.targetCompanyId, p.companyId) = @companyId)
            ORDER BY d.notificationDeliveryId DESC
            FOR JSON PATH), '[]')) AS notifications
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult];
END
GO

IF OBJECT_ID('dbo.sp_pushNotifications_markRead', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_pushNotifications_markRead;
GO
CREATE PROCEDURE [dbo].[sp_pushNotifications_markRead]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @userId    INT = JSON_VALUE(@pjsonfile, '$.userId');
    -- NULL = marcar todas las del usuario (en esa compañía, si viene)
    DECLARE @pushNotificationId INT = JSON_VALUE(@pjsonfile, '$.pushNotificationId');
    DECLARE @companyId INT = NULLIF(JSON_VALUE(@pjsonfile, '$.companyId'), 0);
    DECLARE @clientId  INT = NULLIF(JSON_VALUE(@pjsonfile, '$.clientId'), 0);

    IF @clientId IS NOT NULL AND EXISTS (
        SELECT 1 FROM users WHERE clientId = @clientId AND userId <> @userId)
    BEGIN
        SELECT '{"marked":0}' AS [jsonResult];
        RETURN;
    END

    UPDATE d
    SET isRead = 1, readAt = GETUTCDATE()
    FROM notificationDeliveries d
    INNER JOIN pushNotifications p ON p.pushNotificationId = d.pushNotificationId
    WHERE d.userId = @userId AND ISNULL(d.isRead, 0) = 0
      AND (@pushNotificationId IS NULL OR d.pushNotificationId = @pushNotificationId)
      AND (@companyId IS NULL OR ISNULL(p.targetCompanyId, p.companyId) = @companyId);

    SELECT ('{"marked":' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + '}') AS [jsonResult];
END
GO

IF OBJECT_ID('dbo.sp_pushNotifications_activeUsers', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_pushNotifications_activeUsers;
GO
CREATE PROCEDURE dbo.sp_pushNotifications_activeUsers
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    -- @pjsonfile is a flat object ({"companyId": 5}, {"companyId": null} or
    -- {"companyId": 1008, "roleId": 1}) — JSON_VALUE reads straight off it.
    DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.companyId');
    DECLARE @roleId    INT = JSON_VALUE(@pjsonfile, '$.roleId');

    IF @roleId IS NOT NULL
    BEGIN
        -- targetType 'Role': active users holding that role in that company
        -- (userCompanies.roleId, or roles.code = roleName when roleId is NULL).
        SELECT DISTINCT u.userId
        FROM userCompanies uc
        INNER JOIN users u ON u.userId = uc.userId
        LEFT JOIN roles r ON r.code = uc.roleName
        WHERE u.active = '1'
          AND uc.active = '1'
          AND (@companyId IS NULL OR uc.companyId = @companyId)
          AND ISNULL(uc.roleId, r.roleId) = @roleId
        FOR JSON PATH, ROOT('users');
        RETURN;
    END

    -- @companyId NULL -> every active user (targetType 'All').
    -- @companyId set  -> active users in that company (targetType 'Company').
    SELECT userId
    FROM dbo.users
    WHERE active = '1'
      AND (@companyId IS NULL OR companyId = @companyId)
    FOR JSON AUTO, ROOT('users');
END;
GO
