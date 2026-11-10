-- ============================================================
-- The company's schedule day by day: weekly hours (reservationHours) with
-- holidays / special days (reservationHolidays) applied. Read-only — this
-- is what the agents and the kiosk ask "is it open on <date>, until when?".
-- Dates in company local time (Hermosillo, UTC-7).
-- Tables: sql/migration_history/migrations/2026-09-24_reservation_catalogs.sql,
--         sql/migrations/2026-11-09_reservation_holidays.sql
-- Read-only: BEGIN TRY / CATCH, no transaction (nothing to roll back).
-- ============================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_reservationSchedule]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT  = TRY_CONVERT(INT,  JSON_VALUE(@pjsonfile, '$.reservationSchedule[0].companyId'));
        DECLARE @fromDate  DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.reservationSchedule[0].fromDate'));
        DECLARE @days      INT  = TRY_CONVERT(INT,  JSON_VALUE(@pjsonfile, '$.reservationSchedule[0].days'));

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END
        IF @fromDate IS NULL
            SET @fromDate = CAST(CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'US Mountain Standard Time' AS DATETIME2) AS DATE);
        IF @days IS NULL SET @days = 7;
        IF @days < 1 SET @days = 1;
        IF @days > 62 SET @days = 62;

        WITH n AS (
            SELECT a.d * 10 + b.d AS i
            FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) a(d)
            CROSS JOIN (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) b(d)
        ),
        d AS (
            SELECT DATEADD(DAY, i, @fromDate) AS dt,
                   -- 0 = Monday (1900-01-01 was a Monday); independent of @@DATEFIRST.
                   DATEDIFF(DAY, '19000101', DATEADD(DAY, i, @fromDate)) % 7 AS dow
            FROM n WHERE i < @days
        ),
        s AS (
            SELECT d.dt, d.dow, h.reservationHolidayId, h.name AS holidayName,
                   CASE WHEN h.reservationHolidayId IS NOT NULL THEN h.openTime  ELSE w.openTime  END AS openTime,
                   CASE WHEN h.reservationHolidayId IS NOT NULL THEN h.closeTime ELSE w.closeTime END AS closeTime
            FROM d
            LEFT JOIN [dbo].[reservationHours] w
                   ON w.companyId = @companyId AND w.dayOfWeek = d.dow
            LEFT JOIN [dbo].[reservationHolidays] h
                   ON h.companyId = @companyId AND h.holidayDate = d.dt
        )
        SELECT ('{"result":[{"reservationSchedule":' + ISNULL((
            SELECT CONVERT(NVARCHAR(10), dt, 23) AS [date],
                   dow AS dayOfWeek,
                   CHOOSE(dow + 1, N'lunes', N'martes', N'miércoles', N'jueves',
                                   N'viernes', N'sábado', N'domingo') AS weekday,
                   CAST(CASE WHEN openTime IS NULL THEN 0 ELSE 1 END AS BIT) AS isOpen,
                   CONVERT(NVARCHAR(5), openTime, 108)  AS openTime,
                   CONVERT(NVARCHAR(5), closeTime, 108) AS closeTime,
                   CAST(CASE WHEN reservationHolidayId IS NULL THEN 0 ELSE 1 END AS BIT) AS isHoliday,
                   holidayName
            FROM s
            ORDER BY dt
            FOR JSON PATH, INCLUDE_NULL_VALUES
        ), '[]') + '}]}') AS jsonResult;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
