-- ============================================================
-- Holidays / special days per company: closed all day (no hours) or open
-- with that day's own hours. Overrides reservationHours for that date.
-- Table: sql/migrations/2026-11-09_reservation_holidays.sql
-- Pattern (posgmo-factory agents/database): writes inside
-- BEGIN TRY / BEGIN TRANSACTION / COMMIT, CATCH rolls back.
-- ============================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_reservationHolidays]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    Example (action: 0 = list, 1 = set a date, 3 = remove a date):
      { "reservationHolidays": [{ "action": 1, "companyId": 1, "holidayDate": "2026-12-25",
                                  "name": "Navidad", "openTime": null, "closeTime": null }] }
      openTime + closeTime both empty = closed all day; both set = that day's hours.
      List: fromDate (default today, Hermosillo) .. toDate (optional).
    */

    DECLARE @action      INT,
            @companyId   INT,
            @holidayDate DATE,
            @name        NVARCHAR(80),
            @openTime    TIME(0),
            @closeTime   TIME(0),
            @fromDate    DATE,
            @toDate      DATE;

    BEGIN TRY
        SELECT TOP (1)
            @action      = TRY_CONVERT(INT,     JSON_VALUE(value, '$.action')),
            @companyId   = TRY_CONVERT(INT,     JSON_VALUE(value, '$.companyId')),
            @holidayDate = TRY_CONVERT(DATE,    JSON_VALUE(value, '$.holidayDate')),
            @name        =                      JSON_VALUE(value, '$.name'),
            @openTime    = TRY_CONVERT(TIME(0), JSON_VALUE(value, '$.openTime')),
            @closeTime   = TRY_CONVERT(TIME(0), JSON_VALUE(value, '$.closeTime')),
            @fromDate    = TRY_CONVERT(DATE,    JSON_VALUE(value, '$.fromDate')),
            @toDate      = TRY_CONVERT(DATE,    JSON_VALUE(value, '$.toDate'))
        FROM OPENJSON(@pjsonfile, '$.reservationHolidays');

        -- Validations (before the transaction: nothing to roll back yet)
        IF @companyId IS NULL
            RAISERROR('companyId is required', 16, 1);
        IF @action IS NOT NULL AND @action NOT IN (0, 1, 3)
            RAISERROR('Invalid action (0 = list, 1 = set a date, 3 = remove a date)', 16, 1);
        IF @action IN (1, 3) AND @holidayDate IS NULL
            RAISERROR('holidayDate (YYYY-MM-DD) is required', 16, 1);
        IF @action = 1 AND ((@openTime IS NULL AND @closeTime IS NOT NULL)
                            OR (@openTime IS NOT NULL AND (@closeTime IS NULL OR @closeTime <= @openTime)))
            RAISERROR('openTime and closeTime (HH:MM) go together, closeTime after openTime; both empty = closed all day', 16, 1);

        IF @action IN (1, 3)
        BEGIN
            BEGIN TRANSACTION;

            -- ── 1: set a date (insert or update) ─────────────────────────────
            IF @action = 1
            BEGIN
                -- UPDLOCK + HOLDLOCK: two saves of the same date at once can't
                -- both miss the UPDATE and both INSERT (UQ violation).
                UPDATE [dbo].[reservationHolidays] WITH (UPDLOCK, HOLDLOCK)
                SET name = @name, openTime = @openTime, closeTime = @closeTime, updatedAt = GETUTCDATE()
                WHERE companyId = @companyId AND holidayDate = @holidayDate;

                IF @@ROWCOUNT = 0
                    INSERT INTO [dbo].[reservationHolidays] (companyId, holidayDate, name, openTime, closeTime)
                    VALUES (@companyId, @holidayDate, @name, @openTime, @closeTime);
            END

            -- ── 3: remove a date (back to the weekly hours) ──────────────────
            ELSE IF @action = 3
            BEGIN
                DELETE FROM [dbo].[reservationHolidays]
                WHERE companyId = @companyId AND holidayDate = @holidayDate;
            END

            COMMIT TRANSACTION;
        END

        -- ── 0 / NULL (and after writes): the company's holidays ──────────────
        IF @fromDate IS NULL
            SET @fromDate = CAST(CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'US Mountain Standard Time' AS DATETIME2) AS DATE);

        DECLARE @listJson NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(10), holidayDate, 23) AS holidayDate,
                   name,
                   CAST(CASE WHEN openTime IS NULL THEN 0 ELSE 1 END AS BIT) AS isOpen,
                   CONVERT(NVARCHAR(5), openTime, 108)  AS openTime,
                   CONVERT(NVARCHAR(5), closeTime, 108) AS closeTime
            FROM [dbo].[reservationHolidays]
            WHERE companyId = @companyId
              AND holidayDate >= @fromDate
              AND (@toDate IS NULL OR holidayDate <= @toDate)
            ORDER BY holidayDate
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SELECT ('{"result":[{"reservationHolidays":' + ISNULL(@listJson, '[]') + '}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
