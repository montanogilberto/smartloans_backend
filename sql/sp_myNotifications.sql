-- ============================================================
-- Bandeja de notificaciones POR USUARIO (inbox de la campana).
-- Une NotificationDeliveries (fila por usuario, con isRead) con
-- PushNotifications (contenido). Da a la app un historial rastreable
-- de los pushes — el push del sistema desaparece, esto persiste.
-- ============================================================

IF OBJECT_ID('dbo.sp_pushNotifications_forUser', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_pushNotifications_forUser;
GO
CREATE PROCEDURE [dbo].[sp_pushNotifications_forUser]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @userId INT = JSON_VALUE(@pjsonfile, '$.userId')

    SELECT (SELECT
        (SELECT COUNT(*) FROM NotificationDeliveries
         WHERE userId = @userId AND ISNULL(isRead, 0) = 0) AS unreadCount,
        JSON_QUERY(ISNULL((
            SELECT TOP 50
                d.notificationDeliveryId, d.pushNotificationId,
                ISNULL(d.isRead, 0) AS isRead,
                CONVERT(NVARCHAR(19), d.created_At, 120) AS receivedAt,
                p.title, p.message, p.notificationType, p.priority,
                p.navigationRoute
            FROM NotificationDeliveries d
            INNER JOIN PushNotifications p ON p.pushNotificationId = d.pushNotificationId
            WHERE d.userId = @userId
            ORDER BY d.notificationDeliveryId DESC
            FOR JSON PATH), '[]')) AS notifications
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
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
    DECLARE @userId INT = JSON_VALUE(@pjsonfile, '$.userId')
    -- NULL = marcar todas las del usuario
    DECLARE @pushNotificationId INT = JSON_VALUE(@pjsonfile, '$.pushNotificationId')

    UPDATE NotificationDeliveries
    SET isRead = 1, readAt = GETUTCDATE()
    WHERE userId = @userId AND ISNULL(isRead, 0) = 0
      AND (@pushNotificationId IS NULL OR pushNotificationId = @pushNotificationId)

    SELECT ('{"marked":' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + '}') AS [jsonResult]
END
GO
