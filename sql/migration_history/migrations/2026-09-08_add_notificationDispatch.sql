-- notificationDispatch: cost-minimizing Push -> WhatsApp -> SMS notification cascade.
-- See docs/notifications-income-expenses-tickets.md (frontend repo) for the full design.

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'notificationDispatch_status')
CREATE TABLE [dbo].[notificationDispatch_status] (
    statusCode  NVARCHAR(20) NOT NULL,
    description NVARCHAR(100) NOT NULL,
    created_At  DATETIME NOT NULL DEFAULT GETDATE(),
    updated_at  DATETIME NULL,
    CONSTRAINT PK_notificationDispatch_status PRIMARY KEY CLUSTERED (statusCode)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'notificationDispatch_policy')
CREATE TABLE [dbo].[notificationDispatch_policy] (
    eventName           NVARCHAR(40) NOT NULL,
    channel_list_json   NVARCHAR(MAX) NOT NULL,
    allow_sms_fallback  BIT NOT NULL DEFAULT 0,
    created_At          DATETIME NOT NULL DEFAULT GETDATE(),
    updated_at          DATETIME NULL,
    CONSTRAINT PK_notificationDispatch_policy PRIMARY KEY CLUSTERED (eventName)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'notificationDispatches')
CREATE TABLE [dbo].[notificationDispatches] (
    notificationDispatchId  INT IDENTITY(1,1) NOT NULL,
    companyId               INT NOT NULL,
    sourceType              NVARCHAR(20) NOT NULL,
    sourceId                INT NOT NULL,
    recipientType           NVARCHAR(10) NOT NULL,
    recipientId             INT NOT NULL,
    eventName               NVARCHAR(40) NOT NULL,
    preferredChannel        NVARCHAR(20) NOT NULL,
    selectedChannel         NVARCHAR(20) NOT NULL,
    attemptedChannels       NVARCHAR(MAX) NOT NULL,
    fallbackReason          NVARCHAR(30) NULL,
    status                  NVARCHAR(20) NOT NULL,
    providerMessageId       NVARCHAR(100) NULL,
    providerName            NVARCHAR(30) NULL,
    messagePreview          NVARCHAR(200) NULL,
    sentAt                  DATETIME NULL,
    confirmedAt             DATETIME NULL,
    failedAt                DATETIME NULL,
    created_At              DATETIME NOT NULL DEFAULT GETDATE(),
    updated_at              DATETIME NULL,
    CONSTRAINT PK_notificationDispatches PRIMARY KEY CLUSTERED (notificationDispatchId),
    CONSTRAINT FK_notificationDispatches_companies FOREIGN KEY (companyId) REFERENCES dbo.companies(companyId),
    CONSTRAINT FK_notificationDispatches_policy FOREIGN KEY (eventName) REFERENCES dbo.notificationDispatch_policy(eventName),
    CONSTRAINT FK_notificationDispatches_status FOREIGN KEY (status) REFERENCES dbo.notificationDispatch_status(statusCode)
);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_companyId' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_companyId ON dbo.notificationDispatches (companyId);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_status' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_status ON dbo.notificationDispatches (status);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_eventName' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_eventName ON dbo.notificationDispatches (eventName);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_sourceType_sourceId' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_sourceType_sourceId ON dbo.notificationDispatches (sourceType, sourceId);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_recipientType_recipientId' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_recipientType_recipientId ON dbo.notificationDispatches (recipientType, recipientId);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_providerMessageId' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_providerMessageId ON dbo.notificationDispatches (providerMessageId);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_sentAt' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_sentAt ON dbo.notificationDispatches (sentAt);
GO

-- Seed: status lookup (required by FK_notificationDispatches_status)
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_status WHERE statusCode = 'pending')
INSERT INTO dbo.notificationDispatch_status (statusCode, description) VALUES ('pending', 'Row created, no channel resolved yet');
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_status WHERE statusCode = 'sent')
INSERT INTO dbo.notificationDispatch_status (statusCode, description) VALUES ('sent', 'Dispatched successfully on selectedChannel');
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_status WHERE statusCode = 'confirmed')
INSERT INTO dbo.notificationDispatch_status (statusCode, description) VALUES ('confirmed', 'Provider delivery callback confirmed receipt');
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_status WHERE statusCode = 'failed')
INSERT INTO dbo.notificationDispatch_status (statusCode, description) VALUES ('failed', 'Every channel in the cascade was exhausted without success');
GO

-- Seed: starting cascade policy per event (required by FK_notificationDispatches_policy).
-- Adjust freely -- this table is meant to be edited without a code deploy.
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_policy WHERE eventName = 'income_created')
INSERT INTO dbo.notificationDispatch_policy (eventName, channel_list_json, allow_sms_fallback)
VALUES ('income_created', '["push","whatsapp","sms"]', 1);
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_policy WHERE eventName = 'ticket_ready')
INSERT INTO dbo.notificationDispatch_policy (eventName, channel_list_json, allow_sms_fallback)
VALUES ('ticket_ready', '["push","whatsapp","sms"]', 1);
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_policy WHERE eventName = 'expense_created')
INSERT INTO dbo.notificationDispatch_policy (eventName, channel_list_json, allow_sms_fallback)
VALUES ('expense_created', '["push","whatsapp"]', 0);
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
        failedAt                DATETIME NULL
    );

    INSERT INTO @payload (
        notificationDispatchId, companyId, sourceType, sourceId, recipientType, recipientId,
        eventName, preferredChannel, selectedChannel, attemptedChannels, fallbackReason, status,
        providerMessageId, providerName, messagePreview, sentAt, confirmedAt, failedAt
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
        TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.failedAt'))
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
                created_At, updated_at
            )
            SELECT
                p.companyId, p.sourceType, p.sourceId, p.recipientType, p.recipientId, p.eventName,
                p.preferredChannel, p.selectedChannel, p.attemptedChannels, p.fallbackReason, p.status,
                p.providerMessageId, p.providerName, p.messagePreview, p.sentAt, p.confirmedAt, p.failedAt,
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
        [created_At],
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM dbo.notificationDispatches
    WHERE notificationDispatchId = @notificationDispatchId
    FOR JSON AUTO, ROOT('notificationDispatches');
END
GO
