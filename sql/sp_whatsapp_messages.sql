-- ─────────────────────────────────────────────────────────────────────────────
-- sp_whatsapp_messages — legacy log of every inbound/outbound WhatsApp text
-- (dbo.whatsappMessages). Until 2026-11-12 this SP existed only in the live DB;
-- this file is that definition, scripted, plus ONE change:
--
--   action 1 (insert) now returns the new messageId in result[0].value, so an
--   outbound send can link its Meta wamid to the log row
--   (dbo.whatsappMessageDeliveries.whatsappMessageId — tests/prd_whatsappMessageDelivery.json
--   in the factory). Callers that ignore "value" are unaffected.
--
-- Input envelope: { "messages": [{ "action": 1|2|3, "phoneNumber", "messageBody",
--                                  "responseBody", "direction", "status", "messageId" }] }
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROC [dbo].[sp_whatsapp_messages] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.messages'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for incoming/outgoing messages
            INSERT INTO [dbo].[whatsappMessages]
                ([phoneNumber], [messageBody], [responseBody], [direction], [status])
            SELECT
                JSON_VALUE(value, '$.phoneNumber'),
                JSON_VALUE(value, '$.messageBody'),
                JSON_VALUE(value, '$.responseBody'),
                JSON_VALUE(value, '$.direction'),
                JSON_VALUE(value, '$.status')
            FROM OPENJSON(@pjsonfile, '$.messages');

            -- New (2026-11-12): the id of the (last) inserted row. Callers log one message at a time.
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value',
                                             CONVERT(NVARCHAR(20), SCOPE_IDENTITY()));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Message Logged Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for a message's response or status
            UPDATE wm
            SET
                wm.[responseBody] = JSON_VALUE(j.value, '$.responseBody'),
                wm.[status] = JSON_VALUE(j.value, '$.status')
            FROM
                [dbo].[whatsappMessages] wm
            INNER JOIN
                OPENJSON(@pjsonfile, '$.messages') j
                ON wm.[messageId] = JSON_VALUE(j.value, '$.messageId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Message Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for messages
            DELETE FROM [dbo].[whatsappMessages]
            WHERE [messageId] IN (SELECT JSON_VALUE(value, '$.messageId') FROM OPENJSON(@pjsonfile, '$.messages'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Message Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO
