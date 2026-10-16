-- Kiosk reservation booking: customers book Lavado/Secado time slots from the PWA kiosk.
-- POS polls action=5 for today's queue; action=2 confirms, action=3 cancels, action=4 completes.

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

-- Next: run sql/sp_reservations.sql to (re)create dbo.sp_reservations.
-- It is not dropped here: a drop without the create left /reservations
-- returning 500 "Could not find stored procedure" in production.
