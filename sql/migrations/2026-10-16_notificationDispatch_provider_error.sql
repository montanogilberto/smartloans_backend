-- 2026-10-16 — notificationDispatches: save WHY a send failed.
-- Twilio's status callback (ErrorCode/ErrorMessage) and Meta's webhook
-- (errors[0].code/title) were only logged, so the dispatch log could not show
-- a reason. Adds providerErrorCode/providerErrorMessage, written for FUTURE
-- failures only (no backfill), and returns them from _all/_one.
-- Backend: modules/notificationDispatch.py (apply_provider_status + cascade).
-- Rollback: 2026-10-16_notificationDispatch_provider_error_ROLLBACK.sql

IF COL_LENGTH('dbo.notificationDispatches', 'providerErrorCode') IS NULL
    ALTER TABLE dbo.notificationDispatches ADD providerErrorCode NVARCHAR(20) NULL;
GO
IF COL_LENGTH('dbo.notificationDispatches', 'providerErrorMessage') IS NULL
    ALTER TABLE dbo.notificationDispatches ADD providerErrorMessage NVARCHAR(300) NULL;
GO

CREATE OR ALTER PROC [dbo].[sp_notificationDispatches] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @Outputmessage NVARCHAR(MAX) = '{
      "result": [
        { "value": "", "msg": "", "error": "" }
      ]
    }'

    DECLARE @action INT;
    SET @action = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.notificationDispatches')
    );

    DECLARE @payload TABLE (
        notificationDispatchId  INT NULL,
        companyId               INT NULL,
        sourceType              NVARCHAR(20) NULL,
        sourceId                INT NULL,
        recipientType           NVARCHAR(10) NULL,
        recipientId             INT NULL,
        eventName               NVARCHAR(40) NULL,
        preferredChannel        NVARCHAR(20) NULL,
        selectedChannel         NVARCHAR(20) NULL,
        attemptedChannels       NVARCHAR(MAX) NULL,
        fallbackReason          NVARCHAR(30) NULL,
        status                  NVARCHAR(20) NULL,
        providerMessageId       NVARCHAR(100) NULL,
        providerName            NVARCHAR(30) NULL,
        messagePreview          NVARCHAR(200) NULL,
        sentAt                  DATETIME NULL,
        confirmedAt             DATETIME NULL,
        failedAt                DATETIME NULL,
        providerErrorCode       NVARCHAR(20) NULL,
        providerErrorMessage    NVARCHAR(300) NULL
    );

    INSERT INTO @payload (
        notificationDispatchId, companyId, sourceType, sourceId, recipientType, recipientId,
        eventName, preferredChannel, selectedChannel, attemptedChannels, fallbackReason, status,
        providerMessageId, providerName, messagePreview, sentAt, confirmedAt, failedAt,
        providerErrorCode, providerErrorMessage
    )
    SELECT
        TRY_CONVERT(INT, JSON_VALUE(value, '$.notificationDispatchId')),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        JSON_VALUE(value, '$.sourceType'),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.sourceId')),
        JSON_VALUE(value, '$.recipientType'),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.recipientId')),
        JSON_VALUE(value, '$.eventName'),
        JSON_VALUE(value, '$.preferredChannel'),
        JSON_VALUE(value, '$.selectedChannel'),
        JSON_VALUE(value, '$.attemptedChannels'),
        JSON_VALUE(value, '$.fallbackReason'),
        JSON_VALUE(value, '$.status'),
        JSON_VALUE(value, '$.providerMessageId'),
        JSON_VALUE(value, '$.providerName'),
        JSON_VALUE(value, '$.messagePreview'),
        TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.sentAt')),
        TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.confirmedAt')),
        TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.failedAt')),
        LEFT(JSON_VALUE(value, '$.providerErrorCode'), 20),
        LEFT(JSON_VALUE(value, '$.providerErrorMessage'), 300)
    FROM OPENJSON(@pjsonfile, '$.notificationDispatches');

    BEGIN TRY
        BEGIN TRANSACTION

        IF @action = 1 -- INSERT
        BEGIN
            IF EXISTS (
                SELECT 1 FROM @payload
                GROUP BY companyId, sourceType, sourceId, eventName
                HAVING COUNT(*) > 1
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Duplicate records in payload for same companyId, sourceType, sourceId, eventName.');
                COMMIT TRANSACTION;
                GOTO Finish;
            END;

            IF EXISTS (
                SELECT 1
                FROM dbo.notificationDispatches nd
                INNER JOIN @payload p ON nd.companyId = p.companyId
                                     AND nd.sourceType = p.sourceType
                                     AND nd.sourceId = p.sourceId
                                     AND nd.eventName = p.eventName
                WHERE nd.status IN ('sent', 'confirmed')
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Dispatch already sent or confirmed for this event. No re-send.');
                COMMIT TRANSACTION;
                GOTO Finish;
            END;

            INSERT INTO dbo.notificationDispatches (
                companyId, sourceType, sourceId, recipientType, recipientId, eventName,
                preferredChannel, selectedChannel, attemptedChannels, fallbackReason, status,
                providerMessageId, providerName, messagePreview, sentAt, confirmedAt, failedAt,
                providerErrorCode, providerErrorMessage,
                created_At, updated_at
            )
            SELECT
                p.companyId, p.sourceType, p.sourceId, p.recipientType, p.recipientId, p.eventName,
                p.preferredChannel, p.selectedChannel, p.attemptedChannels, p.fallbackReason, p.status,
                p.providerMessageId, p.providerName, p.messagePreview, p.sentAt, p.confirmedAt, p.failedAt,
                p.providerErrorCode, p.providerErrorMessage,
                GETDATE(), NULL
            FROM @payload p;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2 -- UPDATE
        BEGIN
            UPDATE nd
            SET
                status = ISNULL(p.status, nd.status),
                confirmedAt = ISNULL(p.confirmedAt, nd.confirmedAt),
                failedAt = ISNULL(p.failedAt, nd.failedAt),
                providerErrorCode = ISNULL(p.providerErrorCode, nd.providerErrorCode),
                providerErrorMessage = ISNULL(p.providerErrorMessage, nd.providerErrorMessage),
                updated_at = GETDATE()
            FROM dbo.notificationDispatches nd
            INNER JOIN @payload p ON nd.notificationDispatchId = p.notificationDispatchId;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE nd
            FROM dbo.notificationDispatches nd
            INNER JOIN @payload p ON nd.notificationDispatchId = p.notificationDispatchId;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE());
    END CATCH

Finish:
    SELECT
        JSON_VALUE(value,'$.value') AS value,
        JSON_VALUE(value,'$.msg')   AS msg,
        JSON_VALUE(value,'$.error') AS error
    FROM OPENJSON(@Outputmessage,'$.result');
END
GO

CREATE OR ALTER PROC [dbo].[sp_notificationDispatches_all] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT;
    SET @companyId = TRY_CONVERT(INT,
        (SELECT TOP 1 JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.notificationDispatches'))
    );

    SELECT
        [notificationDispatchId],
        ISNULL([companyId], 0) AS companyId,
        ISNULL([sourceType], '') AS sourceType,
        ISNULL([sourceId], 0) AS sourceId,
        ISNULL([recipientType], '') AS recipientType,
        ISNULL([recipientId], 0) AS recipientId,
        ISNULL([eventName], '') AS eventName,
        ISNULL([preferredChannel], '') AS preferredChannel,
        ISNULL([selectedChannel], '') AS selectedChannel,
        ISNULL([attemptedChannels], '') AS attemptedChannels,
        ISNULL([fallbackReason], '') AS fallbackReason,
        ISNULL([status], '') AS status,
        ISNULL([providerMessageId], '') AS providerMessageId,
        ISNULL([providerName], '') AS providerName,
        ISNULL([messagePreview], '') AS messagePreview,
        ISNULL(CONVERT(VARCHAR(30), sentAt, 126), '') AS sentAt,
        ISNULL(CONVERT(VARCHAR(30), confirmedAt, 126), '') AS confirmedAt,
        ISNULL(CONVERT(VARCHAR(30), failedAt, 126), '') AS failedAt,
        ISNULL([providerErrorCode], '') AS providerErrorCode,
        ISNULL([providerErrorMessage], '') AS providerErrorMessage,
        [created_At],
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM dbo.notificationDispatches
    WHERE companyId = @companyId
    FOR JSON AUTO, ROOT('notificationDispatches');
END
GO

CREATE OR ALTER PROC [dbo].[sp_notificationDispatches_one] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @notificationDispatchId INT;
    SET @notificationDispatchId = CAST(
        (SELECT TOP 1 JSON_VALUE(value, '$.notificationDispatchId')
         FROM OPENJSON(@pjsonfile, '$.notificationDispatches')) AS INT
    );

    SELECT
        [notificationDispatchId],
        ISNULL([companyId], 0) AS companyId,
        ISNULL([sourceType], '') AS sourceType,
        ISNULL([sourceId], 0) AS sourceId,
        ISNULL([recipientType], '') AS recipientType,
        ISNULL([recipientId], 0) AS recipientId,
        ISNULL([eventName], '') AS eventName,
        ISNULL([preferredChannel], '') AS preferredChannel,
        ISNULL([selectedChannel], '') AS selectedChannel,
        ISNULL([attemptedChannels], '') AS attemptedChannels,
        ISNULL([fallbackReason], '') AS fallbackReason,
        ISNULL([status], '') AS status,
        ISNULL([providerMessageId], '') AS providerMessageId,
        ISNULL([providerName], '') AS providerName,
        ISNULL([messagePreview], '') AS messagePreview,
        ISNULL(CONVERT(VARCHAR(30), sentAt, 126), '') AS sentAt,
        ISNULL(CONVERT(VARCHAR(30), confirmedAt, 126), '') AS confirmedAt,
        ISNULL(CONVERT(VARCHAR(30), failedAt, 126), '') AS failedAt,
        ISNULL([providerErrorCode], '') AS providerErrorCode,
        ISNULL([providerErrorMessage], '') AS providerErrorMessage,
        [created_At],
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM dbo.notificationDispatches
    WHERE notificationDispatchId = @notificationDispatchId
    FOR JSON AUTO, ROOT('notificationDispatches');
END
GO
