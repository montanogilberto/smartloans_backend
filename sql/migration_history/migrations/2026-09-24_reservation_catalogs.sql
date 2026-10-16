-- Reservation catalogs: the services a customer can book and the business
-- hours, per company, instead of hard-coded values inside sp_reservations.
-- Kiosk / WhatsApp list reservationServices (sp_reservationServices action 0)
-- and send the chosen reservationServiceId to sp_reservations.
--
-- Run order: this file → sql/sp_reservationServices.sql →
-- sql/sp_reservationHours.sql → sql/sp_reservations.sql

-- One row per bookable service, for any kind of business. How long a slot
-- lasts and how many bookings fit in it:
--   durationMinutes / capacity  when set, used as-is;
--   machineType (optional)      otherwise taken from dbo.machines of that
--                               type — longest cycleMinutes, count in service;
--   neither                     60 minutes, 1 booking.
IF OBJECT_ID(N'dbo.reservationServices', N'U') IS NULL
CREATE TABLE [dbo].[reservationServices] (
    reservationServiceId INT IDENTITY(1,1) NOT NULL,
    companyId            INT             NOT NULL,
    name                 NVARCHAR(60)    NOT NULL,
    description          NVARCHAR(250)   NULL,
    durationMinutes      INT             NULL,
    capacity             INT             NULL,
    machineType          NVARCHAR(30)    NULL,
    isActive             BIT             NOT NULL CONSTRAINT DF_reservationServices_isActive DEFAULT (1),
    createdAt            DATETIME2       NOT NULL CONSTRAINT DF_reservationServices_createdAt DEFAULT (GETUTCDATE()),
    updatedAt            DATETIME2       NULL,
    CONSTRAINT PK_reservationServices PRIMARY KEY CLUSTERED (reservationServiceId),
    CONSTRAINT CK_reservationServices_duration CHECK (durationMinutes IS NULL OR durationMinutes >= 5),
    CONSTRAINT CK_reservationServices_capacity CHECK (capacity IS NULL OR capacity >= 0)
);
GO

-- Opening hours per weekday, company local time (Hermosillo for now). dayOfWeek 0 = Monday …
-- 6 = Sunday. No row for a day = closed that day.
IF OBJECT_ID(N'dbo.reservationHours', N'U') IS NULL
CREATE TABLE [dbo].[reservationHours] (
    reservationHourId INT IDENTITY(1,1) NOT NULL,
    companyId         INT     NOT NULL,
    dayOfWeek         TINYINT NOT NULL,
    openTime          TIME(0) NOT NULL,
    closeTime         TIME(0) NOT NULL,
    createdAt         DATETIME2 NOT NULL CONSTRAINT DF_reservationHours_createdAt DEFAULT (GETUTCDATE()),
    updatedAt         DATETIME2 NULL,
    CONSTRAINT PK_reservationHours PRIMARY KEY CLUSTERED (reservationHourId),
    CONSTRAINT UQ_reservationHours_company_day UNIQUE (companyId, dayOfWeek),
    CONSTRAINT CK_reservationHours_day CHECK (dayOfWeek BETWEEN 0 AND 6),
    CONSTRAINT CK_reservationHours_range CHECK (closeTime > openTime)
);
GO

IF COL_LENGTH('dbo.reservations', 'reservationServiceId') IS NULL
    ALTER TABLE [dbo].[reservations] ADD reservationServiceId INT NULL;
GO

-- serviceType now stores the catalog name (up to 60 chars).
IF COL_LENGTH('dbo.reservations', 'serviceType') < 120
    ALTER TABLE [dbo].[reservations] ALTER COLUMN serviceType NVARCHAR(60) NOT NULL;
GO

-- ── Seed: Lavandería GMO (laundry, machine-backed) ─────────────────────────────────────────
-- Set @companyId before running; with NULL this block does nothing.
DECLARE @companyId INT = NULL;

IF @companyId IS NULL
    PRINT 'Seed skipped: set @companyId to the laundry''s companyId and run this block again.';
ELSE
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [dbo].[reservationServices] WHERE companyId = @companyId AND name = N'Lavado')
        INSERT INTO [dbo].[reservationServices] (companyId, name, machineType) VALUES (@companyId, N'Lavado', N'washer');
    IF NOT EXISTS (SELECT 1 FROM [dbo].[reservationServices] WHERE companyId = @companyId AND name = N'Secado')
        INSERT INTO [dbo].[reservationServices] (companyId, name, machineType) VALUES (@companyId, N'Secado', N'dryer');

    -- Mon–Fri 10–22, Sat 10–17, Sun 10–14
    INSERT INTO [dbo].[reservationHours] (companyId, dayOfWeek, openTime, closeTime)
    SELECT @companyId, d.dayOfWeek, d.openTime, d.closeTime
    FROM (VALUES (0, '10:00', '22:00'), (1, '10:00', '22:00'), (2, '10:00', '22:00'),
                 (3, '10:00', '22:00'), (4, '10:00', '22:00'), (5, '10:00', '17:00'),
                 (6, '10:00', '14:00')) d(dayOfWeek, openTime, closeTime)
    WHERE NOT EXISTS (SELECT 1 FROM [dbo].[reservationHours] h
                      WHERE h.companyId = @companyId AND h.dayOfWeek = d.dayOfWeek);

    -- Link reservations made before the catalog existed.
    UPDATE r SET r.reservationServiceId = s.reservationServiceId
    FROM [dbo].[reservations] r
    JOIN [dbo].[reservationServices] s ON s.companyId = r.companyId AND s.name = r.serviceType
    WHERE r.companyId = @companyId AND r.reservationServiceId IS NULL;
END
GO
