-- ============================================================
-- Laundry service reservations — customers book a time slot
-- for Lavado or Secado from the kiosk. Staff confirms via POS.
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'reservations')
CREATE TABLE [dbo].[reservations] (
    reservationId     INT IDENTITY PRIMARY KEY,
    companyId         INT             NOT NULL,
    clientName        NVARCHAR(120)   NOT NULL,
    phone             NVARCHAR(30)    NOT NULL,
    email             NVARCHAR(200)   NULL,
    serviceType       NVARCHAR(40)    NOT NULL,
    serviceDetail     NVARCHAR(120)   NULL,
    reservationDate   DATE            NOT NULL,
    timeSlot          NVARCHAR(10)    NOT NULL,
    notes             NVARCHAR(500)   NULL,
    status            NVARCHAR(20)    NOT NULL DEFAULT 'pending',
    confirmedByUserId INT             NULL,
    confirmedAt       DATETIME2       NULL,
    created_At        DATETIME2       NOT NULL DEFAULT GETUTCDATE(),
    updated_At        DATETIME2       NULL
);
GO

IF OBJECT_ID('dbo.sp_reservations', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_reservations;
GO
CREATE PROCEDURE [dbo].[sp_reservations]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action    INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservations[0].action'));
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservations[0].companyId'));

        -- ── 0 / NULL: list ───────────────────────────────────────────────────
        IF @action IS NULL OR @action = 0
        BEGIN
            DECLARE @filterId   INT          = TRY_CONVERT(INT,  JSON_VALUE(@pjsonfile, '$.reservations[0].reservationId'));
            DECLARE @filterDate DATE         = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.reservations[0].date'));
            DECLARE @filterStat NVARCHAR(20) =                   JSON_VALUE(@pjsonfile, '$.reservations[0].status');
            DECLARE @listJson NVARCHAR(MAX) = (
                SELECT reservationId, companyId, clientName, phone, email,
                       serviceType, serviceDetail,
                       CONVERT(NVARCHAR(10), reservationDate, 23) AS reservationDate,
                       timeSlot, notes, status, confirmedByUserId,
                       CONVERT(NVARCHAR, confirmedAt,  127) AS confirmedAt,
                       CONVERT(NVARCHAR, created_At, 127)  AS created_At
                FROM [dbo].[reservations]
                WHERE companyId = @companyId
                  AND (@filterId   IS NULL OR reservationId   = @filterId)
                  AND (@filterDate IS NULL OR reservationDate = @filterDate)
                  AND (@filterStat IS NULL OR status          = @filterStat)
                ORDER BY reservationDate, timeSlot
                FOR JSON PATH
            );
            SELECT ('{"result":[{"reservations":' + ISNULL(@listJson, '[]') + '}]}') AS jsonResult;
            RETURN;
        END

        -- ── 1: create ────────────────────────────────────────────────────────
        IF @action = 1
        BEGIN
            DECLARE @clientName    NVARCHAR(120) = JSON_VALUE(@pjsonfile, '$.reservations[0].clientName');
            DECLARE @phone         NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.reservations[0].phone');
            DECLARE @email         NVARCHAR(200) = JSON_VALUE(@pjsonfile, '$.reservations[0].email');
            DECLARE @serviceType   NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.reservations[0].serviceType');
            DECLARE @serviceDetail NVARCHAR(120) = JSON_VALUE(@pjsonfile, '$.reservations[0].serviceDetail');
            DECLARE @resDate       DATE          = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.reservations[0].reservationDate'));
            DECLARE @timeSlot      NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.reservations[0].timeSlot');
            DECLARE @notes         NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.reservations[0].notes');

            IF @companyId IS NULL OR @clientName IS NULL OR @phone IS NULL
               OR @serviceType IS NULL OR @resDate IS NULL OR @timeSlot IS NULL
            BEGIN
                SELECT '{"error":"companyId, clientName, phone, serviceType, reservationDate and timeSlot are required"}' AS jsonResult;
                RETURN;
            END

            IF EXISTS (
                SELECT 1 FROM [dbo].[reservations]
                WHERE companyId = @companyId AND reservationDate = @resDate
                  AND timeSlot = @timeSlot AND serviceType = @serviceType
                  AND status <> 'cancelled'
            )
            BEGIN
                SELECT '{"error":"slot_taken","message":"Este horario ya esta reservado. Elige otro."}' AS jsonResult;
                RETURN;
            END

            INSERT INTO [dbo].[reservations]
                (companyId, clientName, phone, email, serviceType, serviceDetail,
                 reservationDate, timeSlot, notes, status)
            VALUES
                (@companyId, @clientName, @phone, @email, @serviceType, @serviceDetail,
                 @resDate, @timeSlot, @notes, 'pending');

            DECLARE @newId INT = SCOPE_IDENTITY();
            DECLARE @createJson NVARCHAR(MAX) = (
                SELECT reservationId, companyId, clientName, phone, email,
                       serviceType, serviceDetail,
                       CONVERT(NVARCHAR(10), reservationDate, 23) AS reservationDate,
                       timeSlot, notes, status,
                       CONVERT(NVARCHAR, created_At, 127) AS created_At
                FROM [dbo].[reservations] WHERE reservationId = @newId
                FOR JSON PATH
            );
            SELECT ('{"result":[{"reservations":' + ISNULL(@createJson, '[]') + '}]}') AS jsonResult;
            RETURN;
        END

        -- ── 2: confirm ───────────────────────────────────────────────────────
        IF @action = 2
        BEGIN
            DECLARE @resId2  INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservations[0].reservationId'));
            DECLARE @userId2 INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservations[0].confirmedByUserId'));
            UPDATE [dbo].[reservations]
            SET status = 'confirmed', confirmedByUserId = @userId2,
                confirmedAt = GETUTCDATE(), updated_At = GETUTCDATE()
            WHERE reservationId = @resId2 AND companyId = @companyId AND status = 'pending';
            DECLARE @confJson NVARCHAR(MAX) = (
                SELECT reservationId, status FROM [dbo].[reservations] WHERE reservationId = @resId2
                FOR JSON PATH
            );
            SELECT ('{"result":[{"reservations":' + ISNULL(@confJson, '[]') + '}]}') AS jsonResult;
            RETURN;
        END

        -- ── 3: cancel ────────────────────────────────────────────────────────
        IF @action = 3
        BEGIN
            DECLARE @resId3 INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservations[0].reservationId'));
            UPDATE [dbo].[reservations]
            SET status = 'cancelled', updated_At = GETUTCDATE()
            WHERE reservationId = @resId3 AND companyId = @companyId;
            DECLARE @cancJson NVARCHAR(MAX) = (
                SELECT reservationId, status FROM [dbo].[reservations] WHERE reservationId = @resId3
                FOR JSON PATH
            );
            SELECT ('{"result":[{"reservations":' + ISNULL(@cancJson, '[]') + '}]}') AS jsonResult;
            RETURN;
        END

        -- ── 4: complete ──────────────────────────────────────────────────────
        IF @action = 4
        BEGIN
            DECLARE @resId4 INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservations[0].reservationId'));
            UPDATE [dbo].[reservations]
            SET status = 'completed', updated_At = GETUTCDATE()
            WHERE reservationId = @resId4 AND companyId = @companyId;
            DECLARE @compJson NVARCHAR(MAX) = (
                SELECT reservationId, status FROM [dbo].[reservations] WHERE reservationId = @resId4
                FOR JSON PATH
            );
            SELECT ('{"result":[{"reservations":' + ISNULL(@compJson, '[]') + '}]}') AS jsonResult;
            RETURN;
        END

        -- ── 5: POS queue (pending + confirmed, today onward) ─────────────────
        IF @action = 5
        BEGIN
            DECLARE @queueJson NVARCHAR(MAX) = (
                SELECT reservationId, clientName, phone, serviceType, serviceDetail,
                       CONVERT(NVARCHAR(10), reservationDate, 23) AS reservationDate,
                       timeSlot, notes, status,
                       CONVERT(NVARCHAR, created_At, 127) AS created_At
                FROM [dbo].[reservations]
                WHERE companyId = @companyId
                  AND status IN ('pending', 'confirmed')
                  AND reservationDate >= CAST(GETUTCDATE() AS DATE)
                ORDER BY reservationDate, timeSlot
                FOR JSON PATH
            );
            SELECT ('{"result":[{"reservations":' + ISNULL(@queueJson, '[]') + '}]}') AS jsonResult;
            RETURN;
        END

        SELECT '{"error":"Unknown action"}' AS jsonResult;

    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
