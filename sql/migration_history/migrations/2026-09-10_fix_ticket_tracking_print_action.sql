-- sp_ticket_tracking never had a branch for @action = 'print' -- every call
-- from the receipt print flow fell through with no SELECT ever executing,
-- so pymssql's fetchone() raised "Statement not executed or executed
-- statement has no resultset" on every single print (500, tracking lost).
-- This adds a 'print' branch mirroring the existing 'whatsapp'/'sms' ones.

CREATE OR ALTER PROC [dbo].[sp_ticket_tracking]
(
    @pjsonfile NVARCHAR(MAX)
)
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE
        @action VARCHAR(50),
        @incomeId INT,
        @companyId INT,
        @fileName VARCHAR(500),
        @containerName VARCHAR(100),
        @receiptUrl VARCHAR(MAX),
        @phone VARCHAR(50);

    SELECT
        @action = JSON_VALUE(@pjsonfile,'$.ticket[0].action'),
        @incomeId = TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.ticket[0].incomeId')),
        @companyId = TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.ticket[0].companyId')),
        @fileName = JSON_VALUE(@pjsonfile,'$.ticket[0].fileName'),
        @containerName = JSON_VALUE(@pjsonfile,'$.ticket[0].containerName'),
        @receiptUrl = JSON_VALUE(@pjsonfile,'$.ticket[0].receiptUrl'),
        @phone = JSON_VALUE(@pjsonfile,'$.ticket[0].phone');

    ---------------------------------------------------------
    -- VALIDATE
    ---------------------------------------------------------
    IF @action = 'validate'
    BEGIN

        SELECT
            ticketId,
            incomeId,
            shortCode,
            fileName,
            receiptUrl,
            uploadAzure,
            whatsappSent,
            smsSent,
            printed,
            printedDate,
            generationStatus,
            generatedDate,
            errorMessage
        FROM dbo.tickets
        WHERE incomeId = @incomeId
        FOR JSON PATH, ROOT('tickets');

        RETURN;

    END

    ---------------------------------------------------------
    -- SAVE RECEIPT
    ---------------------------------------------------------
    IF @action = 'save'
    BEGIN

        IF EXISTS
        (
            SELECT 1
            FROM dbo.tickets
            WHERE incomeId = @incomeId
        )
        BEGIN

            UPDATE dbo.tickets
            SET
                companyId = @companyId,
                fileName = @fileName,
                containerName = @containerName,
                receiptUrl = @receiptUrl,
                uploadAzure = 1,
                uploadAzureDate = GETDATE(),
                updated_At = GETDATE()
            WHERE incomeId = @incomeId;

            -- Generate shortCode if missing
            UPDATE dbo.tickets
            SET shortCode = CONCAT('T', incomeId)
            WHERE incomeId = @incomeId
              AND shortCode IS NULL;

        END
        ELSE
        BEGIN

            INSERT INTO dbo.tickets
            (
                incomeId,
                companyId,
                fileName,
                containerName,
                receiptUrl,
                shortCode,
                uploadAzure,
                uploadAzureDate,
                created_At
            )
            VALUES
            (
                @incomeId,
                @companyId,
                @fileName,
                @containerName,
                @receiptUrl,
                CONCAT('T', @incomeId),
                1,
                GETDATE(),
                GETDATE()
            );

        END

        SELECT
            1 AS success,
            'Receipt saved' AS message
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- WHATSAPP SUCCESS
    ---------------------------------------------------------
    IF @action = 'whatsapp'
    BEGIN

        UPDATE dbo.tickets
        SET
            whatsappSent = 1,
            whatsappSentDate = GETDATE(),
            whatsappPhone = @phone,
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- SMS SUCCESS
    ---------------------------------------------------------
    IF @action = 'sms'
    BEGIN

        UPDATE dbo.tickets
        SET
            smsSent = 1,
            smsSentDate = GETDATE(),
            smsPhone = @phone,
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- PRINT SUCCESS (new -- this branch never existed before)
    ---------------------------------------------------------
    IF @action = 'print'
    BEGIN

        UPDATE dbo.tickets
        SET
            printed = 1,
            printedDate = GETDATE(),
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

END
GO
