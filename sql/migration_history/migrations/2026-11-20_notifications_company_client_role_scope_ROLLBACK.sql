-- ROLLBACK for 2026-11-20_notifications_company_client_role_scope.sql
-- Exact live definitions captured before the migration was applied.

IF OBJECT_ID('dbo.sp_pushNotifications_forUser', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_pushNotifications_forUser;
GO
-- sp_pushNotifications_forUser: 6 reference(s) rewritten
CREATE PROCEDURE [dbo].[sp_pushNotifications_forUser]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @userId INT = JSON_VALUE(@pjsonfile, '$.userId')

    -- Materializa (lazy) las entregas de broadcasts 'Company': el envío masivo
    -- no crea filas por usuario (102 filas por oferta ahogarían la DB de 20MB),
    -- así que se crean aquí, solo cuando el usuario abre su bandeja.
    -- companyId por clients (fuente de verdad), NO users: cuentas legacy
    -- siguen con users.companyId=1 (Lavanderia) mientras el cliente vive en
    -- 1008 (SmartLoans) — el bug conocido 1 vs 1008.
    DECLARE @companyId INT = (
        SELECT TOP 1 ISNULL(c.companyId, u.companyId)
        FROM users u
        LEFT JOIN clients c ON c.clientId = u.clientId
        WHERE u.userId = @userId);
    INSERT INTO notificationDeliveries (pushNotificationId, userId, isSent, isRead, sentAt, created_At)
    SELECT p.pushNotificationId, @userId, 1, 0, p.created_At, p.created_At
    FROM pushNotifications p
    WHERE p.targetType = 'Company'
      AND p.targetCompanyId = @companyId
      -- Solo broadcasts posteriores al registro del usuario: una cuenta nueva
      -- no debe recibir anuncios históricos (p.ej. ofertas de capital que ya
      -- se prestó antes de que existiera).
      AND p.created_At >= ISNULL((SELECT created_at FROM users WHERE userId = @userId), '1900-01-01')
      AND NOT EXISTS (SELECT 1 FROM notificationDeliveries d
                      WHERE d.pushNotificationId = p.pushNotificationId
                        AND d.userId = @userId);

    SELECT (SELECT
        (SELECT COUNT(*) FROM notificationDeliveries
         WHERE userId = @userId AND ISNULL(isRead, 0) = 0) AS unreadCount,
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
            ORDER BY d.notificationDeliveryId DESC
            FOR JSON PATH), '[]')) AS notifications
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
END
GO

IF OBJECT_ID('dbo.sp_pushNotifications_markRead', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_pushNotifications_markRead;
GO
-- sp_pushNotifications_markRead: 1 reference(s) rewritten
CREATE PROCEDURE [dbo].[sp_pushNotifications_markRead]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @userId INT = JSON_VALUE(@pjsonfile, '$.userId')
    -- NULL = marcar todas las del usuario
    DECLARE @pushNotificationId INT = JSON_VALUE(@pjsonfile, '$.pushNotificationId')

    UPDATE notificationDeliveries
    SET isRead = 1, readAt = GETUTCDATE()
    WHERE userId = @userId AND ISNULL(isRead, 0) = 0
      AND (@pushNotificationId IS NULL OR pushNotificationId = @pushNotificationId)

    SELECT ('{"marked":' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + '}') AS [jsonResult]
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
    -- @pjsonfile is a flat object (e.g. {"companyId": 5} or {"companyId": null}),
    -- not an array, so JSON_VALUE reads straight off @pjsonfile -- OPENJSON
    -- without an array path returns one row per key with a scalar `value`,
    -- which JSON_VALUE(value, '$.key') can't re-parse.
    DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.companyId');

    -- @companyId NULL -> every active user (targetType 'All').
    -- @companyId set  -> active users in that company (targetType 'Company').
    SELECT userId
    FROM dbo.users
    WHERE active = '1'
      AND (@companyId IS NULL OR companyId = @companyId)
    FOR JSON AUTO, ROOT('users');
END;
GO
