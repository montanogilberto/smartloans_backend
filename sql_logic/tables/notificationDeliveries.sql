CREATE TABLE [dbo].[NotificationDeliveries](
	[notificationDeliveryId] [int] IDENTITY(1,1) NOT NULL PRIMARY KEY,
	[pushNotificationId] [int] NOT NULL,
	[userId] [int] NOT NULL,
	[isSent] [bit] NOT NULL,
	[isRead] [bit] NOT NULL,
	[sentAt] [datetime] NULL,
	[readAt] [datetime] NULL,
	[created_At] [datetime] NOT NULL,
	CONSTRAINT [FK_NotificationDeliveries_PushNotifications] FOREIGN KEY ([pushNotificationId]) REFERENCES [dbo].[PushNotifications] ([pushNotificationId])
) ON [PRIMARY]
-- No FK to dbo.users: the live users.userId column has no PRIMARY KEY/unique
-- constraint defined (confirmed via the "no primary or candidate keys" error
-- when this script was first run), so it can't be a FK target as-is. This
-- matches the existing convention elsewhere in this schema (e.g. logins.userId
-- also references users.userId without a declared FK).
GO
ALTER TABLE [dbo].[NotificationDeliveries] ADD CONSTRAINT [DF_NotificationDeliveries_isSent] DEFAULT (0) FOR [isSent]
GO
ALTER TABLE [dbo].[NotificationDeliveries] ADD CONSTRAINT [DF_NotificationDeliveries_isRead] DEFAULT (0) FOR [isRead]
GO
ALTER TABLE [dbo].[NotificationDeliveries] ADD CONSTRAINT [DF_NotificationDeliveries_created_At] DEFAULT (GETDATE()) FOR [created_At]
GO
CREATE INDEX IX_NotificationDeliveries_PushNotificationId ON [dbo].[NotificationDeliveries] ([pushNotificationId])
GO
CREATE INDEX IX_NotificationDeliveries_UserId ON [dbo].[NotificationDeliveries] ([userId])
GO
