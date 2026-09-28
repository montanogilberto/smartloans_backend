-- WhatsApp Cloud API, multi-company: one WhatsApp number per branch.
-- Meta's webhook carries value.metadata.phone_number_id; whatsappChannels
-- maps it to the company/branch that owns the number, so one Meta app and
-- one webhook URL serve every company.
-- whatsappConversations holds the bot's per-chat state (pending booking,
-- staff pause, last booking) so it survives restarts and works with more
-- than one App Service instance/worker.
--
-- Run order: this file → sql/sp_whatsappChannels.sql →
-- sql/sp_whatsappConversations.sql  (POST /whatsapp/cloud/migrate runs all three)

IF OBJECT_ID(N'dbo.whatsappChannels', N'U') IS NULL
CREATE TABLE [dbo].[whatsappChannels] (
    channelId          INT IDENTITY(1,1) NOT NULL,
    phoneNumberId      NVARCHAR(32)  NOT NULL,   -- Meta "Phone number ID"
    wabaId             NVARCHAR(32)  NULL,       -- WhatsApp Business Account ID
    displayPhoneNumber NVARCHAR(20)  NULL,       -- +52 662 468 8224
    companyId          INT           NOT NULL,
    branchId           INT           NULL,       -- dbo.companiesBranch.branchId
    -- Name of the App Service setting holding this number's token. NULL =
    -- WA_ACCESS_TOKEN (system user of our own portfolio). Only numbers
    -- connected from another Meta portfolio need their own.
    accessTokenRef     NVARCHAR(64)  NULL,
    botEnabled         BIT           NOT NULL CONSTRAINT DF_whatsappChannels_botEnabled DEFAULT (1),
    isActive           BIT           NOT NULL CONSTRAINT DF_whatsappChannels_isActive DEFAULT (1),
    createdAt          DATETIME2     NOT NULL CONSTRAINT DF_whatsappChannels_createdAt DEFAULT (GETUTCDATE()),
    updatedAt          DATETIME2     NULL,
    CONSTRAINT PK_whatsappChannels PRIMARY KEY CLUSTERED (channelId),
    CONSTRAINT UQ_whatsappChannels_phoneNumberId UNIQUE (phoneNumberId)
);
GO

IF OBJECT_ID(N'dbo.whatsappConversations', N'U') IS NULL
CREATE TABLE [dbo].[whatsappConversations] (
    conversationId   INT IDENTITY(1,1) NOT NULL,
    channelId        INT            NOT NULL,
    customerPhone    NVARCHAR(20)   NOT NULL,   -- E.164, +52XXXXXXXXXX
    pendingJson      NVARCHAR(MAX)  NULL,       -- proposed CREATE_RESERVATION fields
    pendingExpiresAt DATETIME2      NULL,
    staffPausedUntil DATETIME2      NULL,
    lastBookedJson   NVARCHAR(MAX)  NULL,
    createdAt        DATETIME2      NOT NULL CONSTRAINT DF_whatsappConversations_createdAt DEFAULT (GETUTCDATE()),
    updatedAt        DATETIME2      NULL,
    CONSTRAINT PK_whatsappConversations PRIMARY KEY CLUSTERED (conversationId),
    CONSTRAINT UQ_whatsappConversations_chat UNIQUE (channelId, customerPhone),
    CONSTRAINT FK_whatsappConversations_channel FOREIGN KEY (channelId)
        REFERENCES [dbo].[whatsappChannels] (channelId)
);
GO
