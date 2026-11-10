-- ============================================================
-- reservationHolidays — dates when a company is closed or keeps special
-- hours (holidays, inventory day, vacations). Overrides the weekly
-- reservationHours for that one date, per companyId.
--
-- Why:    the agents (WhatsApp, voice) and the kiosk only knew the weekly
--         hours, so they offered slots on holidays.
-- Writes: POST /reservationHolidays (sql/sp_reservationHolidays.sql).
-- Reads:  POST /reservationSchedule (sql/sp_reservationSchedule.sql) and
--         sp_reservations actions 1 and 6.
-- Run order: this file → sql/sp_reservationHolidays.sql →
--            sql/sp_reservationSchedule.sql → sql/sp_reservations.sql
--            (sql/migrations/README_reservation_schedule.md).
-- Rollback: 2026-11-09_reservation_holidays_ROLLBACK.sql
-- Safe to re-run.
-- ============================================================

-- openTime / closeTime both NULL = closed all day; both set = that day's hours.
IF OBJECT_ID(N'dbo.reservationHolidays', N'U') IS NULL
CREATE TABLE [dbo].[reservationHolidays] (
    reservationHolidayId INT IDENTITY(1,1) NOT NULL,
    companyId            INT          NOT NULL,
    holidayDate          DATE         NOT NULL,
    name                 NVARCHAR(80) NULL,
    openTime             TIME(0)      NULL,
    closeTime            TIME(0)      NULL,
    createdAt            DATETIME2    NOT NULL CONSTRAINT DF_reservationHolidays_createdAt DEFAULT (GETUTCDATE()),
    updatedAt            DATETIME2    NULL,
    CONSTRAINT PK_reservationHolidays PRIMARY KEY CLUSTERED (reservationHolidayId),
    CONSTRAINT UQ_reservationHolidays_company_date UNIQUE (companyId, holidayDate),
    CONSTRAINT CK_reservationHolidays_hours CHECK (
        (openTime IS NULL AND closeTime IS NULL)
        OR (openTime IS NOT NULL AND closeTime IS NOT NULL AND closeTime > openTime))
);
GO
