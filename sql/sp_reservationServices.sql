-- ============================================================
-- Catalog of bookable services per company (any business: Lavado,
-- Corte de cabello, Lavado de auto, …). Kiosk / WhatsApp / POS list it
-- (action 0) and send the chosen reservationServiceId to sp_reservations.
-- Table: sql/migrations/2026-09-24_reservation_catalogs.sql
-- ============================================================

IF OBJECT_ID('dbo.sp_reservationServices', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_reservationServices;
GO
CREATE PROCEDURE [dbo].[sp_reservationServices]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action      INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservationServices[0].action'));
        DECLARE @companyId   INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservationServices[0].companyId'));
        DECLARE @serviceId   INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservationServices[0].reservationServiceId'));
        DECLARE @name        NVARCHAR(60)  =                  JSON_VALUE(@pjsonfile, '$.reservationServices[0].name');
        DECLARE @description NVARCHAR(250) =                  JSON_VALUE(@pjsonfile, '$.reservationServices[0].description');
        DECLARE @duration    INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservationServices[0].durationMinutes'));
        DECLARE @capacity    INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.reservationServices[0].capacity'));
        DECLARE @machineType NVARCHAR(30)  =                  JSON_VALUE(@pjsonfile, '$.reservationServices[0].machineType');
        DECLARE @isActive    BIT           = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.reservationServices[0].isActive'));

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END

        -- ── 1: insert ────────────────────────────────────────────────────────
        IF @action = 1
        BEGIN
            IF @name IS NULL
            BEGIN
                SELECT '{"error":"name is required"}' AS jsonResult;
                RETURN;
            END
            INSERT INTO [dbo].[reservationServices] (companyId, name, description, durationMinutes, capacity, machineType)
            VALUES (@companyId, @name, @description, @duration, @capacity, @machineType);
            SET @serviceId = SCOPE_IDENTITY();
        END

        -- ── 2: update (only the keys sent; send null to clear an optional one)
        ELSE IF @action = 2
        BEGIN
            DECLARE @item NVARCHAR(MAX) = JSON_QUERY(@pjsonfile, '$.reservationServices[0]');
            UPDATE [dbo].[reservationServices]
            SET name            = ISNULL(@name, name),
                description     = CASE WHEN EXISTS (SELECT 1 FROM OPENJSON(@item) WHERE [key] = 'description')     THEN @description ELSE description END,
                durationMinutes = CASE WHEN EXISTS (SELECT 1 FROM OPENJSON(@item) WHERE [key] = 'durationMinutes') THEN @duration    ELSE durationMinutes END,
                capacity        = CASE WHEN EXISTS (SELECT 1 FROM OPENJSON(@item) WHERE [key] = 'capacity')        THEN @capacity    ELSE capacity END,
                machineType     = CASE WHEN EXISTS (SELECT 1 FROM OPENJSON(@item) WHERE [key] = 'machineType')     THEN @machineType ELSE machineType END,
                isActive        = ISNULL(@isActive, isActive),
                updatedAt       = GETUTCDATE()
            WHERE reservationServiceId = @serviceId AND companyId = @companyId;
        END

        -- ── 3: deactivate (kept for existing reservations) ───────────────────
        ELSE IF @action = 3
        BEGIN
            UPDATE [dbo].[reservationServices]
            SET isActive = 0, updatedAt = GETUTCDATE()
            WHERE reservationServiceId = @serviceId AND companyId = @companyId;
        END

        -- ── 0 / NULL: list active services (all, with includeInactive) ───────
        -- Writes also return the affected row in the same shape.
        DECLARE @includeInactive BIT = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.reservationServices[0].includeInactive')), 0);
        DECLARE @listJson NVARCHAR(MAX) = (
            SELECT reservationServiceId, companyId, name, description, durationMinutes, capacity, machineType, isActive
            FROM [dbo].[reservationServices]
            WHERE companyId = @companyId
              AND (@action IN (1, 2, 3) AND reservationServiceId = @serviceId
                   OR ISNULL(@action, 0) = 0 AND (isActive = 1 OR @includeInactive = 1))
            ORDER BY name
            FOR JSON PATH
        );
        SELECT ('{"result":[{"reservationServices":' + ISNULL(@listJson, '[]') + '}]}') AS jsonResult;

    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
