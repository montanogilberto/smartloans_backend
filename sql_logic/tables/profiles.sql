CREATE TABLE [dbo].[profiles](
	[profileId] [int] IDENTITY(1,1) NOT NULL,
	[name] [varchar](50) NOT NULL,
	[userId] [int] NULL
) ON [PRIMARY]