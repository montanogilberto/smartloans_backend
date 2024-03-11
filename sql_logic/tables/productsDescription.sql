CREATE TABLE [dbo].[productsDescription](
	[productDescriptionId] [int] IDENTITY(1,1) NOT NULL,
	[descripcion] [varchar](2000) NULL,
	[createdAt] [datetime] NULL,
	[updatedAt] [datetime] NULL,
 CONSTRAINT [PK_productsDescription_productDescriptionId] PRIMARY KEY CLUSTERED
(
	[productDescriptionId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[productsDescription] ADD  DEFAULT (getdate()) FOR [createdAt]