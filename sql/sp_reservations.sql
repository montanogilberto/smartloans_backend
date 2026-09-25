-- ============================================================
-- Reservations — customers book a time slot for a service from the
-- company's catalog (sp_reservationServices) via kiosk or WhatsApp.
-- Staff confirms via POS. Business hours: sp_reservationHours.
-- Requires sql/migrations/2026-09-24_reservation_catalogs.sql.
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'reservations')
CREATE TABLE [dbo].[reservations] (
    reservationId     INT IDENTITY PRIMARY KEY,
    companyId         INT             NOT NULL,
    clientName        NVARCHAR(120)   NOT NULL,
    phone             NVARCHAR(30)    NOT NULL,
    email             NVARCHAR(200)   NULL,
    reservationServiceId INT          NULL,
    serviceType       NVARCHAR(60)    NOT NULL,
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

        -- Service from the catalog, shared by create (1) and availability (6).
        -- Callers send reservationServiceId; a name in serviceType is still
        -- accepted for clients built before the catalog.
        DECLARE @serviceId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservations[0].reservationServiceId'));
        IF @serviceId IS NULL
            SELECT @serviceId = reservationServiceId
            FROM [dbo].[reservationServices]
            WHERE companyId = @companyId AND isActive = 1
              AND name = JSON_VALUE(@pjsonfile, '$.reservations[0].serviceType');

        DECLARE @serviceName NVARCHAR(60), @machineType NVARCHAR(30),
                @slotMinutes INT, @capacity INT, @machineMinutes INT, @machineCount INT;
        SELECT @serviceName = name, @machineType = machineType,
               @slotMinutes = durationMinutes, @capacity = capacity
        FROM [dbo].[reservationServices]
        WHERE reservationServiceId = @serviceId AND companyId = @companyId AND isActive = 1;

        -- Duration / capacity not set on the service: take them from its
        -- machines (longest cycle, how many in service), else 60 min / 1.
        IF @machineType IS NOT NULL AND (@slotMinutes IS NULL OR @capacity IS NULL)
            SELECT @machineMinutes = MAX(cycleMinutes),
                   @machineCount   = SUM(CASE WHEN status IN ('available', 'in_use') THEN 1 ELSE 0 END)
            FROM [dbo].[machines]
            WHERE companyId = @companyId AND machineType = @machineType AND status <> 'retired';
        SET @slotMinutes = COALESCE(@slotMinutes, @machineMinutes, 60);
        SET @capacity    = COALESCE(@capacity, @machineCount, 1);
        DECLARE @nowLocal DATETIME2 = CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'US Mountain Standard Time' AS DATETIME2);

        -- ── 0 / NULL: list ───────────────────────────────────────────────────
        IF @action IS NULL OR @action = 0
        BEGIN
            DECLARE @filterId   INT          = TRY_CONVERT(INT,  JSON_VALUE(@pjsonfile, '$.reservations[0].reservationId'));
            DECLARE @filterDate DATE         = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.reservations[0].date'));
            DECLARE @filterStat NVARCHAR(20) =                   JSON_VALUE(@pjsonfile, '$.reservations[0].status');
            DECLARE @listJson NVARCHAR(MAX) = (
                SELECT reservationId, companyId, clientName, phone, email,
                       reservationServiceId, serviceType, serviceDetail,
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
            DECLARE @serviceDetail NVARCHAR(120) = JSON_VALUE(@pjsonfile, '$.reservations[0].serviceDetail');
            DECLARE @resDate       DATE          = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.reservations[0].reservationDate'));
            DECLARE @timeSlot      NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.reservations[0].timeSlot');
            DECLARE @notes         NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.reservations[0].notes');

            IF @companyId IS NULL OR @clientName IS NULL OR @phone IS NULL
               OR @resDate IS NULL OR @timeSlot IS NULL
            BEGIN
                SELECT '{"error":"companyId, clientName, phone, reservationServiceId, reservationDate and timeSlot are required"}' AS jsonResult;
                RETURN;
            END
            IF @serviceName IS NULL
            BEGIN
                SELECT '{"error":"unknown_service","message":"Ese servicio no esta disponible."}' AS jsonResult;
                RETURN;
            END

            DECLARE @slotStart TIME = TRY_CONVERT(TIME, @timeSlot);
            IF @slotStart IS NULL
            BEGIN
                SELECT '{"error":"timeSlot must be HH:MM"}' AS jsonResult;
                RETURN;
            END

            -- A slot that already ended (Hermosillo time) can't be booked.
            IF DATEADD(MINUTE, DATEDIFF(MINUTE, '00:00', @slotStart) + @slotMinutes, CAST(@resDate AS DATETIME2)) <= @nowLocal
            BEGIN
                SELECT '{"error":"past_slot","message":"Ese horario ya paso. Elige otro."}' AS jsonResult;
                RETURN;
            END

            -- Capacity check + insert in one transaction; UPDLOCK/HOLDLOCK
            -- stops two simultaneous bookings (kiosk + WhatsApp) from both
            -- taking the last free spot.
            BEGIN TRANSACTION;
            IF (
                SELECT COUNT(*) FROM [dbo].[reservations] WITH (UPDLOCK, HOLDLOCK)
                WHERE companyId = @companyId AND reservationDate = @resDate
                  AND reservationServiceId = @serviceId AND status <> 'cancelled'
                  AND ABS(DATEDIFF(MINUTE, TRY_CONVERT(TIME, timeSlot), @slotStart)) < @slotMinutes
            ) >= @capacity
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT '{"error":"slot_taken","message":"Este horario ya esta reservado. Elige otro."}' AS jsonResult;
                RETURN;
            END

            INSERT INTO [dbo].[reservations]
                (companyId, clientName, phone, email, reservationServiceId, serviceType, serviceDetail,
                 reservationDate, timeSlot, notes, status)
            VALUES
                (@companyId, @clientName, @phone, @email, @serviceId, @serviceName, @serviceDetail,
                 @resDate, @timeSlot, @notes, 'pending');

            DECLARE @newId INT = SCOPE_IDENTITY();
            COMMIT TRANSACTION;
            DECLARE @createJson NVARCHAR(MAX) = (
                SELECT reservationId, companyId, clientName, phone, email,
                       reservationServiceId, serviceType, serviceDetail,
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
        -- "Today" is Hermosillo local date (UTC-7, no DST). With the UTC date,
        -- from 17:00 local today's reservations dropped out of the queue.
        IF @action = 5
        BEGIN
            DECLARE @todayLocal DATE = CAST(@nowLocal AS DATE);
            DECLARE @queueJson NVARCHAR(MAX) = (
                SELECT reservationId, clientName, phone, reservationServiceId, serviceType, serviceDetail,
                       CONVERT(NVARCHAR(10), reservationDate, 23) AS reservationDate,
                       timeSlot, notes, status,
                       CONVERT(NVARCHAR, created_At, 127) AS created_At
                FROM [dbo].[reservations]
                WHERE companyId = @companyId
                  AND status IN ('pending', 'confirmed')
                  AND reservationDate >= @todayLocal
                ORDER BY reservationDate, timeSlot
                FOR JSON PATH
            );
            SELECT ('{"result":[{"reservations":' + ISNULL(@queueJson, '[]') + '}]}') AS jsonResult;
            RETURN;
        END

        -- ── 6: free slots for one date + service (kiosk / WhatsApp calendar) ─
        -- Hours come from reservationHours (no row = closed). Only slots that
        -- fit entirely before closing, start in the future, and still have
        -- capacity left are returned.
        IF @action = 6
        BEGIN
            DECLARE @availDate DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.reservations[0].date'));
            IF @companyId IS NULL OR @availDate IS NULL OR @serviceName IS NULL
            BEGIN
                SELECT '{"error":"companyId, date and a valid reservationServiceId are required"}' AS jsonResult;
                RETURN;
            END

            -- 0 = Monday (1900-01-01 was a Monday); independent of @@DATEFIRST.
            DECLARE @dow INT = DATEDIFF(DAY, '19000101', @availDate) % 7;
            DECLARE @open TIME, @close TIME;
            SELECT @open = openTime, @close = closeTime
            FROM [dbo].[reservationHours]
            WHERE companyId = @companyId AND dayOfWeek = @dow;
            DECLARE @slotsJson NVARCHAR(MAX) = '[]';

            IF @open IS NOT NULL AND @availDate >= CAST(@nowLocal AS DATE)
            BEGIN
                WITH n AS (
                    SELECT a.d * 10 + b.d AS i
                    FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) a(d)
                    CROSS JOIN (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) b(d)
                ),
                slots AS (
                    SELECT DATEADD(MINUTE, i * @slotMinutes, @open) AS t
                    FROM n
                    WHERE (i + 1) * @slotMinutes <= DATEDIFF(MINUTE, @open, @close)
                ),
                counted AS (
                    SELECT s.t,
                           @capacity - (
                               SELECT COUNT(*) FROM [dbo].[reservations] r
                               WHERE r.companyId = @companyId AND r.reservationDate = @availDate
                                 AND r.reservationServiceId = @serviceId AND r.status <> 'cancelled'
                                 AND ABS(DATEDIFF(MINUTE, TRY_CONVERT(TIME, r.timeSlot), s.t)) < @slotMinutes
                           ) AS available
                    FROM slots s
                    WHERE @availDate > CAST(@nowLocal AS DATE) OR s.t > CAST(@nowLocal AS TIME)
                )
                SELECT @slotsJson = ISNULL((
                    SELECT CONVERT(NVARCHAR(5), t, 108) AS timeSlot, available
                    FROM counted WHERE available > 0
                    ORDER BY t
                    FOR JSON PATH
                ), '[]');
            END

            DECLARE @dayJson NVARCHAR(MAX) = (
                SELECT CONVERT(NVARCHAR(10), @availDate, 23) AS [date],
                       @serviceId AS reservationServiceId,
                       @serviceName AS serviceName,
                       @slotMinutes AS durationMinutes,
                       @capacity AS capacity,
                       CONVERT(NVARCHAR(5), @open, 108) AS [open],
                       CONVERT(NVARCHAR(5), @close, 108) AS [close],
                       JSON_QUERY(@slotsJson) AS slots
                FOR JSON PATH, INCLUDE_NULL_VALUES
            );
            SELECT ('{"result":' + @dayJson + '}') AS jsonResult;
            RETURN;
        END

        SELECT '{"error":"Unknown action"}' AS jsonResult;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
