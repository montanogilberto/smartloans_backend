CREATE TABLE [dbo].[logins](
	[loginId] [int] IDENTITY(1,1) NOT NULL,
	[userId] [int] NULL,
	[active] [char](1) NULL
) ON [PRIMARY]