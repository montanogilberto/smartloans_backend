-- Rollback of 2026-11-09_reservation_holidays.sql.
-- Run the previous sql/sp_reservations.sql first (git history before 2026-11-09):
-- the current one reads this table. Deletes every company's holidays.
IF OBJECT_ID('dbo.sp_reservationSchedule', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_reservationSchedule;
GO
IF OBJECT_ID('dbo.sp_reservationHolidays', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_reservationHolidays;
GO
IF OBJECT_ID(N'dbo.reservationHolidays', N'U') IS NOT NULL DROP TABLE [dbo].[reservationHolidays];
GO
