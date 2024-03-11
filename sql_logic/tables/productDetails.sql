CREATE TABLE [dbo].[productDetails](
	[productDetailId] [int] IDENTITY(1,1) NOT NULL,
	[stockQuantity] [int] NOT NULL,
	[unitPrice] [decimal](10, 2) NOT NULL,
	[salePrice] [decimal](10, 2) NOT NULL,
PRIMARY KEY CLUSTERED
(
	[productDetailId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]