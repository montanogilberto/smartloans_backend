-- ============================================================
-- Business hours for reservations, per company and weekday
-- (company local time, Hermosillo for now; dayOfWeek 0 = Monday … 6 = Sunday).
-- No row for a day = closed. sp_reservations action 6 builds the
-- free slots from these hours.
-- Table: sql/migrations/2026-09-24_reservation_catalogs.sql
-- ============================================================

IF OBJECT_ID('dbo.sp_reservationHours', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_reservationHours;
GO
CREATE PROCEDURE [dbo].[sp_reservationHours]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action    INT     = TRY_CONVERT(INT,     JSON_VALUE(@pjsonfile, '$.reservationHours[0].action'));
        DECLARE @companyId INT     = TRY_CONVERT(INT,     JSON_VALUE(@pjsonfile, '$.reservationHours[0].companyId'));
        DECLARE @dayOfWeek TINYINT = TRY_CONVERT(TINYINT, JSON_VALUE(@pjsonfile, '$.reservationHours[0].dayOfWeek'));
        DECLARE @openTime  TIME(0) = TRY_CONVERT(TIME(0), JSON_VALUE(@pjsonfile, '$.reservationHours[0].openTime'));
        DECLARE @closeTime TIME(0) = TRY_CONVERT(TIME(0), JSON_VALUE(@pjsonfile, '$.reservationHours[0].closeTime'));

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END

        -- ── 1: set hours for a day (insert or update) ────────────────────────
        IF @action = 1
        BEGIN
            IF @dayOfWeek IS NULL OR @dayOfWeek > 6 OR @openTime IS NULL OR @closeTime IS NULL
               OR @closeTime <= @openTime
            BEGIN
                SELECT '{"error":"dayOfWeek (0-6), openTime and closeTime (HH:MM, after openTime) are required"}' AS jsonResult;
                RETURN;
            END
            UPDATE [dbo].[reservationHours]
            SET openTime = @openTime, closeTime = @closeTime, updatedAt = GETUTCDATE()
            WHERE companyId = @companyId AND dayOfWeek = @dayOfWeek;
            IF @@ROWCOUNT = 0
                INSERT INTO [dbo].[reservationHours] (companyId, dayOfWeek, openTime, closeTime)
                VALUES (@companyId, @dayOfWeek, @openTime, @closeTime);
        END

        -- ── 3: close a day ───────────────────────────────────────────────────
        ELSE IF @action = 3
        BEGIN
            DELETE FROM [dbo].[reservationHours]
            WHERE companyId = @companyId AND dayOfWeek = @dayOfWeek;
        END

        -- ── 0 / NULL (and after writes): the company's week ──────────────────
        DECLARE @listJson NVARCHAR(MAX) = (
            SELECT dayOfWeek,
                   CONVERT(NVARCHAR(5), openTime, 108)  AS openTime,
                   CONVERT(NVARCHAR(5), closeTime, 108) AS closeTime
            FROM [dbo].[reservationHours]
            WHERE companyId = @companyId
            ORDER BY dayOfWeek
            FOR JSON PATH
        );
        SELECT ('{"result":[{"reservationHours":' + ISNULL(@listJson, '[]') + '}]}') AS jsonResult;

    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
