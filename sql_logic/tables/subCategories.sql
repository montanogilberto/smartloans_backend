CREATE TABLE [dbo].[subCategories](
	[subcategoryid] [int] IDENTITY(1,1) NOT NULL,
	[name] [varchar](100) NOT NULL,
	[categoryid] [int] NOT NULL,
 CONSTRAINT [PK_subcategories_categoryId] PRIMARY KEY CLUSTERED
(
	[subcategoryid] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]