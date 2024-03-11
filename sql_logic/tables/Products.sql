CREATE TABLE [dbo].[Products](
	[productid] [int] IDENTITY(1,1) NOT NULL,
	[productName] [nvarchar](255) NOT NULL,
	[code] [varchar](100) NULL,
	[image] [image] NULL,
	[subCategoryId] [int] NOT NULL,
	[productDetailId] [int] NULL,
	[productDescriptionId] [int] NULL,
	[createdAt] [datetime] NULL,
	[updatedAt] [datetime] NULL,
 CONSTRAINT [PK_products_productId] PRIMARY KEY CLUSTERED
(
	[productid] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
ALTER TABLE [dbo].[Products] ADD  DEFAULT (getdate()) FOR [createdAt]