/* Generado desde [montanogilberto_smartloans] el 2026-08-15 15:50:03
   por sql/migration/generate_migration.py — NO editar a mano. */
/* PASO 1 de 3 — 141 tablas, 44 foreign keys, 100 indices */
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* ---------- TABLAS ---------- */

-- dbo.activeIngredients
IF OBJECT_ID(N'dbo.activeIngredients', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[activeIngredients] (
    [activeIngredientId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(50) NOT NULL,
    [subCategoryId] int NOT NULL,
    [is_principal] varchar(10) NULL,
    CONSTRAINT [PK_activeIngredients_activeIngredientId] PRIMARY KEY CLUSTERED ([activeIngredientId])
);
END
GO

-- dbo.addresses
IF OBJECT_ID(N'dbo.addresses', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[addresses] (
    [addressId] int IDENTITY(1,1) NOT NULL,
    [street] varchar(500) NULL,
    [postalCode] varchar(10) NULL,
    [city] varchar(200) NULL,
    [state] varchar(200) NULL,
    [createdAt] datetime NULL CONSTRAINT [DF_addresses_datetime] DEFAULT (getdate()),
    [updatedAt] datetime NULL,
    CONSTRAINT [PK_addresses_addressId] PRIMARY KEY CLUSTERED ([addressId])
);
END
GO

-- dbo.applicationLogs
IF OBJECT_ID(N'dbo.applicationLogs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[applicationLogs] (
    [applicationLogId] bigint IDENTITY(1,1) NOT NULL,
    [correlationId] uniqueidentifier NULL,
    [workflowId] uniqueidentifier NULL,
    [companyId] int NULL,
    [level] varchar(20) NOT NULL,
    [source] varchar(150) NULL,
    [message] nvarchar(max) NULL,
    [exception] nvarchar(max) NULL,
    [apiEndpoint] varchar(200) NULL,
    [httpStatus] int NULL,
    [durationMs] int NULL,
    [ipAddress] varchar(50) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__applicati__creat__0A7378A9] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__applicat__0259544B0347EB45] PRIMARY KEY CLUSTERED ([applicationLogId])
);
END
GO

-- dbo.auditLogs
IF OBJECT_ID(N'dbo.auditLogs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[auditLogs] (
    [auditLogId] bigint IDENTITY(1,1) NOT NULL,
    [correlationId] uniqueidentifier NULL,
    [companyId] int NOT NULL,
    [actorUserId] int NULL,
    [actorClientId] int NULL,
    [entityName] varchar(100) NOT NULL,
    [entityId] int NULL,
    [fieldName] varchar(100) NULL,
    [oldValue] nvarchar(max) NULL,
    [newValue] nvarchar(max) NULL,
    [action] varchar(30) NULL,
    [ipAddress] varchar(50) NULL,
    [deviceInfo] varchar(200) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__auditLogs__creat__07970BFE] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__auditLog__56A1B8570D898C80] PRIMARY KEY CLUSTERED ([auditLogId])
);
END
GO

-- dbo.bankAccounts
IF OBJECT_ID(N'dbo.bankAccounts', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[bankAccounts] (
    [bankAccountId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [clientId] int NOT NULL,
    [clabe] nvarchar(18) NOT NULL,
    [bankCode] nvarchar(5) NULL,
    [bankName] nvarchar(100) NULL,
    [holderName] nvarchar(255) NOT NULL,
    [isVerified] bit NOT NULL CONSTRAINT [DF__bankAccou__isVer__28F7FFC9] DEFAULT ((0)),
    [verificationMethod] nvarchar(20) NULL,
    [verificationCents] int NULL,
    [verifiedAt] datetime2(7) NULL,
    [isDefault] bit NOT NULL CONSTRAINT [DF__bankAccou__isDef__29EC2402] DEFAULT ((0)),
    [isActive] bit NOT NULL CONSTRAINT [DF__bankAccou__isAct__2AE0483B] DEFAULT ((1)),
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__bankAccou__creat__2BD46C74] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    [clabeHash] nvarchar(64) NULL,
    [rfc] nvarchar(13) NULL,
    [accountStatus] nvarchar(22) NOT NULL CONSTRAINT [DF_bankAccounts_status] DEFAULT ('PRIMARY'),
    CONSTRAINT [PK__bankAcco__C9BC0F90F87EBF5C] PRIMARY KEY CLUSTERED ([bankAccountId])
);
END
GO

-- dbo.bankAccountSnapshots
IF OBJECT_ID(N'dbo.bankAccountSnapshots', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[bankAccountSnapshots] (
    [snapshotId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [loanId] int NOT NULL,
    [clientId] int NOT NULL,
    [partyRole] nvarchar(10) NOT NULL,
    [bankCode] nvarchar(5) NULL,
    [bankName] nvarchar(100) NOT NULL,
    [clabe] nvarchar(18) NOT NULL,
    [clabeLast4] nvarchar(4) NOT NULL,
    [holderName] nvarchar(255) NOT NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__bankAccou__creat__66010E09] DEFAULT (getutcdate()),
    CONSTRAINT [PK__bankAcco__BDCD2E0F481B9B5B] PRIMARY KEY CLUSTERED ([snapshotId]),
    CONSTRAINT [UQ_snapshot] UNIQUE NONCLUSTERED ([loanId], [partyRole]),
    CONSTRAINT [CK_snapshot_role] CHECK ([partyRole]='lender' OR [partyRole]='borrower')
);
END
GO

-- dbo.buyOffers
IF OBJECT_ID(N'dbo.buyOffers', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[buyOffers] (
    [buyOfferId] bigint IDENTITY(1,1) NOT NULL,
    [sourceType] varchar(10) NOT NULL,
    [sourceName] nvarchar(200) NOT NULL,
    [supplierSku] nvarchar(100) NULL,
    [titleRaw] nvarchar(500) NULL,
    [buyPriceOriginal] decimal(18,6) NOT NULL,
    [currencyOriginal] char(3) NOT NULL,
    [buyPriceUsd] decimal(18,6) NOT NULL,
    [fxRateToUsd] decimal(18,8) NOT NULL,
    [fxAsOfDate] date NOT NULL,
    [minQty] int NULL,
    [leadTimeDays] int NULL,
    [shippingBuyOriginal] decimal(18,6) NULL,
    [shippingBuyUsd] decimal(18,6) NULL,
    [taxBuyOriginal] decimal(18,6) NULL,
    [taxBuyUsd] decimal(18,6) NULL,
    [offerTimestamp] datetime2(7) NOT NULL,
    [unifiedProductId] bigint NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__buyOffers__creat__48BAC3E5] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NOT NULL CONSTRAINT [DF__buyOffers__updat__49AEE81E] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__buyOffer__DAAED0066A4527D1] PRIMARY KEY CLUSTERED ([buyOfferId]),
    CONSTRAINT [CK_buyOffers_sourceType] CHECK ([sourceType]='local' OR [sourceType]='online')
);
END
GO

-- dbo.cashRegisterMovements
IF OBJECT_ID(N'dbo.cashRegisterMovements', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[cashRegisterMovements] (
    [movementId] int IDENTITY(1,1) NOT NULL,
    [sessionId] int NOT NULL,
    [companyId] int NOT NULL,
    [userId] int NOT NULL,
    [movementType] varchar(20) NOT NULL,
    [amount] decimal(10,2) NOT NULL,
    [incomeId] int NULL,
    [notes] nvarchar(250) NULL,
    [createdAt] datetime NOT NULL CONSTRAINT [DF_cashRegisterMovements_createdAt] DEFAULT (getdate()),
    [cashPaid] decimal(10,2) NULL,
    [cashReturn] decimal(10,2) NULL,
    CONSTRAINT [PK__cashRegi__B9977ED8F95CACAE] PRIMARY KEY CLUSTERED ([movementId])
);
END
GO

-- dbo.cashRegisterSessions
IF OBJECT_ID(N'dbo.cashRegisterSessions', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[cashRegisterSessions] (
    [sessionId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [openedByUserId] int NOT NULL,
    [openedAt] datetime NOT NULL CONSTRAINT [DF_cashRegisterSessions_openedAt] DEFAULT (getdate()),
    [openingCash] decimal(10,2) NOT NULL CONSTRAINT [DF_cashRegisterSessions_openingCash] DEFAULT ((0)),
    [closedAt] datetime NULL,
    [closedByUserId] int NULL,
    [closingCash] decimal(10,2) NULL,
    [status] varchar(10) NOT NULL CONSTRAINT [DF_cashRegisterSessions_status] DEFAULT ('open'),
    [openingNotes] nvarchar(500) NULL,
    [closingNotes] nvarchar(500) NULL,
    [autoClosed] bit NOT NULL CONSTRAINT [DF__cashRegis__autoC__149C0161] DEFAULT ((0)),
    [expectedCash] decimal(10,2) NULL,
    [cashDifference] decimal(10,2) NULL,
    CONSTRAINT [PK__cashRegi__23DB122BFF1ECC94] PRIMARY KEY CLUSTERED ([sessionId])
);
END
GO

-- dbo.categories
IF OBJECT_ID(N'dbo.categories', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[categories] (
    [categoryid] int IDENTITY(1,1) NOT NULL,
    [name] varchar(100) NOT NULL,
    CONSTRAINT [PK_categories_categoryId] PRIMARY KEY CLUSTERED ([categoryid])
);
END
GO

-- dbo.check_types
IF OBJECT_ID(N'dbo.check_types', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[check_types] (
    [checkTypeId] int IDENTITY(1,1) NOT NULL,
    [description] varchar(50) NOT NULL,
    CONSTRAINT [PK_check_checkTypeId] PRIMARY KEY CLUSTERED ([description])
);
END
GO

-- dbo.checks
IF OBJECT_ID(N'dbo.checks', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[checks] (
    [checkId] int IDENTITY(1,1) NOT NULL,
    [latitude] varchar(500) NULL,
    [longitude] varchar(500) NULL,
    [description] varchar(500) NULL,
    [datetimelocal] datetime NOT NULL,
    [checkTypeId] int NOT NULL,
    [userId] int NOT NULL,
    [street] varchar(500) NULL,
    [postalCode] varchar(10) NULL,
    [city] varchar(200) NULL,
    [state] varchar(200) NULL,
    [createdAt] datetime NULL CONSTRAINT [DF_checks_createdAt] DEFAULT (getdate()),
    [updatedAt] datetime NULL,
    CONSTRAINT [PK_checks_checkId] PRIMARY KEY CLUSTERED ([checkId])
);
END
GO

-- dbo.clientDashboards
IF OBJECT_ID(N'dbo.clientDashboards', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[clientDashboards] (
    [clientDashboardId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [clientId] int NOT NULL,
    [availableCredit] decimal(18,2) NULL,
    [activeLoanBalance] decimal(18,2) NULL,
    [nextPaymentAmount] decimal(18,2) NULL,
    [nextPaymentDate] datetime2(7) NULL,
    [activityDate] datetime2(7) NULL,
    [activityType] nvarchar(50) NULL,
    [description] nvarchar(500) NULL,
    [amount] decimal(18,2) NULL,
    [loanNumber] nvarchar(50) NULL,
    [loanAmount] decimal(18,2) NULL,
    [remainingBalance] decimal(18,2) NULL,
    [status] nvarchar(30) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__clientDas__creat__7F36D027] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__clientDa__E7B3E16F07CC9101] PRIMARY KEY CLUSTERED ([clientDashboardId])
);
END
GO

-- dbo.ClientFaceRecognitions
IF OBJECT_ID(N'dbo.ClientFaceRecognitions', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ClientFaceRecognitions] (
    [clientFaceRecognitionId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [document_type] nvarchar(255) NOT NULL,
    [id_front_image_blob_url] nvarchar(2048) NOT NULL,
    [client_selfie_blob_url] nvarchar(2048) NOT NULL,
    [confidence_score] decimal(5,4) NOT NULL,
    [is_verified] bit NOT NULL,
    [contract_accepted] bit NOT NULL,
    [accepted_at] datetime NOT NULL,
    [created_At] datetime NOT NULL CONSTRAINT [DF_ClientFaceRecognitions_created_At] DEFAULT (sysutcdatetime()),
    [updated_at] datetime2(7) NULL,
    [clientId] int NOT NULL CONSTRAINT [DF__ClientFac__clien__50B0EB68] DEFAULT ((0)),
    [id_back_image_blob_url] nvarchar(2048) NULL,
    [azure_session_id] uniqueidentifier NULL,
    [contract_pdf_blob_url] nvarchar(2048) NULL,
    [contract_accepted_at] datetime2(7) NULL,
    [pagare_accepted] bit NOT NULL CONSTRAINT [DF__ClientFac__pagar__51A50FA1] DEFAULT ((0)),
    [pagare_pdf_blob_url] nvarchar(2048) NULL,
    [pagare_accepted_at] datetime2(7) NULL,
    [has_physical_pagare] bit NOT NULL CONSTRAINT [DF__ClientFac__has_p__529933DA] DEFAULT ((0)),
    [physical_pagare_verified_at] datetime2(7) NULL,
    [is_active] bit NOT NULL CONSTRAINT [DF__ClientFac__is_ac__538D5813] DEFAULT ((1)),
    [created_by] int NOT NULL CONSTRAINT [DF__ClientFac__creat__54817C4C] DEFAULT ((1)),
    [updated_by] int NULL,
    [presence_video_blob_url] nvarchar(2048) NULL,
    [presence_latitude] decimal(9,6) NULL,
    [presence_longitude] decimal(9,6) NULL,
    [presence_location_accuracy_meters] decimal(9,2) NULL,
    [presence_captured_at] datetime2(7) NULL,
    [id_signature_crop_blob_url] nvarchar(2048) NULL,
    [contract_signature_blob_url] nvarchar(2048) NULL,
    [signature_match_score] decimal(5,2) NULL,
    [signature_match_passed] bit NULL,
    [signature_matched_at] datetime2(7) NULL,
    [nombre] nvarchar(255) NULL,
    [domicilio] nvarchar(500) NULL,
    [curp] nvarchar(18) NULL,
    [clave_elector] nvarchar(20) NULL,
    [fecha_nacimiento] nvarchar(10) NULL,
    [rfc] nvarchar(13) NULL,
    CONSTRAINT [PK_ClientFaceRecognitions] PRIMARY KEY CLUSTERED ([clientFaceRecognitionId])
);
END
GO

-- dbo.clientFollowUps
IF OBJECT_ID(N'dbo.clientFollowUps', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[clientFollowUps] (
    [followUpId] int IDENTITY(1,1) NOT NULL,
    [clientId] int NOT NULL,
    [companyId] int NOT NULL,
    [riskStatus] nvarchar(20) NOT NULL CONSTRAINT [DF__clientFol__riskS__7D197D8B] DEFAULT ('on_track'),
    [reason] nvarchar(200) NULL,
    [note] nvarchar(500) NULL,
    [assignedTo] int NULL,
    [dueDate] datetime2(7) NULL,
    [resolvedAt] datetime2(7) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__clientFol__creat__7E0DA1C4] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__clientFo__CD9FFDECF58FEAD5] PRIMARY KEY CLUSTERED ([followUpId])
);
END
GO

-- dbo.clientFollowUps_status
IF OBJECT_ID(N'dbo.clientFollowUps_status', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[clientFollowUps_status] (
    [riskStatus] nvarchar(20) NOT NULL,
    [sortOrder] int NOT NULL,
    [description] nvarchar(100) NULL,
    [scorePenalty] int NOT NULL CONSTRAINT [DF__clientFol__score__7A3D10E0] DEFAULT ((0)),
    CONSTRAINT [PK__clientFo__54852DD78E92BFCF] PRIMARY KEY CLUSTERED ([riskStatus])
);
END
GO

-- dbo.clients
IF OBJECT_ID(N'dbo.clients', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[clients] (
    [clientId] int IDENTITY(1,1) NOT NULL,
    [first_name] nvarchar(100) NOT NULL,
    [last_name] varchar(100) NULL,
    [cellphone] nvarchar(20) NOT NULL,
    [email] nvarchar(100) NULL,
    [created_At] datetime NULL CONSTRAINT [DF__clients__created__01342732] DEFAULT (getdate()),
    [updated_at] datetime NULL CONSTRAINT [DF__clients__updated__02284B6B] DEFAULT (getdate()),
    [companyId] int NULL,
    [phone] varchar(10) NULL,
    [qrBlobUrl] nvarchar(500) NULL,
    [clientType] nvarchar(20) NOT NULL CONSTRAINT [DF_clients_clientType] DEFAULT ('borrower'),
    CONSTRAINT [PK__clients__81A2CBE1C519AEA4] PRIMARY KEY CLUSTERED ([clientId]),
    CONSTRAINT [UQ_clients_cellphone] UNIQUE NONCLUSTERED ([cellphone]),
    CONSTRAINT [CK_clients_clientType] CHECK ([clientType]='lawyer' OR [clientType]='both' OR [clientType]='lender' OR [clientType]='borrower')
);
END
GO

-- dbo.clientWallets
IF OBJECT_ID(N'dbo.clientWallets', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[clientWallets] (
    [walletId] int IDENTITY(1,1) NOT NULL,
    [clientId] int NOT NULL,
    [companyId] int NOT NULL,
    [availableBalance] decimal(18,2) NOT NULL CONSTRAINT [DF__clientWal__avail__024846FC] DEFAULT ((0)),
    [reservedBalance] decimal(18,2) NOT NULL CONSTRAINT [DF__clientWal__reser__033C6B35] DEFAULT ((0)),
    [totalTopUps] decimal(18,2) NOT NULL CONSTRAINT [DF__clientWal__total__04308F6E] DEFAULT ((0)),
    [totalDisbursed] decimal(18,2) NOT NULL CONSTRAINT [DF__clientWal__total__0524B3A7] DEFAULT ((0)),
    [totalRepaid] decimal(18,2) NOT NULL CONSTRAINT [DF__clientWal__total__0618D7E0] DEFAULT ((0)),
    [updatedAt] datetime2(7) NULL,
    CONSTRAINT [PK__clientWa__3785C870EC217129] PRIMARY KEY CLUSTERED ([walletId]),
    CONSTRAINT [UQ_clientWallets] UNIQUE NONCLUSTERED ([clientId], [companyId])
);
END
GO

-- dbo.clothesCatalog
IF OBJECT_ID(N'dbo.clothesCatalog', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[clothesCatalog] (
    [catalogId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [name] nvarchar(100) NOT NULL,
    [group] varchar(20) NOT NULL,
    [description] nvarchar(250) NULL,
    [sortOrder] int NOT NULL CONSTRAINT [DF_clothesCatalog_sortOrder] DEFAULT ((0)),
    [isActive] bit NOT NULL CONSTRAINT [DF_clothesCatalog_isActive] DEFAULT ((1)),
    [createdAt] datetime NOT NULL CONSTRAINT [DF_clothesCatalog_createdAt] DEFAULT (getdate()),
    [updatedAt] datetime NULL,
    CONSTRAINT [PK__clothesC__D93DC3C60F08026D] PRIMARY KEY CLUSTERED ([catalogId])
);
END
GO

-- dbo.Commands
IF OBJECT_ID(N'dbo.Commands', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Commands] (
    [commandId] int IDENTITY(1,1) NOT NULL,
    [phrase] nvarchar(255) NULL,
    [action] nvarchar(100) NULL,
    CONSTRAINT [PK__Commands__4E1233059D96B8E0] PRIMARY KEY CLUSTERED ([commandId])
);
END
GO

-- dbo.commission_terminals
IF OBJECT_ID(N'dbo.commission_terminals', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[commission_terminals] (
    [commissionTerminalId] int IDENTITY(1,1) NOT NULL,
    [provider] varchar(40) NOT NULL,
    [terminalName] varchar(80) NOT NULL,
    [paymentMethod] varchar(20) NULL,
    [country] char(2) NULL,
    [commissionRatePct] decimal(6,3) NOT NULL,
    [fixedFeeAmount] decimal(10,2) NULL,
    [currency] char(3) NULL,
    [isActive] bit NOT NULL CONSTRAINT [DF_commission_terminals_isActive] DEFAULT ((1)),
    [validFrom] datetime NOT NULL CONSTRAINT [DF_commission_terminals_validFrom] DEFAULT (getdate()),
    [validTo] datetime NULL,
    [createdAt] datetime NOT NULL CONSTRAINT [DF_commission_terminals_createdAt] DEFAULT (getdate()),
    [updatedAt] datetime NULL,
    CONSTRAINT [PK__commissi__CC2F73BD0ABA2608] PRIMARY KEY CLUSTERED ([commissionTerminalId])
);
END
GO

-- dbo.companies
IF OBJECT_ID(N'dbo.companies', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[companies] (
    [companyId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(100) NOT NULL,
    [createdAt] datetime NULL CONSTRAINT [DF__companies__creat__1AD3FDA4] DEFAULT (getdate()),
    [updatedAt] datetime NULL,
    CONSTRAINT [PK_companies_companyId] PRIMARY KEY CLUSTERED ([companyId])
);
END
GO

-- dbo.companiesBranch
IF OBJECT_ID(N'dbo.companiesBranch', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[companiesBranch] (
    [branchId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(100) NOT NULL,
    [active] varchar(1) NULL CONSTRAINT [DF__companies__activ__1DB06A4F] DEFAULT ('1'),
    [createdAt] datetime NULL CONSTRAINT [DF__companies__creat__1EA48E88] DEFAULT (getdate()),
    [updatedAt] datetime NULL,
    [companyId] int NOT NULL,
    CONSTRAINT [PK_companiesBranch_branchId] PRIMARY KEY CLUSTERED ([branchId])
);
END
GO

-- dbo.company_modules
IF OBJECT_ID(N'dbo.company_modules', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[company_modules] (
    [companyId] int NOT NULL,
    [moduleId] int NOT NULL,
    [active] bit NOT NULL CONSTRAINT [DF__company_m__activ__1960B67E] DEFAULT ((1)),
    CONSTRAINT [PK__company___C5BA91712B0A0518] PRIMARY KEY CLUSTERED ([companyId], [moduleId])
);
END
GO

-- dbo.contractors
IF OBJECT_ID(N'dbo.contractors', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[contractors] (
    [contractorId] int IDENTITY(1,1) NOT NULL,
    [employeeId] int NOT NULL,
    [contractingCompany] nvarchar(100) NULL,
    [contractStartDate] date NULL,
    [contractEndDate] date NULL,
    [createdAt] datetime NULL CONSTRAINT [DF_contractors_createdAt] DEFAULT (getdate()),
    CONSTRAINT [PK_contractors_contractorId] PRIMARY KEY CLUSTERED ([contractorId])
);
END
GO

-- dbo.costRules
IF OBJECT_ID(N'dbo.costRules', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[costRules] (
    [ruleId] int IDENTITY(1,1) NOT NULL,
    [channel] varchar(20) NOT NULL,
    [category] nvarchar(200) NULL,
    [feePercent] decimal(9,6) NOT NULL CONSTRAINT [DF__costRules__feePe__5AD97420] DEFAULT ((0)),
    [fixedFeeUsd] decimal(18,6) NOT NULL CONSTRAINT [DF__costRules__fixed__5BCD9859] DEFAULT ((0)),
    [adsPercent] decimal(9,6) NOT NULL CONSTRAINT [DF__costRules__adsPe__5CC1BC92] DEFAULT ((0)),
    [returnsRate] decimal(9,6) NOT NULL CONSTRAINT [DF__costRules__retur__5DB5E0CB] DEFAULT ((0)),
    [avgReturnCostUsd] decimal(18,6) NOT NULL CONSTRAINT [DF__costRules__avgRe__5EAA0504] DEFAULT ((0)),
    [packagingCostUsd] decimal(18,6) NOT NULL CONSTRAINT [DF__costRules__packa__5F9E293D] DEFAULT ((0)),
    [otherCostUsd] decimal(18,6) NOT NULL CONSTRAINT [DF__costRules__other__60924D76] DEFAULT ((0)),
    [effectiveFrom] date NOT NULL,
    [effectiveTo] date NULL,
    [market] char(2) NOT NULL CONSTRAINT [DF_costRules_market] DEFAULT ('US'),
    CONSTRAINT [PK__costRule__121C066159E24FBE] PRIMARY KEY CLUSTERED ([ruleId]),
    CONSTRAINT [CK_costRules_market] CHECK ([market]='MX' OR [market]='US')
);
END
GO

-- dbo.creditScoreHistory
IF OBJECT_ID(N'dbo.creditScoreHistory', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[creditScoreHistory] (
    [historyId] int IDENTITY(1,1) NOT NULL,
    [clientId] int NOT NULL,
    [companyId] int NOT NULL,
    [score] int NOT NULL,
    [label] nvarchar(20) NOT NULL,
    [computedAt] datetime2(7) NOT NULL CONSTRAINT [DF__creditSco__compu__7C8F6DA6] DEFAULT (getutcdate()),
    CONSTRAINT [PK__creditSc__19BDBDD3859072FA] PRIMARY KEY CLUSTERED ([historyId])
);
END
GO

-- dbo.creditScores
IF OBJECT_ID(N'dbo.creditScores', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[creditScores] (
    [scoreId] int IDENTITY(1,1) NOT NULL,
    [clientId] int NOT NULL,
    [companyId] int NOT NULL,
    [score] int NOT NULL,
    [label] nvarchar(20) NOT NULL,
    [breakdown] nvarchar(max) NULL,
    [computedAt] datetime2(7) NOT NULL CONSTRAINT [DF__creditSco__compu__79B300FB] DEFAULT (getutcdate()),
    CONSTRAINT [PK__creditSc__B56A0C8DA4FC6F47] PRIMARY KEY CLUSTERED ([scoreId]),
    CONSTRAINT [UQ_creditScores_client] UNIQUE NONCLUSTERED ([clientId], [companyId])
);
END
GO

-- dbo.departments
IF OBJECT_ID(N'dbo.departments', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[departments] (
    [departmentId] int IDENTITY(1,1) NOT NULL,
    [departmentName] nvarchar(100) NOT NULL,
    [createdAt] datetime NULL CONSTRAINT [DF_departments_createdAt] DEFAULT (getdate()),
    CONSTRAINT [PK_departments_departmentId] PRIMARY KEY CLUSTERED ([departmentId])
);
END
GO

-- dbo.employeeProjectAssignments
IF OBJECT_ID(N'dbo.employeeProjectAssignments', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[employeeProjectAssignments] (
    [assignmentId] int IDENTITY(1,1) NOT NULL,
    [employeeId] int NOT NULL,
    [projectId] int NOT NULL,
    [assignmentStartDate] date NULL,
    [assignmentEndDate] date NULL,
    [createdAt] datetime NULL CONSTRAINT [DF_employeeProjectAssignments_createdAt] DEFAULT (getdate()),
    CONSTRAINT [PK_employeeProjectAssignments_assignmentId] PRIMARY KEY CLUSTERED ([assignmentId])
);
END
GO

-- dbo.employees
IF OBJECT_ID(N'dbo.employees', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[employees] (
    [employeeId] int IDENTITY(1,1) NOT NULL,
    [firstName] nvarchar(50) NOT NULL,
    [lastName] nvarchar(50) NOT NULL,
    [email] nvarchar(100) NOT NULL,
    [phoneNumber] nvarchar(20) NULL,
    [address] nvarchar(255) NULL,
    [employmentTypeId] int NOT NULL,
    [position] nvarchar(100) NULL,
    [departmentId] int NOT NULL,
    [statusId] int NOT NULL,
    [hireDate] date NULL,
    [endDate] date NULL,
    [emergencyContactName] nvarchar(100) NULL,
    [emergencyContactRelationship] nvarchar(50) NULL,
    [emergencyContactPhone] nvarchar(20) NULL,
    [notes] nvarchar(max) NULL,
    [createdAt] datetime NULL CONSTRAINT [DF_employees_createdAt] DEFAULT (getdate()),
    CONSTRAINT [PK_employees_employeeId] PRIMARY KEY CLUSTERED ([employeeId]),
    CONSTRAINT [UQ__employee__AB6E6164EF9F5DA3] UNIQUE NONCLUSTERED ([email])
);
END
GO

-- dbo.employmentTypes
IF OBJECT_ID(N'dbo.employmentTypes', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[employmentTypes] (
    [employmentTypeId] int IDENTITY(1,1) NOT NULL,
    [employmentType] nvarchar(20) NOT NULL,
    [createdAt] datetime NULL CONSTRAINT [DF_employmentTypes_createdAt] DEFAULT (getdate()),
    CONSTRAINT [PK_employmentTypes_employmentTypeId] PRIMARY KEY CLUSTERED ([employmentTypeId])
);
END
GO

-- dbo.exchangeRates
IF OBJECT_ID(N'dbo.exchangeRates', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[exchangeRates] (
    [exchangeRateId] int IDENTITY(1,1) NOT NULL,
    [fromCurrency] char(3) NOT NULL,
    [toCurrency] char(3) NOT NULL CONSTRAINT [DF__exchangeR__toCur__4119A21D] DEFAULT ('USD'),
    [rate] decimal(18,8) NOT NULL,
    [asOfDate] date NOT NULL,
    [source] nvarchar(100) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__exchangeR__creat__420DC656] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__exchange__DE88B8412F3CB874] PRIMARY KEY CLUSTERED ([exchangeRateId]),
    CONSTRAINT [UQ_exchangeRates] UNIQUE NONCLUSTERED ([fromCurrency], [toCurrency], [asOfDate])
);
END
GO

-- dbo.expenseDetailOptions
IF OBJECT_ID(N'dbo.expenseDetailOptions', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[expenseDetailOptions] (
    [expenseDetailOptionId] int IDENTITY(1,1) NOT NULL,
    [expenseDetailId] int NOT NULL,
    [productOptionId] int NOT NULL,
    [productOptionChoiceId] int NOT NULL,
    [created_At] datetime NULL CONSTRAINT [DF__expenseDe__creat__35A7EF71] DEFAULT (getdate()),
    [updated_At] datetime NULL CONSTRAINT [DF__expenseDe__updat__369C13AA] DEFAULT (getdate()),
    CONSTRAINT [PK__expenseD__19DB061C21568E06] PRIMARY KEY CLUSTERED ([expenseDetailOptionId])
);
END
GO

-- dbo.expenseDetails
IF OBJECT_ID(N'dbo.expenseDetails', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[expenseDetails] (
    [expenseDetailId] int IDENTITY(1,1) NOT NULL,
    [expenseId] int NOT NULL,
    [productId] int NOT NULL,
    [created_At] datetime NULL CONSTRAINT [DF__expenseDe__creat__30E33A54] DEFAULT (getdate()),
    [updated_At] datetime NULL CONSTRAINT [DF__expenseDe__updat__31D75E8D] DEFAULT (getdate()),
    CONSTRAINT [PK__expenseD__6A1CE74AC0A422C9] PRIMARY KEY CLUSTERED ([expenseDetailId])
);
END
GO

-- dbo.expenses
IF OBJECT_ID(N'dbo.expenses', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[expenses] (
    [expenseId] int IDENTITY(1,1) NOT NULL,
    [orderId] int NULL,
    [total] decimal(10,2) NOT NULL,
    [paymentMethod] varchar(20) NOT NULL,
    [paymentDate] datetime NULL CONSTRAINT [DF__expenses__paymen__2E06CDA9] DEFAULT (getdate()),
    [userId] int NOT NULL,
    [supplierId] int NOT NULL,
    [companyId] int NOT NULL,
    CONSTRAINT [PK__expenses__3672732EF73B1DBD] PRIMARY KEY CLUSTERED ([expenseId])
);
END
GO

-- dbo.images
IF OBJECT_ID(N'dbo.images', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[images] (
    [imageId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(100) NOT NULL,
    [location] varchar(100) NOT NULL,
    [url] varchar(100) NOT NULL,
    [id] int NOT NULL,
    [moduleId] varchar(100) NOT NULL,
    [createdAt] datetime NULL CONSTRAINT [DF__images__createdA__0D7A0286] DEFAULT (getdate()),
    [updatedAt] datetime NULL,
    CONSTRAINT [PK_images_imageId] PRIMARY KEY CLUSTERED ([imageId])
);
END
GO

-- dbo.income
IF OBJECT_ID(N'dbo.income', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[income] (
    [incomeId] int IDENTITY(1,1) NOT NULL,
    [orderId] int NULL,
    [total] decimal(10,2) NOT NULL,
    [paymentMethod] varchar(20) NOT NULL,
    [paymentDate] datetime NULL CONSTRAINT [DF__income__paymentD__72E607DB] DEFAULT (getdate()),
    [userId] int NOT NULL,
    [clientId] int NOT NULL,
    [companyId] int NOT NULL,
    [cashPaid] decimal(10,2) NULL,
    [cashReturn] decimal(10,2) NULL,
    [promotionId] int NULL,
    [promotionCode] varchar(30) NULL,
    [discountAmount] decimal(10,2) NULL,
    [commissionTerminalId] int NULL,
    CONSTRAINT [PK__income__5FC78A6357FCAEA2] PRIMARY KEY CLUSTERED ([incomeId])
);
END
GO

-- dbo.incomeDetailOptions
IF OBJECT_ID(N'dbo.incomeDetailOptions', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[incomeDetailOptions] (
    [incomeDetailOptionId] int IDENTITY(1,1) NOT NULL,
    [incomeDetailId] int NOT NULL,
    [productOptionId] int NOT NULL,
    [productOptionChoiceId] int NOT NULL,
    [created_At] datetime NULL CONSTRAINT [DF__incomeDet__creat__75C27486] DEFAULT (getdate()),
    [updated_At] datetime NULL CONSTRAINT [DF__incomeDet__updat__76B698BF] DEFAULT (getdate()),
    [quantity] int NOT NULL CONSTRAINT [DF_incomeDetailOptions_quantity] DEFAULT ((1)),
    CONSTRAINT [PK__incomeDe__3286EA1E83C2FE6B] PRIMARY KEY CLUSTERED ([incomeDetailOptionId])
);
END
GO

-- dbo.incomeDetails
IF OBJECT_ID(N'dbo.incomeDetails', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[incomeDetails] (
    [incomeDetailId] int IDENTITY(1,1) NOT NULL,
    [incomeId] int NOT NULL,
    [productId] int NOT NULL,
    [created_At] datetime NULL CONSTRAINT [DF__incomeDet__creat__7A8729A3] DEFAULT (getdate()),
    [updated_At] datetime NULL CONSTRAINT [DF__incomeDet__updat__7B7B4DDC] DEFAULT (getdate()),
    [quantity] int NOT NULL CONSTRAINT [DF_incomeDetails_quantity] DEFAULT ((1)),
    [piecesJson] nvarchar(max) NULL,
    CONSTRAINT [PK__incomeDe__A2E92981A69E12ED] PRIMARY KEY CLUSTERED ([incomeDetailId]),
    CONSTRAINT [CK_incomeDetails_piecesJson_isJson] CHECK ([piecesJson] IS NULL OR isjson([piecesJson])=(1))
);
END
GO

-- dbo.ingestState
IF OBJECT_ID(N'dbo.ingestState', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ingestState] (
    [ingestStateId] bigint IDENTITY(1,1) NOT NULL,
    [targetKey] nvarchar(400) NOT NULL,
    [source] varchar(30) NOT NULL,
    [market] char(2) NOT NULL,
    [channel] varchar(20) NULL,
    [status] varchar(20) NOT NULL CONSTRAINT [DF__ingestSta__statu__5B988E2F] DEFAULT ('idle'),
    [lastOffset] int NULL,
    [nextOffset] int NULL,
    [pageSize] int NOT NULL CONSTRAINT [DF__ingestSta__pageS__5C8CB268] DEFAULT ((50)),
    [lastRunAt] datetime2(7) NULL,
    [nextRunAt] datetime2(7) NULL,
    [attempts] int NOT NULL CONSTRAINT [DF__ingestSta__attem__5D80D6A1] DEFAULT ((0)),
    [lastError] nvarchar(500) NULL,
    [lockedBy] nvarchar(100) NULL,
    [lockUntil] datetime2(7) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__ingestSta__creat__5E74FADA] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NOT NULL CONSTRAINT [DF__ingestSta__updat__5F691F13] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__ingestSt__0F8730FA208D5223] PRIMARY KEY CLUSTERED ([ingestStateId]),
    CONSTRAINT [UQ_ingestState] UNIQUE NONCLUSTERED ([targetKey]),
    CONSTRAINT [CK_ingestState_market] CHECK ([market]='MX' OR [market]='US'),
    CONSTRAINT [CK_ingestState_status] CHECK ([status]='failed' OR [status]='paused' OR [status]='running' OR [status]='idle')
);
END
GO

-- dbo.integrationLogs
IF OBJECT_ID(N'dbo.integrationLogs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[integrationLogs] (
    [integrationLogId] bigint IDENTITY(1,1) NOT NULL,
    [correlationId] uniqueidentifier NULL,
    [workflowId] uniqueidentifier NULL,
    [companyId] int NULL,
    [service] varchar(50) NOT NULL,
    [operation] varchar(100) NULL,
    [status] varchar(30) NULL,
    [httpStatus] int NULL,
    [latencyMs] int NULL,
    [requestSummary] nvarchar(max) NULL,
    [responseSummary] nvarchar(max) NULL,
    [exception] nvarchar(max) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__integrati__creat__0D4FE554] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__integrat__0833D12FA09AAD4F] PRIMARY KEY CLUSTERED ([integrationLogId])
);
END
GO

-- dbo.inventoryMovements
IF OBJECT_ID(N'dbo.inventoryMovements', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[inventoryMovements] (
    [movementId] bigint IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [productId] int NOT NULL,
    [quantityDelta] decimal(18,3) NOT NULL,
    [reason] varchar(30) NOT NULL,
    [notes] nvarchar(300) NULL,
    [refType] varchar(30) NULL,
    [refId] int NULL,
    [userId] int NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__inventory__creat__62108194] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__inventor__B9977ED8C7D659B9] PRIMARY KEY CLUSTERED ([movementId])
);
END
GO

-- dbo.inventoryStock
IF OBJECT_ID(N'dbo.inventoryStock', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[inventoryStock] (
    [inventoryStockId] bigint IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [productId] int NOT NULL,
    [stockQuantity] decimal(18,3) NOT NULL CONSTRAINT [DF__inventory__stock__5E3FF0B0] DEFAULT ((0)),
    [minStockQty] decimal(18,3) NULL,
    [reorderQty] decimal(18,3) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__inventory__creat__5F3414E9] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NULL,
    CONSTRAINT [PK__inventor__016BDE2C6363A4B4] PRIMARY KEY CLUSTERED ([inventoryStockId]),
    CONSTRAINT [UQ_inventoryStock] UNIQUE NONCLUSTERED ([companyId], [productId])
);
END
GO

-- dbo.LedStatus
IF OBJECT_ID(N'dbo.LedStatus', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[LedStatus] (
    [deviceId] nvarchar(64) NOT NULL,
    [status] nvarchar(10) NOT NULL,
    [updated_at] datetime2(0) NOT NULL CONSTRAINT [DF_LedStatus_updated_at] DEFAULT (sysutcdatetime()),
    [updated_by] nvarchar(50) NULL,
    CONSTRAINT [PK_LedStatus] PRIMARY KEY CLUSTERED ([deviceId]),
    CONSTRAINT [CK_LedStatus_Status] CHECK ([status]=N'off' OR [status]=N'on')
);
END
GO

-- dbo.legalCaseNotes
IF OBJECT_ID(N'dbo.legalCaseNotes', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[legalCaseNotes] (
    [noteId] int IDENTITY(1,1) NOT NULL,
    [caseId] int NOT NULL,
    [authorClientId] int NOT NULL,
    [authorRole] nvarchar(20) NOT NULL,
    [noteText] nvarchar(max) NOT NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__legalCase__creat__1249A49B] DEFAULT (getutcdate()),
    CONSTRAINT [PK__legalCas__03C97EFDB7D0703B] PRIMARY KEY CLUSTERED ([noteId])
);
END
GO

-- dbo.legalCases
IF OBJECT_ID(N'dbo.legalCases', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[legalCases] (
    [caseId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [loanId] int NOT NULL,
    [borrowerClientId] int NOT NULL,
    [lenderClientId] int NOT NULL,
    [lenderUserId] int NULL,
    [lawyerClientId] int NULL,
    [lawyerUserId] int NULL,
    [lawyerName] nvarchar(200) NULL,
    [caseStatus] nvarchar(30) NOT NULL CONSTRAINT [DF__legalCase__caseS__0E7913B7] DEFAULT ('open'),
    [caseStage] nvarchar(50) NULL,
    [overdueAmount] decimal(14,2) NULL,
    [recoveredAmount] decimal(14,2) NULL,
    [embargoExecutedAt] datetime2(7) NULL,
    [closedAt] datetime2(7) NULL,
    [statusNote] nvarchar(max) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__legalCase__creat__0F6D37F0] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__legalCas__956FA6C9CB41F499] PRIMARY KEY CLUSTERED ([caseId])
);
END
GO

-- dbo.listingDrafts
IF OBJECT_ID(N'dbo.listingDrafts', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[listingDrafts] (
    [draftId] bigint IDENTITY(1,1) NOT NULL,
    [unifiedProductId] bigint NOT NULL,
    [channel] varchar(20) NOT NULL,
    [market] char(2) NOT NULL,
    [payloadJson] nvarchar(max) NOT NULL,
    [suggestedPriceUsd] decimal(18,6) NULL,
    [minPriceUsd] decimal(18,6) NULL,
    [maxPriceUsd] decimal(18,6) NULL,
    [status] varchar(20) NOT NULL CONSTRAINT [DF__listingDr__statu__73A521EA] DEFAULT ('draft'),
    [approvedBy] nvarchar(100) NULL,
    [approvedAt] datetime2(7) NULL,
    [errorMessage] nvarchar(2000) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__listingDr__creat__74994623] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NOT NULL CONSTRAINT [DF__listingDr__updat__758D6A5C] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__listingD__D549F8D703424E40] PRIMARY KEY CLUSTERED ([draftId]),
    CONSTRAINT [CK_listingDrafts_channel] CHECK ([channel]='mercadolibre' OR [channel]='amazon'),
    CONSTRAINT [CK_listingDrafts_market] CHECK ([market]='MX' OR [market]='US'),
    CONSTRAINT [CK_listingDrafts_status] CHECK ([status]='failed' OR [status]='published' OR [status]='approved' OR [status]='draft')
);
END
GO

-- dbo.loanContracts
IF OBJECT_ID(N'dbo.loanContracts', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[loanContracts] (
    [contractId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [loanId] int NOT NULL,
    [conversationId] int NULL,
    [borrowerClientId] int NOT NULL,
    [lenderClientId] int NOT NULL,
    [borrowerUserId] int NULL,
    [lenderUserId] int NULL,
    [contractType] nvarchar(20) NOT NULL CONSTRAINT [DF__loanContr__contr__03FB8544] DEFAULT ('contract'),
    [principalAmount] decimal(14,2) NOT NULL,
    [interestRate] decimal(6,4) NOT NULL,
    [termMonths] int NOT NULL,
    [paymentFrequency] nvarchar(20) NOT NULL CONSTRAINT [DF__loanContr__payme__04EFA97D] DEFAULT ('monthly'),
    [startDate] datetime2(7) NULL,
    [endDate] datetime2(7) NULL,
    [contractStatus] nvarchar(20) NOT NULL CONSTRAINT [DF__loanContr__contr__05E3CDB6] DEFAULT ('pending'),
    [pdfBlobUrl] nvarchar(500) NULL,
    [contractHtml] nvarchar(max) NULL,
    [notes] nvarchar(max) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__loanContr__creat__06D7F1EF] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__loanCont__138209419796E1E6] PRIMARY KEY CLUSTERED ([contractId])
);
END
GO

-- dbo.loanContractSignatures
IF OBJECT_ID(N'dbo.loanContractSignatures', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[loanContractSignatures] (
    [signatureId] int IDENTITY(1,1) NOT NULL,
    [contractId] int NOT NULL,
    [signerClientId] int NOT NULL,
    [signerUserId] int NULL,
    [signerRole] nvarchar(20) NOT NULL,
    [signatureImageUrl] nvarchar(500) NULL,
    [ipAddress] nvarchar(50) NULL,
    [deviceFingerprint] nvarchar(200) NULL,
    [biometricVerified] bit NOT NULL CONSTRAINT [DF__loanContr__biome__09B45E9A] DEFAULT ((0)),
    [signedAt] datetime2(7) NOT NULL CONSTRAINT [DF__loanContr__signe__0AA882D3] DEFAULT (getutcdate()),
    CONSTRAINT [PK__loanCont__9EE2FCB93316CEB3] PRIMARY KEY CLUSTERED ([signatureId])
);
END
GO

-- dbo.loanConversations
IF OBJECT_ID(N'dbo.loanConversations', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[loanConversations] (
    [conversationId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [borrowerId] int NOT NULL,
    [lenderId] int NOT NULL,
    [borrowerUserId] int NULL,
    [lenderUserId] int NULL,
    [loanProposalId] int NULL,
    [status] nvarchar(20) NOT NULL CONSTRAINT [DF__loanConve__statu__526429B0] DEFAULT ('open'),
    [requestedAmount] decimal(14,2) NULL,
    [agreedAmount] decimal(14,2) NULL,
    [agreedRate] decimal(6,4) NULL,
    [agreedTermMonths] int NULL,
    [title] nvarchar(200) NULL,
    [lastMessageAt] datetime2(7) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__loanConve__creat__53584DE9] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__loanConv__2860E54EF45096F4] PRIMARY KEY CLUSTERED ([conversationId])
);
END
GO

-- dbo.loanDisbursements
IF OBJECT_ID(N'dbo.loanDisbursements', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[loanDisbursements] (
    [disbursementId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [loanId] int NOT NULL,
    [contractId] int NULL,
    [borrowerClientId] int NOT NULL,
    [lenderClientId] int NOT NULL,
    [borrowerUserId] int NULL,
    [lenderUserId] int NULL,
    [amount] decimal(14,2) NOT NULL,
    [currency] nvarchar(10) NOT NULL CONSTRAINT [DF__loanDisbu__curre__15261146] DEFAULT ('MXN'),
    [disbursementStatus] nvarchar(20) NOT NULL CONSTRAINT [DF__loanDisbu__disbu__161A357F] DEFAULT ('pending'),
    [transferReference] nvarchar(200) NULL,
    [transferMethod] nvarchar(50) NULL,
    [sentAt] datetime2(7) NULL,
    [receivedAt] datetime2(7) NULL,
    [errorNote] nvarchar(500) NULL,
    [notes] nvarchar(max) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__loanDisbu__creat__170E59B8] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__loanDisb__FEF4CEB09CCEFA74] PRIMARY KEY CLUSTERED ([disbursementId])
);
END
GO

-- dbo.loanInstallments
IF OBJECT_ID(N'dbo.loanInstallments', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[loanInstallments] (
    [installmentId] int IDENTITY(1,1) NOT NULL,
    [loanId] int NOT NULL,
    [clientId] int NOT NULL,
    [companyId] int NOT NULL,
    [lenderId] int NOT NULL,
    [installmentNumber] int NOT NULL,
    [dueDate] date NOT NULL,
    [amount] decimal(18,2) NOT NULL,
    [principal] decimal(18,2) NOT NULL,
    [interest] decimal(18,2) NOT NULL,
    [remainingBalance] decimal(18,2) NOT NULL,
    [status] nvarchar(20) NOT NULL CONSTRAINT [DF__loanInsta__statu__0DB9F9A8] DEFAULT ('pending'),
    [stripePaymentIntentId] nvarchar(100) NULL,
    [failureReason] nvarchar(500) NULL,
    [attemptCount] int NOT NULL CONSTRAINT [DF__loanInsta__attem__0EAE1DE1] DEFAULT ((0)),
    [lastAttemptAt] datetime2(7) NULL,
    [paidAt] datetime2(7) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__loanInsta__creat__0FA2421A] DEFAULT (getutcdate()),
    CONSTRAINT [PK__loanInst__B9163708162793C0] PRIMARY KEY CLUSTERED ([installmentId])
);
END
GO

-- dbo.loanMessages
IF OBJECT_ID(N'dbo.loanMessages', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[loanMessages] (
    [messageId] int IDENTITY(1,1) NOT NULL,
    [conversationId] int NOT NULL,
    [senderId] int NOT NULL,
    [senderUserId] int NULL,
    [senderRole] nvarchar(20) NOT NULL,
    [msgType] nvarchar(20) NOT NULL CONSTRAINT [DF__loanMessa__msgTy__5634BA94] DEFAULT ('text'),
    [body] nvarchar(2000) NULL,
    [amount] decimal(14,2) NULL,
    [rate] decimal(6,4) NULL,
    [termMonths] int NULL,
    [isRead] bit NOT NULL CONSTRAINT [DF__loanMessa__isRea__5728DECD] DEFAULT ((0)),
    [pushSent] bit NOT NULL CONSTRAINT [DF__loanMessa__pushS__581D0306] DEFAULT ((0)),
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__loanMessa__creat__5911273F] DEFAULT (getutcdate()),
    CONSTRAINT [PK__loanMess__4808B9934A5A17DE] PRIMARY KEY CLUSTERED ([messageId])
);
END
GO

-- dbo.loanOffers
IF OBJECT_ID(N'dbo.loanOffers', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[loanOffers] (
    [offerId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [lenderId] int NOT NULL,
    [availableCapital] decimal(18,2) NOT NULL,
    [minRate] decimal(5,2) NOT NULL,
    [maxRate] decimal(5,2) NOT NULL,
    [minTermMonths] int NOT NULL CONSTRAINT [DF__loanOffer__minTe__1AA9E072] DEFAULT ((1)),
    [maxTermMonths] int NOT NULL CONSTRAINT [DF__loanOffer__maxTe__1B9E04AB] DEFAULT ((24)),
    [description] nvarchar(500) NULL,
    [isActive] bit NOT NULL CONSTRAINT [DF__loanOffer__isAct__1C9228E4] DEFAULT ((1)),
    [expiresAt] datetime NULL,
    [created_At] datetime NOT NULL CONSTRAINT [DF__loanOffer__creat__1D864D1D] DEFAULT (getutcdate()),
    [consentAccepted] bit NOT NULL CONSTRAINT [DF__loanOffer__conse__0C26B6F1] DEFAULT ((0)),
    [consentAcceptedAt] datetime NULL,
    CONSTRAINT [PK__loanOffe__589DEA006B5CC5D2] PRIMARY KEY CLUSTERED ([offerId])
);
END
GO

-- dbo.loanProposals
IF OBJECT_ID(N'dbo.loanProposals', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[loanProposals] (
    [proposalId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [lenderId] int NOT NULL,
    [borrowerId] int NOT NULL,
    [requestedAmount] decimal(18,2) NOT NULL,
    [proposedRate] decimal(5,2) NOT NULL,
    [termMonths] int NOT NULL,
    [status] nvarchar(20) NOT NULL CONSTRAINT [DF__loanPropo__statu__233F2673] DEFAULT ('pending'),
    [lenderNote] nvarchar(500) NULL,
    [borrowerNote] nvarchar(500) NULL,
    [pushNotificationId] int NULL,
    [respondedAt] datetime2(7) NULL,
    [expiresAt] datetime2(7) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__loanPropo__creat__24334AAC] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__loanProp__3EB9E814998E9C92] PRIMARY KEY CLUSTERED ([proposalId])
);
END
GO

-- dbo.loanProposals_status
IF OBJECT_ID(N'dbo.loanProposals_status', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[loanProposals_status] (
    [statusId] int IDENTITY(1,1) NOT NULL,
    [statusCode] nvarchar(20) NOT NULL,
    [description] nvarchar(100) NOT NULL,
    [sortOrder] int NOT NULL,
    [isTerminal] bit NOT NULL CONSTRAINT [DF_loanProposals_status_isTerminal] DEFAULT ((0)),
    CONSTRAINT [PK_loanProposals_status] PRIMARY KEY CLUSTERED ([statusId]),
    CONSTRAINT [UQ_loanProposals_status_statusCode] UNIQUE NONCLUSTERED ([statusCode])
);
END
GO

-- dbo.loans
IF OBJECT_ID(N'dbo.loans', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[loans] (
    [loanId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [loanNumber] nvarchar(50) NOT NULL,
    [clientId] int NOT NULL,
    [principalAmount] decimal(18,2) NOT NULL,
    [interestRate] decimal(5,2) NOT NULL,
    [termMonths] int NOT NULL,
    [paymentFrequency] nvarchar(20) NOT NULL CONSTRAINT [DF__loans__paymentFr__7A721B0A] DEFAULT ('monthly'),
    [approvedAmount] decimal(18,2) NULL,
    [totalRepaymentAmount] decimal(18,2) NULL,
    [disbursementDate] datetime2(7) NULL,
    [maturityDate] datetime2(7) NULL,
    [loanStatus] nvarchar(30) NOT NULL CONSTRAINT [DF__loans__loanStatu__7B663F43] DEFAULT ('pending'),
    [notes] nvarchar(max) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__loans__created_A__7C5A637C] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__loans__6DB788FF216A15A5] PRIMARY KEY CLUSTERED ([loanId])
);
END
GO

-- dbo.logins
IF OBJECT_ID(N'dbo.logins', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[logins] (
    [loginId] int IDENTITY(1,1) NOT NULL,
    [userId] int NULL,
    [active] char(1) NULL
);
END
GO

-- dbo.logs
IF OBJECT_ID(N'dbo.logs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[logs] (
    [logId] int IDENTITY(1,1) NOT NULL,
    [tableName] nvarchar(50) NOT NULL,
    [recordId] int NOT NULL,
    [action] nvarchar(50) NOT NULL,
    [actionTime] datetime NULL CONSTRAINT [DF_logs_actionTime] DEFAULT (getdate()),
    CONSTRAINT [PK__logs__7839F64D402FF8F5] PRIMARY KEY CLUSTERED ([logId])
);
END
GO

-- dbo.machines
IF OBJECT_ID(N'dbo.machines', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[machines] (
    [machineId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [name] nvarchar(100) NOT NULL,
    [machineType] nvarchar(30) NOT NULL CONSTRAINT [DF__machines__machin__155B1B70] DEFAULT ('washer'),
    [capacityKg] decimal(8,2) NOT NULL CONSTRAINT [DF__machines__capaci__164F3FA9] DEFAULT ((0)),
    [kwhPerCycle] decimal(8,4) NOT NULL CONSTRAINT [DF__machines__kwhPer__174363E2] DEFAULT ((0)),
    [litersPerCycle] decimal(8,2) NOT NULL CONSTRAINT [DF__machines__liters__1837881B] DEFAULT ((0)),
    [cycleMinutes] int NOT NULL CONSTRAINT [DF__machines__cycleM__192BAC54] DEFAULT ((45)),
    [purchaseCost] decimal(18,2) NOT NULL CONSTRAINT [DF__machines__purcha__1A1FD08D] DEFAULT ((0)),
    [lifetimeCycles] int NOT NULL CONSTRAINT [DF__machines__lifeti__1B13F4C6] DEFAULT ((5000)),
    [currentCycleCount] int NOT NULL CONSTRAINT [DF__machines__curren__1C0818FF] DEFAULT ((0)),
    [maintenanceEvery] int NOT NULL CONSTRAINT [DF__machines__mainte__1CFC3D38] DEFAULT ((200)),
    [lastMaintenanceCycle] int NOT NULL CONSTRAINT [DF__machines__lastMa__1DF06171] DEFAULT ((0)),
    [wearScore] int NOT NULL CONSTRAINT [DF__machines__wearSc__1EE485AA] DEFAULT ((0)),
    [status] nvarchar(20) NOT NULL CONSTRAINT [DF__machines__status__1FD8A9E3] DEFAULT ('available'),
    [location] nvarchar(100) NULL,
    [serialNumber] nvarchar(100) NULL,
    [notes] nvarchar(500) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__machines__create__20CCCE1C] DEFAULT (getutcdate()),
    [updatedAt] datetime2(7) NULL,
    CONSTRAINT [PK__machines__D1ABE06D3EC266FA] PRIMARY KEY CLUSTERED ([machineId])
);
END
GO

-- dbo.maintenanceLogs
IF OBJECT_ID(N'dbo.maintenanceLogs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[maintenanceLogs] (
    [logId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [machineId] int NOT NULL,
    [logType] nvarchar(30) NOT NULL CONSTRAINT [DF__maintenan__logTy__38A457AD] DEFAULT ('scheduled'),
    [description] nvarchar(500) NULL,
    [technicianName] nvarchar(100) NULL,
    [costMXN] decimal(10,2) NOT NULL CONSTRAINT [DF__maintenan__costM__39987BE6] DEFAULT ((0)),
    [cycleAtMaintenance] int NOT NULL CONSTRAINT [DF__maintenan__cycle__3A8CA01F] DEFAULT ((0)),
    [wearBefore] int NOT NULL CONSTRAINT [DF__maintenan__wearB__3B80C458] DEFAULT ((0)),
    [wearAfter] int NOT NULL CONSTRAINT [DF__maintenan__wearA__3C74E891] DEFAULT ((0)),
    [partsReplaced] nvarchar(500) NULL,
    [nextServiceCycle] int NULL,
    [completedAt] datetime2(7) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__maintenan__creat__3D690CCA] DEFAULT (getutcdate()),
    CONSTRAINT [PK__maintena__7839F64D8E7B1394] PRIMARY KEY CLUSTERED ([logId])
);
END
GO

-- dbo.manufactures
IF OBJECT_ID(N'dbo.manufactures', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[manufactures] (
    [manufactureId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(50) NOT NULL,
    CONSTRAINT [PK_manufactures_manufactureId] PRIMARY KEY CLUSTERED ([manufactureId])
);
END
GO

-- dbo.marketplaceOrders
IF OBJECT_ID(N'dbo.marketplaceOrders', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[marketplaceOrders] (
    [marketplaceOrderId] bigint IDENTITY(1,1) NOT NULL,
    [channel] varchar(20) NOT NULL,
    [market] char(2) NOT NULL,
    [channelOrderId] nvarchar(100) NOT NULL,
    [unifiedProductId] bigint NOT NULL,
    [quantity] int NOT NULL CONSTRAINT [DF__marketpla__quant__19CACAD2] DEFAULT ((1)),
    [soldPriceUsd] decimal(18,6) NOT NULL,
    [buyerAddressJson] nvarchar(max) NULL,
    [status] varchar(30) NOT NULL CONSTRAINT [DF__marketpla__statu__1ABEEF0B] DEFAULT ('ORDER_NEW'),
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__marketpla__creat__1BB31344] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NOT NULL CONSTRAINT [DF__marketpla__updat__1CA7377D] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__marketpl__E42F3684B3AEEFD2] PRIMARY KEY CLUSTERED ([marketplaceOrderId]),
    CONSTRAINT [UQ_marketplaceOrders] UNIQUE NONCLUSTERED ([channel], [market], [channelOrderId]),
    CONSTRAINT [CK_marketplaceOrders_channel] CHECK ([channel]='mercadolibre' OR [channel]='amazon'),
    CONSTRAINT [CK_marketplaceOrders_market] CHECK ([market]='MX' OR [market]='US'),
    CONSTRAINT [CK_marketplaceOrders_status] CHECK ([status]='CANCELLED' OR [status]='ON_HOLD' OR [status]='DELIVERED' OR [status]='SHIPPED' OR [status]='LABEL_CREATED' OR [status]='PURCHASED' OR [status]='PURCHASE_AUTHORIZED' OR [status]='PROCUREMENT_CHECK' OR [status]='ORDER_NEW')
);
END
GO

-- dbo.measurements
IF OBJECT_ID(N'dbo.measurements', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[measurements] (
    [measurementId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(50) NOT NULL,
    [prefix] varchar(50) NOT NULL,
    CONSTRAINT [PK_measurements_measurementId] PRIMARY KEY CLUSTERED ([measurementId])
);
END
GO

-- dbo.mercadolibreWebhookLogs
IF OBJECT_ID(N'dbo.mercadolibreWebhookLogs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[mercadolibreWebhookLogs] (
    [id] int IDENTITY(1,1) NOT NULL,
    [created_at] datetime NOT NULL CONSTRAINT [DF__mercadoli__creat__56D3D912] DEFAULT (getdate()),
    [payload] nvarchar(max) NOT NULL,
    CONSTRAINT [PK__mercadol__3213E83FC9A68D27] PRIMARY KEY CLUSTERED ([id])
);
END
GO

-- dbo.messageTickets
IF OBJECT_ID(N'dbo.messageTickets', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[messageTickets] (
    [ticketId] bigint IDENTITY(1,1) NOT NULL,
    [channel] varchar(20) NOT NULL,
    [market] char(2) NOT NULL,
    [threadId] nvarchar(120) NULL,
    [marketplaceOrderId] bigint NULL,
    [customerMessage] nvarchar(max) NOT NULL,
    [suggestedReply] nvarchar(max) NULL,
    [finalReply] nvarchar(max) NULL,
    [status] varchar(20) NOT NULL CONSTRAINT [DF__messageTi__statu__384F51F2] DEFAULT ('pending'),
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__messageTi__creat__3943762B] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NOT NULL CONSTRAINT [DF__messageTi__updat__3A379A64] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__messageT__3333C6106EC7A269] PRIMARY KEY CLUSTERED ([ticketId]),
    CONSTRAINT [CK_messageTickets_channel] CHECK ([channel]='mercadolibre' OR [channel]='amazon'),
    CONSTRAINT [CK_messageTickets_market] CHECK ([market]='MX' OR [market]='US'),
    CONSTRAINT [CK_messageTickets_status] CHECK ([status]='needs_review' OR [status]='sent' OR [status]='approved' OR [status]='suggested' OR [status]='pending')
);
END
GO

-- dbo.ml_crawl_frontier
IF OBJECT_ID(N'dbo.ml_crawl_frontier', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_crawl_frontier] (
    [frontierId] bigint IDENTITY(1,1) NOT NULL,
    [frontierKey] varchar(200) NOT NULL,
    [frontierType] varchar(50) NOT NULL,
    [sourceUrl] nvarchar(1000) NULL,
    [entityId] varchar(100) NULL,
    [firstSeenAt] datetime2(3) NOT NULL CONSTRAINT [DF__ml_crawl___first__4A38F803] DEFAULT (sysutcdatetime()),
    [lastSeenAt] datetime2(3) NOT NULL CONSTRAINT [DF__ml_crawl___lastS__4B2D1C3C] DEFAULT (sysutcdatetime()),
    [lastCrawledAt] datetime2(3) NULL,
    [status] varchar(20) NOT NULL CONSTRAINT [DF__ml_crawl___statu__4C214075] DEFAULT ('pending'),
    [cooldownUntil] datetime2(3) NULL,
    CONSTRAINT [PK__ml_crawl__9FFAC27D2E05DB11] PRIMARY KEY CLUSTERED ([frontierId])
);
END
GO

-- dbo.ml_domains_cache
IF OBJECT_ID(N'dbo.ml_domains_cache', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_domains_cache] (
    [id] bigint IDENTITY(1,1) NOT NULL,
    [site_id] nvarchar(10) NOT NULL,
    [query_text] nvarchar(400) NOT NULL,
    [domain_id] nvarchar(80) NULL,
    [category_id] nvarchar(40) NULL,
    [attributes_json] nvarchar(max) NULL,
    [created_at] datetime2(3) NOT NULL CONSTRAINT [DF__ml_domain__creat__7DEDA633] DEFAULT (sysutcdatetime()),
    [raw_json] nvarchar(max) NULL,
    [updated_at] datetime2(3) NOT NULL CONSTRAINT [DF_ml_domains_cache_updated] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__ml_domai__3213E83F40159E46] PRIMARY KEY CLUSTERED ([id])
);
END
GO

-- dbo.ml_item_features
IF OBJECT_ID(N'dbo.ml_item_features', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_item_features] (
    [item_id] nvarchar(40) NOT NULL,
    [site_id] nvarchar(10) NOT NULL,
    [domain_id] nvarchar(80) NULL,
    [category_id] nvarchar(40) NULL,
    [brand] nvarchar(120) NULL,
    [model] nvarchar(120) NULL,
    [internal_memory] nvarchar(60) NULL,
    [ram] nvarchar(60) NULL,
    [storage_type] nvarchar(60) NULL,
    [condition] nvarchar(30) NULL,
    [price] decimal(18,2) NULL,
    [sold_quantity] int NULL,
    [available_quantity] int NULL,
    [shipping_free] bit NULL,
    [logistics_type] nvarchar(60) NULL,
    [features_json] nvarchar(max) NULL,
    [last_seen_at] datetime2(3) NOT NULL CONSTRAINT [DF__ml_item_f__last___086B34A6] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__ml_item___52020FDDE1676D2F] PRIMARY KEY CLUSTERED ([item_id])
);
END
GO

-- dbo.ml_item_scores
IF OBJECT_ID(N'dbo.ml_item_scores', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_item_scores] (
    [item_id] nvarchar(40) NOT NULL,
    [model_version] nvarchar(50) NOT NULL,
    [score] float NOT NULL,
    [explanation_json] nvarchar(max) NULL,
    [created_at] datetime2(3) NOT NULL CONSTRAINT [DF__ml_item_s__creat__0B47A151] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__ml_item___52020FDD18E40D30] PRIMARY KEY CLUSTERED ([item_id])
);
END
GO

-- dbo.ml_jobs
IF OBJECT_ID(N'dbo.ml_jobs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_jobs] (
    [job_id] bigint IDENTITY(1,1) NOT NULL,
    [job_type] nvarchar(30) NOT NULL,
    [payload_json] nvarchar(max) NOT NULL,
    [status] nvarchar(20) NOT NULL CONSTRAINT [DF__ml_jobs__status__0E240DFC] DEFAULT ('queued'),
    [attempts] int NOT NULL CONSTRAINT [DF__ml_jobs__attempt__0F183235] DEFAULT ((0)),
    [last_error] nvarchar(max) NULL,
    [locked_by] nvarchar(80) NULL,
    [locked_until] datetime2(3) NULL,
    [created_at] datetime2(3) NOT NULL CONSTRAINT [DF__ml_jobs__created__100C566E] DEFAULT (sysutcdatetime()),
    [updated_at] datetime2(3) NOT NULL CONSTRAINT [DF__ml_jobs__updated__11007AA7] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__ml_jobs__6E32B6A52EEE1648] PRIMARY KEY CLUSTERED ([job_id])
);
END
GO

-- dbo.ml_oauth_states
IF OBJECT_ID(N'dbo.ml_oauth_states', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_oauth_states] (
    [state] nvarchar(200) NOT NULL,
    [code_verifier] nvarchar(400) NOT NULL,
    [created_at] datetime2(7) NOT NULL CONSTRAINT [DF__ml_oauth___creat__67FE6514] DEFAULT (sysutcdatetime()),
    [used_at] datetime2(7) NULL,
    CONSTRAINT [PK__ml_oauth__A9360BC25864DAAF] PRIMARY KEY CLUSTERED ([state])
);
END
GO

-- dbo.ml_scrape_items
IF OBJECT_ID(N'dbo.ml_scrape_items', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_scrape_items] (
    [scrapeItemId] bigint IDENTITY(1,1) NOT NULL,
    [runId] bigint NOT NULL,
    [pageId] bigint NULL,
    [itemId] varchar(50) NOT NULL,
    [itemUrl] nvarchar(1000) NOT NULL,
    [title] nvarchar(1000) NULL,
    [price] decimal(18,2) NULL,
    [currencyId] varchar(10) NULL,
    [sellerId] varchar(50) NULL,
    [sellerUrl] nvarchar(1000) NULL,
    [positionInPage] int NULL,
    [discoveredAt] datetime2(3) NOT NULL CONSTRAINT [DF__ml_scrape__disco__44801EAD] DEFAULT (sysutcdatetime()),
    [persisted] bit NOT NULL CONSTRAINT [DF__ml_scrape__persi__457442E6] DEFAULT ((0)),
    CONSTRAINT [PK__ml_scrap__66D72BE8C50FB8C7] PRIMARY KEY CLUSTERED ([scrapeItemId])
);
END
GO

-- dbo.ml_scrape_pages
IF OBJECT_ID(N'dbo.ml_scrape_pages', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_scrape_pages] (
    [pageId] bigint IDENTITY(1,1) NOT NULL,
    [runId] bigint NOT NULL,
    [pageNumber] int NOT NULL,
    [pageUrl] nvarchar(1000) NOT NULL,
    [httpStatus] int NULL,
    [itemsExtracted] int NOT NULL CONSTRAINT [DF__ml_scrape__items__3EC74557] DEFAULT ((0)),
    [itemsReportedTotal] int NULL,
    [durationMs] int NULL,
    [blocked] bit NOT NULL CONSTRAINT [DF__ml_scrape__block__3FBB6990] DEFAULT ((0)),
    [blockReason] varchar(100) NULL,
    [createdAt] datetime2(3) NOT NULL CONSTRAINT [DF__ml_scrape__creat__40AF8DC9] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__ml_scrap__54B1FF741FF771FE] PRIMARY KEY CLUSTERED ([pageId])
);
END
GO

-- dbo.ml_scrape_runs
IF OBJECT_ID(N'dbo.ml_scrape_runs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_scrape_runs] (
    [runId] bigint IDENTITY(1,1) NOT NULL,
    [runUid] uniqueidentifier NOT NULL CONSTRAINT [DF__ml_scrape__runUi__353DDB1D] DEFAULT (newid()),
    [sourceUrl] nvarchar(1000) NOT NULL,
    [siteId] varchar(10) NOT NULL CONSTRAINT [DF__ml_scrape__siteI__3631FF56] DEFAULT ('MLM'),
    [queryText] nvarchar(500) NULL,
    [startedAt] datetime2(3) NOT NULL CONSTRAINT [DF__ml_scrape__start__3726238F] DEFAULT (sysutcdatetime()),
    [finishedAt] datetime2(3) NULL,
    [status] varchar(20) NOT NULL CONSTRAINT [DF__ml_scrape__statu__381A47C8] DEFAULT ('running'),
    [pagesVisited] int NOT NULL CONSTRAINT [DF__ml_scrape__pages__390E6C01] DEFAULT ((0)),
    [itemsExtracted] int NOT NULL CONSTRAINT [DF__ml_scrape__items__3A02903A] DEFAULT ((0)),
    [itemsReportedTotal] int NULL,
    [coveragePercent] AS (case when [itemsReportedTotal] IS NULL OR [itemsReportedTotal]=(0) then NULL else CONVERT([decimal](5,2),([itemsExtracted]*(100.0))/[itemsReportedTotal]) end),
    [workerId] varchar(100) NULL,
    [errorMessage] nvarchar(max) NULL,
    [createdAt] datetime2(3) NOT NULL CONSTRAINT [DF__ml_scrape__creat__3AF6B473] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(3) NOT NULL CONSTRAINT [DF__ml_scrape__updat__3BEAD8AC] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__ml_scrap__9A8D7A2F93711AB8] PRIMARY KEY CLUSTERED ([runId])
);
END
GO

-- dbo.ml_search_results
IF OBJECT_ID(N'dbo.ml_search_results', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_search_results] (
    [search_result_id] bigint IDENTITY(1,1) NOT NULL,
    [search_run_id] bigint NOT NULL,
    [item_id] nvarchar(40) NOT NULL,
    [title] nvarchar(500) NULL,
    [price] decimal(18,2) NULL,
    [currency_id] nvarchar(10) NULL,
    [condition] nvarchar(30) NULL,
    [permalink] nvarchar(1000) NULL,
    [seller_id] bigint NULL,
    [thumbnail] nvarchar(1000) NULL,
    [raw_json] nvarchar(max) NULL,
    [created_at] datetime2(3) NOT NULL CONSTRAINT [DF__ml_search__creat__049AA3C2] DEFAULT (sysutcdatetime()),
    [updated_at] datetime2(3) NOT NULL CONSTRAINT [DF_ml_search_results_updated] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__ml_searc__BF721C502303558D] PRIMARY KEY CLUSTERED ([search_result_id])
);
END
GO

-- dbo.ml_search_runs
IF OBJECT_ID(N'dbo.ml_search_runs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_search_runs] (
    [search_run_id] bigint IDENTITY(1,1) NOT NULL,
    [site_id] nvarchar(10) NOT NULL,
    [query_text] nvarchar(400) NOT NULL,
    [domain_id] nvarchar(80) NULL,
    [category_id] nvarchar(40) NULL,
    [filters_json] nvarchar(max) NULL,
    [status] nvarchar(20) NOT NULL CONSTRAINT [DF__ml_search__statu__00CA12DE] DEFAULT ('queued'),
    [http_status] int NULL,
    [error_json] nvarchar(max) NULL,
    [created_at] datetime2(3) NOT NULL CONSTRAINT [DF__ml_search__creat__01BE3717] DEFAULT (sysutcdatetime()),
    [finished_at] datetime2(3) NULL,
    [request_url] nvarchar(1000) NULL,
    [updated_at] datetime2(3) NOT NULL CONSTRAINT [DF_ml_search_runs_updated] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__ml_searc__99EAA24B57E7A02B] PRIMARY KEY CLUSTERED ([search_run_id])
);
END
GO

-- dbo.ml_tokens
IF OBJECT_ID(N'dbo.ml_tokens', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[ml_tokens] (
    [id] int IDENTITY(1,1) NOT NULL,
    [access_token] nvarchar(max) NOT NULL,
    [refresh_token] nvarchar(max) NOT NULL,
    [expires_at] datetime2(7) NOT NULL,
    [created_at] datetime2(7) NOT NULL CONSTRAINT [DF__ml_tokens__creat__6ADAD1BF] DEFAULT (sysutcdatetime()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__ml_token__3213E83F8D6B1534] PRIMARY KEY CLUSTERED ([id])
);
END
GO

-- dbo.modules
IF OBJECT_ID(N'dbo.modules', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[modules] (
    [moduleId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(100) NOT NULL,
    [createdAt] datetime NULL CONSTRAINT [DF__modules__created__4F7CD00D] DEFAULT (getdate()),
    [updatedAt] datetime NULL,
    CONSTRAINT [PK_modules_moduleId] PRIMARY KEY CLUSTERED ([moduleId])
);
END
GO

-- dbo.NotificationDeliveries
IF OBJECT_ID(N'dbo.NotificationDeliveries', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[NotificationDeliveries] (
    [notificationDeliveryId] int IDENTITY(1,1) NOT NULL,
    [pushNotificationId] int NOT NULL,
    [userId] int NOT NULL,
    [isSent] bit NOT NULL CONSTRAINT [DF_NotificationDeliveries_isSent] DEFAULT ((0)),
    [isRead] bit NOT NULL CONSTRAINT [DF_NotificationDeliveries_isRead] DEFAULT ((0)),
    [sentAt] datetime NULL,
    [readAt] datetime NULL,
    [created_At] datetime NOT NULL CONSTRAINT [DF_NotificationDeliveries_created_At] DEFAULT (getdate()),
    CONSTRAINT [PK__Notifica__048E01B0C8063802] PRIMARY KEY CLUSTERED ([notificationDeliveryId])
);
END
GO

-- dbo.onboardingReminders
IF OBJECT_ID(N'dbo.onboardingReminders', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[onboardingReminders] (
    [reminderId] int IDENTITY(1,1) NOT NULL,
    [clientId] int NOT NULL,
    [companyId] int NOT NULL,
    [missingSteps] nvarchar(500) NOT NULL,
    [sentAt] datetime2(7) NOT NULL CONSTRAINT [DF__onboardin__sentA__41F8B7BD] DEFAULT (getutcdate()),
    CONSTRAINT [PK__onboardi__09DAAAE396F66FC3] PRIMARY KEY CLUSTERED ([reminderId]),
    CONSTRAINT [UQ_onboardingReminders_client] UNIQUE NONCLUSTERED ([clientId], [companyId])
);
END
GO

-- dbo.opportunities
IF OBJECT_ID(N'dbo.opportunities', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[opportunities] (
    [opportunityId] bigint IDENTITY(1,1) NOT NULL,
    [unifiedProductId] bigint NOT NULL,
    [buyOfferId] bigint NOT NULL,
    [sellListingId] bigint NOT NULL,
    [channel] varchar(20) NOT NULL,
    [buyTotalCostUsd] decimal(18,6) NOT NULL,
    [sellGrossUsd] decimal(18,6) NOT NULL,
    [sellFeesUsd] decimal(18,6) NOT NULL,
    [returnsRiskUsd] decimal(18,6) NOT NULL,
    [sellNetUsd] decimal(18,6) NOT NULL,
    [netMarginUsd] decimal(18,6) NOT NULL,
    [roi] decimal(18,8) NOT NULL,
    [velocityScore] decimal(9,6) NULL,
    [confidenceScore] decimal(9,6) NULL,
    [finalScore] decimal(9,6) NULL,
    [status] varchar(20) NOT NULL CONSTRAINT [DF__opportuni__statu__636EBA21] DEFAULT ('active'),
    [calculatedAt] datetime2(7) NOT NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__opportuni__creat__6462DE5A] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NOT NULL CONSTRAINT [DF__opportuni__updat__65570293] DEFAULT (sysutcdatetime()),
    [market] char(2) NOT NULL CONSTRAINT [DF_opportunities_market] DEFAULT ('US'),
    CONSTRAINT [PK__opportun__7368FB8484425816] PRIMARY KEY CLUSTERED ([opportunityId]),
    CONSTRAINT [CK_opportunities_channel] CHECK ([channel]='mercadolibre' OR [channel]='amazon'),
    CONSTRAINT [CK_opportunities_market] CHECK ([market]='MX' OR [market]='US'),
    CONSTRAINT [CK_opportunities_status] CHECK ([status]='blocked' OR [status]='expired' OR [status]='watch' OR [status]='active')
);
END
GO

-- dbo.orderDetails
IF OBJECT_ID(N'dbo.orderDetails', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[orderDetails] (
    [orderDetaild] int IDENTITY(1,1) NOT NULL,
    [orderId] int NOT NULL,
    [productOptionId] int NULL,
    [productOptionChoiceId] int NULL,
    CONSTRAINT [PK__orderDet__2D623FA2F613C4E7] PRIMARY KEY CLUSTERED ([orderDetaild])
);
END
GO

-- dbo.orders
IF OBJECT_ID(N'dbo.orders', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[orders] (
    [orderId] int IDENTITY(1,1) NOT NULL,
    [productId] int NULL,
    [quantity] int NULL,
    [paymentMethod] nvarchar(20) NULL,
    [orderDate] datetime NULL CONSTRAINT [DF_orders_orderDate] DEFAULT (getdate()),
    [orderNumber] int NULL,
    [tableNumber] int NULL,
    [userId] int NULL,
    [total] decimal(10,2) NOT NULL,
    [createdAt] datetime NOT NULL CONSTRAINT [DF_orders_createdAt] DEFAULT (getdate()),
    [clientId] int NULL,
    [comments] nvarchar(max) NULL,
    CONSTRAINT [PK__orders__0809335D7F7924A6] PRIMARY KEY CLUSTERED ([orderId])
);
END
GO

-- dbo.orderStatuses
IF OBJECT_ID(N'dbo.orderStatuses', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[orderStatuses] (
    [orderStatusId] int IDENTITY(1,1) NOT NULL,
    [name] nvarchar(20) NOT NULL,
    [color] nvarchar(20) NOT NULL,
    CONSTRAINT [PK__orderSta__C0F25369C8CBA3BB] PRIMARY KEY CLUSTERED ([orderStatusId])
);
END
GO

-- dbo.orderTracking
IF OBJECT_ID(N'dbo.orderTracking', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[orderTracking] (
    [trackingId] int IDENTITY(1,1) NOT NULL,
    [orderId] int NOT NULL,
    [orderStatusId] int NULL,
    [changedBy] int NULL,
    [changedAt] datetime NOT NULL CONSTRAINT [DF__orderTrac__chang__595B4002] DEFAULT (getdate()),
    [notes] nvarchar(max) NULL,
    CONSTRAINT [PK__orderTra__A81574EED048318D] PRIMARY KEY CLUSTERED ([trackingId])
);
END
GO

-- dbo.paymentIntents
IF OBJECT_ID(N'dbo.paymentIntents', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[paymentIntents] (
    [paymentIntentId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [loanId] int NOT NULL,
    [installmentId] int NULL,
    [intentType] nvarchar(12) NOT NULL,
    [expectedAmountMXN] decimal(10,2) NOT NULL,
    [payerClientId] int NOT NULL,
    [payeeClientId] int NOT NULL,
    [beneficiarySnapshotId] int NOT NULL,
    [suggestedReference] nvarchar(40) NOT NULL,
    [expiresAt] datetime2(7) NULL,
    [status] nvarchar(12) NOT NULL CONSTRAINT [DF__paymentIn__statu__7DD8979A] DEFAULT ('OPEN'),
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__paymentIn__creat__7ECCBBD3] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK_paymentIntents] PRIMARY KEY CLUSTERED ([paymentIntentId]),
    CONSTRAINT [CK_paymentIntents_amount] CHECK ([expectedAmountMXN]>(0)),
    CONSTRAINT [CK_paymentIntents_installmentId] CHECK ([intentType]='FUNDING' AND [installmentId] IS NULL OR [intentType]<>'FUNDING' AND [installmentId] IS NOT NULL),
    CONSTRAINT [CK_paymentIntents_intentType] CHECK ([intentType]='PAYOFF' OR [intentType]='PARTIAL' OR [intentType]='INSTALLMENT' OR [intentType]='FUNDING'),
    CONSTRAINT [CK_paymentIntents_status] CHECK ([status]='CANCELLED' OR [status]='EXPIRED' OR [status]='DECLARED' OR [status]='OPEN')
);
END
GO

-- dbo.permissions
IF OBJECT_ID(N'dbo.permissions', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[permissions] (
    [permissionId] int IDENTITY(1,1) NOT NULL,
    [code] nvarchar(80) NOT NULL,
    [name] nvarchar(120) NOT NULL,
    [moduleId] int NOT NULL,
    CONSTRAINT [PK__permissi__D821329C70591060] PRIMARY KEY CLUSTERED ([permissionId]),
    CONSTRAINT [UQ__permissi__357D4CF9FAE8E350] UNIQUE NONCLUSTERED ([code])
);
END
GO

-- dbo.pos_laundry
IF OBJECT_ID(N'dbo.pos_laundry', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[pos_laundry] (
    [laundryId] int IDENTITY(1,1) NOT NULL,
    [total] decimal(10,2) NOT NULL,
    [create_at] datetime NOT NULL CONSTRAINT [DF_pos_laundry_create_at] DEFAULT (getdate()),
    [update_at] datetime NOT NULL CONSTRAINT [DF_pos_laundry_update_at] DEFAULT (getdate()),
    CONSTRAINT [PK__pos_laun__4CF22F3A1CCE5982] PRIMARY KEY CLUSTERED ([laundryId])
);
END
GO

-- dbo.pos_laundry_detail
IF OBJECT_ID(N'dbo.pos_laundry_detail', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[pos_laundry_detail] (
    [laundryDetailId] int IDENTITY(1,1) NOT NULL,
    [laundryId] int NOT NULL,
    [productId] int NOT NULL,
    [cantidad] int NOT NULL CONSTRAINT [DF__pos_laund__canti__0EC32C7A] DEFAULT ((1)),
    [precio_unitario] decimal(10,2) NOT NULL CONSTRAINT [DF__pos_laund__preci__0FB750B3] DEFAULT ((0.00)),
    [subtotal] AS ([cantidad]*[precio_unitario]) PERSISTED,
    [create_at] datetime NOT NULL CONSTRAINT [DF_pos_laundry_detail_create_at] DEFAULT (getdate()),
    [update_at] datetime NOT NULL CONSTRAINT [DF_pos_laundry_detail_update_at] DEFAULT (getdate()),
    CONSTRAINT [PK__pos_laun__747B664B78957D53] PRIMARY KEY CLUSTERED ([laundryDetailId])
);
END
GO

-- dbo.procurementJobs
IF OBJECT_ID(N'dbo.procurementJobs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[procurementJobs] (
    [procJobId] bigint IDENTITY(1,1) NOT NULL,
    [marketplaceOrderId] bigint NOT NULL,
    [supplierCandidate] nvarchar(200) NOT NULL,
    [maxBuyCostUsd] decimal(18,6) NOT NULL,
    [decision] varchar(10) NULL,
    [reason] nvarchar(500) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__procureme__creat__2BE97B0D] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NOT NULL CONSTRAINT [DF__procureme__updat__2CDD9F46] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__procurem__923E63844E3158BD] PRIMARY KEY CLUSTERED ([procJobId]),
    CONSTRAINT [CK_procurement_decision] CHECK ([decision] IS NULL OR ([decision]='cancel' OR [decision]='hold' OR [decision]='buy'))
);
END
GO

-- dbo.productCategories
IF OBJECT_ID(N'dbo.productCategories', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[productCategories] (
    [productCategoryId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(50) NOT NULL,
    [image] varchar(50) NULL,
    [companyId] int NULL,
    CONSTRAINT [PK__productC__A944253BB94E0B95] PRIMARY KEY CLUSTERED ([productCategoryId])
);
END
GO

-- dbo.productDetails
IF OBJECT_ID(N'dbo.productDetails', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[productDetails] (
    [productDetailId] int IDENTITY(1,1) NOT NULL,
    [productId] int NOT NULL,
    [stockQuantity] int NOT NULL,
    [unitPrice] decimal(10,2) NOT NULL,
    [salePrice] decimal(10,2) NOT NULL,
    [createdAt] datetime NULL CONSTRAINT [DF__productDe__creat__6FE99F9F] DEFAULT (getdate()),
    [updatedAt] datetime NULL,
    CONSTRAINT [PK_productDetailS_productDetailId] PRIMARY KEY CLUSTERED ([productDetailId])
);
END
GO

-- dbo.productForms
IF OBJECT_ID(N'dbo.productForms', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[productForms] (
    [productFormId] int IDENTITY(1,1) NOT NULL,
    [quantity] varchar(50) NOT NULL,
    [productPackingPresentationId] int NOT NULL,
    [productsPackingTypeId] int NOT NULL,
    CONSTRAINT [PK_productForms_productformId] PRIMARY KEY CLUSTERED ([productFormId])
);
END
GO

-- dbo.productionOrders
IF OBJECT_ID(N'dbo.productionOrders', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[productionOrders] (
    [orderId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [clientId] int NULL,
    [ticketId] int NULL,
    [machineId] int NOT NULL,
    [assignedBy] int NULL,
    [cycleType] nvarchar(30) NOT NULL CONSTRAINT [DF__productio__cycle__2E26C93A] DEFAULT ('normal'),
    [weightKg] decimal(8,2) NOT NULL CONSTRAINT [DF__productio__weigh__2F1AED73] DEFAULT ((0)),
    [detergentGrams] decimal(8,2) NOT NULL CONSTRAINT [DF__productio__deter__300F11AC] DEFAULT ((0)),
    [extraDetergent] bit NOT NULL CONSTRAINT [DF__productio__extra__310335E5] DEFAULT ((0)),
    [status] nvarchar(20) NOT NULL CONSTRAINT [DF__productio__statu__31F75A1E] DEFAULT ('queued'),
    [startedAt] datetime2(7) NULL,
    [completedAt] datetime2(7) NULL,
    [estimatedMinutes] int NOT NULL CONSTRAINT [DF__productio__estim__32EB7E57] DEFAULT ((45)),
    [actualMinutes] int NULL,
    [notes] nvarchar(500) NULL,
    [realCostElec] decimal(10,4) NULL,
    [realCostWater] decimal(10,4) NULL,
    [realCostDetergent] decimal(10,4) NULL,
    [realCostLabor] decimal(10,4) NULL,
    [realCostDepreciation] decimal(10,4) NULL,
    [realCostOverhead] decimal(10,4) NULL,
    [realCostTotal] decimal(10,4) NULL,
    [ticketPrice] decimal(10,2) NULL,
    [margin] decimal(10,4) NULL,
    [marginPct] decimal(6,2) NULL,
    [alertSent] bit NOT NULL CONSTRAINT [DF__productio__alert__33DFA290] DEFAULT ((0)),
    [maintenanceTriggered] bit NOT NULL CONSTRAINT [DF__productio__maint__34D3C6C9] DEFAULT ((0)),
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__productio__creat__35C7EB02] DEFAULT (getutcdate()),
    [updatedAt] datetime2(7) NULL,
    CONSTRAINT [PK__producti__0809335D39CED7C0] PRIMARY KEY CLUSTERED ([orderId])
);
END
GO

-- dbo.productMatches
IF OBJECT_ID(N'dbo.productMatches', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[productMatches] (
    [matchId] bigint IDENTITY(1,1) NOT NULL,
    [unifiedProductId] bigint NOT NULL,
    [entityType] varchar(10) NOT NULL,
    [entityId] bigint NOT NULL,
    [confidence] decimal(5,4) NOT NULL,
    [matchMethod] varchar(20) NOT NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__productMa__creat__55209ACA] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__productM__02C72A0D2F7B55D5] PRIMARY KEY CLUSTERED ([matchId]),
    CONSTRAINT [CK_productMatches_entityType] CHECK ([entityType]='sell' OR [entityType]='buy'),
    CONSTRAINT [CK_productMatches_matchMethod] CHECK ([matchMethod]='manual' OR [matchMethod]='rules' OR [matchMethod]='embedding' OR [matchMethod]='ean')
);
END
GO

-- dbo.productOptionChoices
IF OBJECT_ID(N'dbo.productOptionChoices', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[productOptionChoices] (
    [productOptionChoiceId] int IDENTITY(1,1) NOT NULL,
    [productOptionId] int NOT NULL,
    [choiceKey] nvarchar(50) NULL,
    [name] nvarchar(100) NULL,
    [price] decimal(10,2) NOT NULL CONSTRAINT [DF__productOp__price__1699586C] DEFAULT ((0)),
    [createdAt] datetime NULL CONSTRAINT [DF__productOp__creat__178D7CA5] DEFAULT (getdate()),
    [updatedAt] datetime NULL CONSTRAINT [DF__productOp__updat__1881A0DE] DEFAULT (getdate()),
    [description] varchar(255) NULL,
    CONSTRAINT [PK__productO__44DDC03473D220A0] PRIMARY KEY CLUSTERED ([productOptionChoiceId])
);
END
GO

-- dbo.productOptions
IF OBJECT_ID(N'dbo.productOptions', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[productOptions] (
    [productOptionId] int IDENTITY(1,1) NOT NULL,
    [productId] int NOT NULL,
    [optionKey] nvarchar(50) NULL,
    [name] nvarchar(100) NULL,
    [type] nvarchar(20) NULL,
    [createdAt] datetime NULL CONSTRAINT [DF__productOp__creat__11D4A34F] DEFAULT (getdate()),
    [updatedAt] datetime NULL CONSTRAINT [DF__productOp__updat__12C8C788] DEFAULT (getdate()),
    CONSTRAINT [PK__productO__800C8D1F94A31085] PRIMARY KEY CLUSTERED ([productOptionId])
);
END
GO

-- dbo.products
IF OBJECT_ID(N'dbo.products', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[products] (
    [productId] int IDENTITY(1,1) NOT NULL,
    [name] nvarchar(255) NOT NULL,
    [code] varchar(100) NULL,
    [dateOfExpire] date NULL,
    [productFormId] int NULL,
    [manufactureId] int NULL,
    [description] varchar(5000) NULL,
    [createdAt] datetime NULL CONSTRAINT [DF__products__create__1F2E9E6D] DEFAULT (getdate()),
    [updatedAt] datetime NULL,
    [barCode] varchar(100) NULL,
    [categoryId] int NULL,
    [companyId] int NOT NULL,
    CONSTRAINT [PK_products_productId] PRIMARY KEY CLUSTERED ([productId])
);
END
GO

-- dbo.productsDescription
IF OBJECT_ID(N'dbo.productsDescription', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[productsDescription] (
    [productDescriptionId] int IDENTITY(1,1) NOT NULL,
    [productId] int NOT NULL,
    [Dosage] varchar(50) NULL,
    [measurementId] int NULL,
    [is_principal] varchar(1) NULL,
    [activeIngredientId] int NULL,
    [createdAt] datetime NULL CONSTRAINT [DF__productsD__creat__1C5231C2] DEFAULT (getdate()),
    [updatedAt] datetime NULL,
    CONSTRAINT [PK_productsDescription_productDescriptionId] PRIMARY KEY CLUSTERED ([productDescriptionId])
);
END
GO

-- dbo.productsPackingPresentation
IF OBJECT_ID(N'dbo.productsPackingPresentation', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[productsPackingPresentation] (
    [productPackingPresentationId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(50) NULL,
    CONSTRAINT [PK_productsPackingPresentation_productPackingPresentationId] PRIMARY KEY CLUSTERED ([productPackingPresentationId])
);
END
GO

-- dbo.productsPackingType
IF OBJECT_ID(N'dbo.productsPackingType', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[productsPackingType] (
    [productsPackingTypeId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(50) NULL,
    CONSTRAINT [PK_productsPackingType_productsPackingTypeId] PRIMARY KEY CLUSTERED ([productsPackingTypeId])
);
END
GO

-- dbo.profiles
IF OBJECT_ID(N'dbo.profiles', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[profiles] (
    [profileId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(50) NOT NULL,
    [userId] int NULL
);
END
GO

-- dbo.profitabilitySnapshots
IF OBJECT_ID(N'dbo.profitabilitySnapshots', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[profitabilitySnapshots] (
    [snapshotId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [snapshotDate] date NOT NULL CONSTRAINT [DF__profitabi__snaps__41399DAE] DEFAULT (CONVERT([date],getutcdate())),
    [periodType] nvarchar(10) NOT NULL CONSTRAINT [DF__profitabi__perio__422DC1E7] DEFAULT ('daily'),
    [totalOrders] int NOT NULL CONSTRAINT [DF__profitabi__total__4321E620] DEFAULT ((0)),
    [totalRevenue] decimal(18,2) NOT NULL CONSTRAINT [DF__profitabi__total__44160A59] DEFAULT ((0)),
    [totalRealCost] decimal(18,2) NOT NULL CONSTRAINT [DF__profitabi__total__450A2E92] DEFAULT ((0)),
    [totalMargin] decimal(18,2) NOT NULL CONSTRAINT [DF__profitabi__total__45FE52CB] DEFAULT ((0)),
    [avgMarginPct] decimal(6,2) NOT NULL CONSTRAINT [DF__profitabi__avgMa__46F27704] DEFAULT ((0)),
    [bestServiceType] nvarchar(50) NULL,
    [worstServiceType] nvarchar(50) NULL,
    [lossOrders] int NOT NULL CONSTRAINT [DF__profitabi__lossO__47E69B3D] DEFAULT ((0)),
    [suggestedPriceAdj] nvarchar(max) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__profitabi__creat__48DABF76] DEFAULT (getutcdate()),
    CONSTRAINT [PK__profitab__BDCD2E0FCC67B9B9] PRIMARY KEY CLUSTERED ([snapshotId]),
    CONSTRAINT [UQ_profitSnap] UNIQUE NONCLUSTERED ([companyId], [snapshotDate], [periodType])
);
END
GO

-- dbo.projects
IF OBJECT_ID(N'dbo.projects', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[projects] (
    [projectId] int IDENTITY(1,1) NOT NULL,
    [projectName] nvarchar(100) NOT NULL,
    [createdAt] datetime NULL CONSTRAINT [DF_projects_createdAt] DEFAULT (getdate()),
    CONSTRAINT [PK_projects_projectId] PRIMARY KEY CLUSTERED ([projectId])
);
END
GO

-- dbo.promotion_targets
IF OBJECT_ID(N'dbo.promotion_targets', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[promotion_targets] (
    [promotionTargetId] int IDENTITY(1,1) NOT NULL,
    [promotionId] int NOT NULL,
    [targetType] varchar(20) NOT NULL,
    [productId] int NULL,
    CONSTRAINT [PK__promotio__8C118CA0C945052A] PRIMARY KEY CLUSTERED ([promotionTargetId])
);
END
GO

-- dbo.promotions
IF OBJECT_ID(N'dbo.promotions', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[promotions] (
    [promotionId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [code] varchar(30) NOT NULL,
    [name] nvarchar(80) NOT NULL,
    [promoType] varchar(20) NOT NULL,
    [isActive] bit NOT NULL CONSTRAINT [DF_promotions_isActive] DEFAULT ((1)),
    [startAtUtc] datetime2(0) NULL,
    [endAtUtc] datetime2(0) NULL,
    [createdAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_promotions_createdAt] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__promotio__99EB696E1FEA7714] PRIMARY KEY CLUSTERED ([promotionId])
);
END
GO

-- dbo.publishJobs
IF OBJECT_ID(N'dbo.publishJobs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[publishJobs] (
    [jobId] bigint IDENTITY(1,1) NOT NULL,
    [draftId] bigint NOT NULL,
    [status] varchar(20) NOT NULL CONSTRAINT [DF__publishJo__statu__7C3A67EB] DEFAULT ('queued'),
    [attempts] int NOT NULL CONSTRAINT [DF__publishJo__attem__7D2E8C24] DEFAULT ((0)),
    [nextRetryAt] datetime2(7) NULL,
    [lastError] nvarchar(2000) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__publishJo__creat__7E22B05D] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NOT NULL CONSTRAINT [DF__publishJo__updat__7F16D496] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__publishJ__164AA1A8812BF051] PRIMARY KEY CLUSTERED ([jobId]),
    CONSTRAINT [CK_publishJobs_status] CHECK ([status]='cancelled' OR [status]='failed' OR [status]='published' OR [status]='processing' OR [status]='queued')
);
END
GO

-- dbo.PushNotifications
IF OBJECT_ID(N'dbo.PushNotifications', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[PushNotifications] (
    [pushNotificationId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [title] nvarchar(200) NOT NULL,
    [message] nvarchar(1000) NOT NULL,
    [notificationType] nvarchar(50) NOT NULL,
    [priority] nvarchar(20) NOT NULL,
    [targetType] nvarchar(50) NOT NULL,
    [targetUserId] int NULL,
    [targetRoleId] int NULL,
    [targetCompanyId] int NULL,
    [navigationRoute] nvarchar(250) NULL,
    [isRead] bit NOT NULL,
    [isSent] bit NOT NULL,
    [sentAt] datetime NULL,
    [scheduledAt] datetime NULL,
    [payloadJson] nvarchar(max) NULL,
    [created_At] datetime NOT NULL CONSTRAINT [DF__PushNotif__creat__5FF32EF8] DEFAULT (getdate()),
    [updated_at] datetime NULL,
    CONSTRAINT [PK__PushNoti__C645E42A4559508F] PRIMARY KEY CLUSTERED ([pushNotificationId])
);
END
GO

-- dbo.registrationReminders
IF OBJECT_ID(N'dbo.registrationReminders', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[registrationReminders] (
    [reminderId] int IDENTITY(1,1) NOT NULL,
    [userId] int NOT NULL,
    [missingSteps] nvarchar(500) NOT NULL,
    [sentAt] datetime2(7) NOT NULL CONSTRAINT [DF__registrat__sentA__5E94F66B] DEFAULT (getutcdate()),
    CONSTRAINT [PK__registra__09DAAAE360E73023] PRIMARY KEY CLUSTERED ([reminderId]),
    CONSTRAINT [UQ_registrationReminders_user] UNIQUE NONCLUSTERED ([userId])
);
END
GO

-- dbo.rewardPoints
IF OBJECT_ID(N'dbo.rewardPoints', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[rewardPoints] (
    [pointId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [clientId] int NOT NULL,
    [balance] int NOT NULL CONSTRAINT [DF__rewardPoi__balan__69478F08] DEFAULT ((0)),
    [lifetimeEarned] int NOT NULL CONSTRAINT [DF__rewardPoi__lifet__6A3BB341] DEFAULT ((0)),
    [lifetimeRedeemed] int NOT NULL CONSTRAINT [DF__rewardPoi__lifet__6B2FD77A] DEFAULT ((0)),
    [lastActivity] datetime2(7) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__rewardPoi__creat__6C23FBB3] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__rewardPo__4CB435AEC336C905] PRIMARY KEY CLUSTERED ([pointId]),
    CONSTRAINT [UQ_rewardPoints_client] UNIQUE NONCLUSTERED ([companyId], [clientId])
);
END
GO

-- dbo.rewardRules
IF OBJECT_ID(N'dbo.rewardRules', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[rewardRules] (
    [ruleId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [ruleName] nvarchar(120) NOT NULL,
    [ruleType] nvarchar(40) NOT NULL CONSTRAINT [DF__rewardRul__ruleT__629A9179] DEFAULT ('purchase'),
    [pointsPerUnit] decimal(10,4) NOT NULL CONSTRAINT [DF__rewardRul__point__638EB5B2] DEFAULT ((1.0)),
    [minAmount] decimal(10,2) NULL,
    [maxPointsPerTx] int NULL,
    [isActive] bit NOT NULL CONSTRAINT [DF__rewardRul__isAct__6482D9EB] DEFAULT ((1)),
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__rewardRul__creat__6576FE24] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__rewardRu__121C06614285647B] PRIMARY KEY CLUSTERED ([ruleId])
);
END
GO

-- dbo.rewardTransactions
IF OBJECT_ID(N'dbo.rewardTransactions', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[rewardTransactions] (
    [txId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [clientId] int NOT NULL,
    [ruleId] int NULL,
    [txType] nvarchar(20) NOT NULL,
    [points] int NOT NULL,
    [balanceAfter] int NOT NULL,
    [referenceId] nvarchar(100) NULL,
    [description] nvarchar(255) NULL,
    [createdBy] int NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__rewardTra__creat__6F00685E] DEFAULT (getutcdate()),
    CONSTRAINT [PK__rewardTr__E3B9916622C6ED85] PRIMARY KEY CLUSTERED ([txId])
);
END
GO

-- dbo.role_permissions
IF OBJECT_ID(N'dbo.role_permissions', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[role_permissions] (
    [roleId] int NOT NULL,
    [permissionId] int NOT NULL,
    CONSTRAINT [PK__role_per__101A55031E8192D8] PRIMARY KEY CLUSTERED ([roleId], [permissionId])
);
END
GO

-- dbo.roles
IF OBJECT_ID(N'dbo.roles', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[roles] (
    [roleId] int IDENTITY(1,1) NOT NULL,
    [code] nvarchar(50) NOT NULL,
    [name] nvarchar(100) NOT NULL,
    [description] nvarchar(255) NULL,
    [active] bit NOT NULL CONSTRAINT [DF__roles__active__04659998] DEFAULT ((1)),
    CONSTRAINT [PK__roles__CD98462AD571E8ED] PRIMARY KEY CLUSTERED ([roleId]),
    CONSTRAINT [UQ__roles__357D4CF9E31564DB] UNIQUE NONCLUSTERED ([code])
);
END
GO

-- dbo.savedPaymentMethods
IF OBJECT_ID(N'dbo.savedPaymentMethods', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[savedPaymentMethods] (
    [methodId] int IDENTITY(1,1) NOT NULL,
    [clientId] int NOT NULL,
    [companyId] int NOT NULL,
    [stripePaymentMethodId] nvarchar(100) NOT NULL,
    [last4] nvarchar(4) NULL,
    [brand] nvarchar(20) NULL,
    [expiryMonth] int NULL,
    [expiryYear] int NULL,
    [isDefault] bit NOT NULL CONSTRAINT [DF__savedPaym__isDef__09E968C4] DEFAULT ((1)),
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__savedPaym__creat__0ADD8CFD] DEFAULT (getutcdate()),
    [updatedAt] datetime2(7) NULL,
    CONSTRAINT [PK__savedPay__C7B34C893D50A3B7] PRIMARY KEY CLUSTERED ([methodId]),
    CONSTRAINT [UQ_savedPaymentMethods] UNIQUE NONCLUSTERED ([clientId], [companyId])
);
END
GO

-- dbo.sellListingAttributes
IF OBJECT_ID(N'dbo.sellListingAttributes', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[sellListingAttributes] (
    [sellListingId] bigint NOT NULL,
    [attributesJson] nvarchar(max) NOT NULL,
    [attributesHash] varbinary(32) NULL,
    [updatedAt] datetime2(0) NOT NULL CONSTRAINT [DF_sellListingAttributes_updatedAt] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__sellList__3828EE37A90BF5E3] PRIMARY KEY CLUSTERED ([sellListingId])
);
END
GO

-- dbo.sellListings
IF OBJECT_ID(N'dbo.sellListings', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[sellListings] (
    [sellListingId] bigint IDENTITY(1,1) NOT NULL,
    [channel] varchar(20) NOT NULL,
    [channelItemId] nvarchar(80) NOT NULL,
    [title] nvarchar(500) NULL,
    [sellPriceOriginal] decimal(18,6) NOT NULL,
    [currencyOriginal] char(3) NOT NULL,
    [sellPriceUsd] decimal(18,6) NOT NULL,
    [fxRateToUsd] decimal(18,8) NOT NULL,
    [fxAsOfDate] date NOT NULL,
    [fulfillmentType] nvarchar(50) NULL,
    [shippingTimeDays] int NULL,
    [rating] decimal(5,2) NULL,
    [reviewsCount] int NULL,
    [listingTimestamp] datetime2(7) NOT NULL,
    [unifiedProductId] bigint NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__sellListi__creat__4F67C174] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NOT NULL CONSTRAINT [DF__sellListi__updat__505BE5AD] DEFAULT (sysutcdatetime()),
    [market] char(2) NOT NULL CONSTRAINT [DF_sellListings_market] DEFAULT ('US'),
    [listingDate] AS (CONVERT([date],[listingTimestamp])) PERSISTED,
    [scrapeItemId] bigint NULL,
    CONSTRAINT [PK__sellList__3828EE37DE63641A] PRIMARY KEY CLUSTERED ([sellListingId]),
    CONSTRAINT [UQ_sellListings] UNIQUE NONCLUSTERED ([channel], [market], [channelItemId], [listingTimestamp]),
    CONSTRAINT [CK_sellListings_channel] CHECK ([channel]='mercadolibre' OR [channel]='amazon'),
    CONSTRAINT [CK_sellListings_market] CHECK ([market]='MX' OR [market]='US')
);
END
GO

-- dbo.shipments
IF OBJECT_ID(N'dbo.shipments', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[shipments] (
    [shipmentId] bigint IDENTITY(1,1) NOT NULL,
    [marketplaceOrderId] bigint NOT NULL,
    [carrier] nvarchar(50) NULL,
    [serviceLevel] nvarchar(50) NULL,
    [labelRef] nvarchar(500) NULL,
    [trackingNumber] nvarchar(100) NULL,
    [status] varchar(20) NOT NULL CONSTRAINT [DF__shipments__statu__31A25463] DEFAULT ('LABEL_CREATED'),
    [shippedAt] datetime2(7) NULL,
    [deliveredAt] datetime2(7) NULL,
    [lastError] nvarchar(2000) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__shipments__creat__3296789C] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NOT NULL CONSTRAINT [DF__shipments__updat__338A9CD5] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__shipment__47217801DF16F1B1] PRIMARY KEY CLUSTERED ([shipmentId]),
    CONSTRAINT [CK_shipments_status] CHECK ([status]='ERROR' OR [status]='DELIVERED' OR [status]='SHIPPED' OR [status]='LABEL_CREATED')
);
END
GO

-- dbo.status
IF OBJECT_ID(N'dbo.status', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[status] (
    [statusId] int IDENTITY(1,1) NOT NULL,
    [status] nvarchar(20) NOT NULL,
    [createdAt] datetime NULL CONSTRAINT [DF_status_createdAt] DEFAULT (getdate()),
    CONSTRAINT [PK_status_statusId] PRIMARY KEY CLUSTERED ([statusId])
);
END
GO

-- dbo.stripeConnectedAccounts
IF OBJECT_ID(N'dbo.stripeConnectedAccounts', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[stripeConnectedAccounts] (
    [id] int IDENTITY(1,1) NOT NULL,
    [clientId] int NOT NULL,
    [companyId] int NOT NULL,
    [connectedAccountId] nvarchar(100) NOT NULL,
    [chargesEnabled] bit NOT NULL CONSTRAINT [DF__stripeCon__charg__6C5905DD] DEFAULT ((0)),
    [payoutsEnabled] bit NOT NULL CONSTRAINT [DF__stripeCon__payou__6D4D2A16] DEFAULT ((0)),
    [detailsSubmitted] bit NOT NULL CONSTRAINT [DF__stripeCon__detai__6E414E4F] DEFAULT ((0)),
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__stripeCon__creat__6F357288] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    [hasExternalAccount] bit NOT NULL CONSTRAINT [DF__stripeCon__hasEx__349EBC9F] DEFAULT ((0)),
    [externalAccountLast4] nvarchar(4) NULL,
    [externalAccountType] nvarchar(20) NULL,
    [externalAccountBankName] nvarchar(100) NULL,
    [identitySubmitted] bit NOT NULL CONSTRAINT [DF__stripeCon__ident__13FCE2E3] DEFAULT ((0)),
    [tosAccepted] bit NOT NULL CONSTRAINT [DF__stripeCon__tosAc__6E96540A] DEFAULT ((0)),
    [tosAcceptedAt] datetime2(7) NULL,
    CONSTRAINT [PK__stripeCo__3213E83F79382E0A] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UQ_stripeAccounts_client] UNIQUE NONCLUSTERED ([clientId], [companyId])
);
END
GO

-- dbo.stripeTransactions
IF OBJECT_ID(N'dbo.stripeTransactions', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[stripeTransactions] (
    [transactionId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [loanId] int NULL,
    [proposalId] int NULL,
    [fromClientId] int NOT NULL,
    [toClientId] int NOT NULL,
    [amount] int NOT NULL,
    [currency] nvarchar(3) NOT NULL CONSTRAINT [DF__stripeTra__curre__7211DF33] DEFAULT ('mxn'),
    [paymentType] nvarchar(30) NOT NULL,
    [status] nvarchar(20) NOT NULL CONSTRAINT [DF__stripeTra__statu__7306036C] DEFAULT ('pending'),
    [stripePaymentIntentId] nvarchar(100) NULL,
    [stripeTransferId] nvarchar(100) NULL,
    [failureReason] nvarchar(500) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__stripeTra__creat__73FA27A5] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    [stripePayoutId] nvarchar(100) NULL,
    CONSTRAINT [PK__stripeTr__9B57CF728C626BE5] PRIMARY KEY CLUSTERED ([transactionId])
);
END
GO

-- dbo.subCategories
IF OBJECT_ID(N'dbo.subCategories', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[subCategories] (
    [subcategoryid] int IDENTITY(1,1) NOT NULL,
    [name] varchar(100) NOT NULL,
    [categoryid] int NOT NULL,
    CONSTRAINT [PK_subcategories_categoryId] PRIMARY KEY CLUSTERED ([subcategoryid])
);
END
GO

-- dbo.Suppliers
IF OBJECT_ID(N'dbo.Suppliers', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Suppliers] (
    [supplierId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [supplierName] nvarchar(200) NOT NULL,
    [contactName] nvarchar(100) NULL,
    [phone] nvarchar(20) NULL,
    [email] nvarchar(100) NULL,
    [address] nvarchar(max) NULL,
    [active] nvarchar(1) NOT NULL,
    [created_At] datetime NOT NULL CONSTRAINT [DF__Suppliers__creat__4A03EDD9] DEFAULT (getdate()),
    [updated_at] datetime NULL,
    CONSTRAINT [PK__Supplier__DB8E62ED535CF84D] PRIMARY KEY CLUSTERED ([supplierId])
);
END
GO

-- dbo.symptoms
IF OBJECT_ID(N'dbo.symptoms', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[symptoms] (
    [symptomId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(100) NOT NULL,
    [productId] int NOT NULL,
    CONSTRAINT [PK_symptoms_symptomId] PRIMARY KEY CLUSTERED ([symptomId])
);
END
GO

-- dbo.sysdiagrams
IF OBJECT_ID(N'dbo.sysdiagrams', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[sysdiagrams] (
    [name] nvarchar(128) NOT NULL,
    [principal_id] int NOT NULL,
    [diagram_id] int IDENTITY(1,1) NOT NULL,
    [version] int NULL,
    [definition] varbinary(max) NULL,
    CONSTRAINT [PK__sysdiagr__C2B05B61DF4A20AC] PRIMARY KEY CLUSTERED ([diagram_id]),
    CONSTRAINT [UK_principal_name] UNIQUE NONCLUSTERED ([principal_id], [name])
);
END
GO

-- dbo.tankWaters
IF OBJECT_ID(N'dbo.tankWaters', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tankWaters] (
    [tankWaterId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(200) NULL,
    [metrics] int NULL,
    [capacity] varchar(200) NULL,
    [device] varchar(200) NULL,
    [created_At] datetime NULL CONSTRAINT [DF__tankWater__creat__1446FBA6] DEFAULT (getdate()),
    [updated_at] datetime NULL CONSTRAINT [DF__tankWater__updat__153B1FDF] DEFAULT (getdate()),
    CONSTRAINT [PK__tankWate__D2C6661913BED3FB] PRIMARY KEY CLUSTERED ([tankWaterId])
);
END
GO

-- dbo.tankWatersDetails
IF OBJECT_ID(N'dbo.tankWatersDetails', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tankWatersDetails] (
    [tankWatersDetailId] int IDENTITY(1,1) NOT NULL,
    [tankWaterId] int NOT NULL,
    [quantity] varchar(200) NOT NULL,
    [created_At] datetime NULL CONSTRAINT [DF__tankWater__creat__116A8EFB] DEFAULT (getdate()),
    CONSTRAINT [PK__tankWate__67F6435BE35D74D2] PRIMARY KEY CLUSTERED ([tankWatersDetailId])
);
END
GO

-- dbo.tickets
IF OBJECT_ID(N'dbo.tickets', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[tickets] (
    [ticketId] int IDENTITY(1,1) NOT NULL,
    [ticketNumber] varchar(50) NULL,
    [ticketData] nvarchar(max) NULL,
    [printed] bit NULL CONSTRAINT [DF__tickets__printed__5FD33367] DEFAULT ((0)),
    [printedDate] datetime NULL,
    [created_At] datetime NULL CONSTRAINT [DF__tickets__created__60C757A0] DEFAULT (getdate()),
    [updated_At] datetime NULL CONSTRAINT [DF__tickets__updated__61BB7BD9] DEFAULT (getdate()),
    [incomeId] int NULL,
    [companyId] int NULL,
    [fileName] varchar(500) NULL,
    [containerName] varchar(200) NULL,
    [blobPath] varchar(1000) NULL,
    [receiptUrl] varchar(max) NULL,
    [uploadAzure] bit NOT NULL CONSTRAINT [DF__tickets__uploadA__0EE3280B] DEFAULT ((0)),
    [uploadAzureDate] datetime NULL,
    [whatsappSent] bit NOT NULL CONSTRAINT [DF__tickets__whatsap__0FD74C44] DEFAULT ((0)),
    [whatsappSentDate] datetime NULL,
    [whatsappPhone] varchar(50) NULL,
    [whatsappResponse] varchar(max) NULL,
    [smsSent] bit NOT NULL CONSTRAINT [DF__tickets__smsSent__10CB707D] DEFAULT ((0)),
    [smsSentDate] datetime NULL,
    [smsPhone] varchar(50) NULL,
    [smsResponse] varchar(max) NULL,
    [generationStatus] varchar(50) NOT NULL CONSTRAINT [DF__tickets__generat__11BF94B6] DEFAULT ('PENDING'),
    [generatedDate] datetime NULL,
    [errorMessage] varchar(max) NULL,
    [shortCode] varchar(20) NULL,
    CONSTRAINT [PK__tickets__3333C610D9D3546E] PRIMARY KEY CLUSTERED ([ticketId])
);
END
GO

-- dbo.transfers
IF OBJECT_ID(N'dbo.transfers', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[transfers] (
    [transferId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [toClientId] int NOT NULL,
    [toBankAccountId] int NOT NULL,
    [amountMXN] decimal(12,2) NOT NULL,
    [purpose] nvarchar(30) NOT NULL,
    [loanId] int NULL,
    [provider] nvarchar(20) NOT NULL CONSTRAINT [DF__transfers__provi__3EE740E8] DEFAULT ('stp'),
    [providerRef] nvarchar(100) NULL,
    [cepUrl] nvarchar(2048) NULL,
    [status] nvarchar(20) NOT NULL CONSTRAINT [DF__transfers__statu__3FDB6521] DEFAULT ('pending'),
    [failureReason] nvarchar(500) NULL,
    [idempotencyKey] nvarchar(64) NOT NULL,
    [settledAt] datetime2(7) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__transfers__creat__40CF895A] DEFAULT (getutcdate()),
    [updated_at] datetime2(7) NULL,
    CONSTRAINT [PK__transfer__AAADCD81EE018725] PRIMARY KEY CLUSTERED ([transferId]),
    CONSTRAINT [CK_transfers_amount] CHECK ([amountMXN]>(0))
);
END
GO

-- dbo.transfers_status
IF OBJECT_ID(N'dbo.transfers_status', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[transfers_status] (
    [statusCode] nvarchar(20) NOT NULL,
    [sortOrder] int NOT NULL,
    [description] nvarchar(100) NULL,
    [isTerminal] bit NOT NULL CONSTRAINT [DF__transfers__isTer__3C0AD43D] DEFAULT ((0)),
    CONSTRAINT [PK__transfer__AD4366F710AD6199] PRIMARY KEY CLUSTERED ([statusCode])
);
END
GO

-- dbo.unifiedProducts
IF OBJECT_ID(N'dbo.unifiedProducts', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[unifiedProducts] (
    [unifiedProductId] bigint IDENTITY(1,1) NOT NULL,
    [brand] nvarchar(200) NULL,
    [model] nvarchar(200) NULL,
    [title] nvarchar(500) NULL,
    [ean_upc] nvarchar(64) NULL,
    [attributesJson] nvarchar(max) NULL,
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__unifiedPr__creat__44EA3301] DEFAULT (sysutcdatetime()),
    [updatedAt] datetime2(7) NOT NULL CONSTRAINT [DF__unifiedPr__updat__45DE573A] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__unifiedP__B8856962CB28CF78] PRIMARY KEY CLUSTERED ([unifiedProductId])
);
END
GO

-- dbo.userCompanies
IF OBJECT_ID(N'dbo.userCompanies', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[userCompanies] (
    [userCompanyId] int IDENTITY(1,1) NOT NULL,
    [userId] int NOT NULL,
    [companyId] int NOT NULL,
    [branchId] int NULL,
    [isDefault] bit NOT NULL CONSTRAINT [DF__userCompa__isDef__78F3E6EC] DEFAULT ((0)),
    [roleName] varchar(50) NULL,
    [active] varchar(1) NOT NULL CONSTRAINT [DF__userCompa__activ__79E80B25] DEFAULT ('1'),
    [created_at] datetime NOT NULL CONSTRAINT [DF__userCompa__creat__7ADC2F5E] DEFAULT (getdate()),
    [updated_at] datetime NULL,
    [roleId] int NULL,
    CONSTRAINT [PK__userComp__615573C83F93AB34] PRIMARY KEY CLUSTERED ([userCompanyId])
);
END
GO

-- dbo.users
IF OBJECT_ID(N'dbo.users', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[users] (
    [userId] int IDENTITY(1,1) NOT NULL,
    [name] varchar(50) NULL,
    [email] varchar(50) NULL,
    [password] varchar(50) NULL,
    [created_at] datetime NULL CONSTRAINT [DF_users2_created_at] DEFAULT (getdate()),
    [active] varchar(1) NOT NULL CONSTRAINT [DF_users_active] DEFAULT ('1'),
    [image] varchar(200) NULL,
    [imageUrl] nvarchar(500) NULL,
    [qrCode] nvarchar(100) NULL,
    [companyId] int NOT NULL CONSTRAINT [DF__users__companyId__0CFADF99] DEFAULT ((1)),
    [clientId] int NULL,
    [employeeId] int NULL,
    [cellphone] nvarchar(20) NULL,
    [appProfile] varchar(20) NULL,
    [enabledModules] nvarchar(max) NULL,
    [identityVerified] bit NOT NULL CONSTRAINT [DF_users_identityVerified] DEFAULT ((0))
);
END
GO

-- dbo.utilityRates
IF OBJECT_ID(N'dbo.utilityRates', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[utilityRates] (
    [rateId] int IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [electricityPerKwh] decimal(10,4) NOT NULL CONSTRAINT [DF__utilityRa__elect__249D5F00] DEFAULT ((3.20)),
    [waterPerLiter] decimal(10,4) NOT NULL CONSTRAINT [DF__utilityRa__water__25918339] DEFAULT ((0.015)),
    [detergentPerGram] decimal(10,4) NOT NULL CONSTRAINT [DF__utilityRa__deter__2685A772] DEFAULT ((0.08)),
    [laborPerHour] decimal(10,2) NOT NULL CONSTRAINT [DF__utilityRa__labor__2779CBAB] DEFAULT ((80.00)),
    [overheadPct] decimal(5,2) NOT NULL CONSTRAINT [DF__utilityRa__overh__286DEFE4] DEFAULT ((15.00)),
    [targetMarginPct] decimal(5,2) NOT NULL CONSTRAINT [DF__utilityRa__targe__2962141D] DEFAULT ((40.00)),
    [effectiveFrom] date NOT NULL CONSTRAINT [DF__utilityRa__effec__2A563856] DEFAULT (CONVERT([date],getutcdate())),
    [createdAt] datetime2(7) NOT NULL CONSTRAINT [DF__utilityRa__creat__2B4A5C8F] DEFAULT (getutcdate()),
    CONSTRAINT [PK__utilityR__5705EA14B4B8C022] PRIMARY KEY CLUSTERED ([rateId]),
    CONSTRAINT [UQ_utilityRates] UNIQUE NONCLUSTERED ([companyId], [effectiveFrom])
);
END
GO

-- dbo.vending
IF OBJECT_ID(N'dbo.vending', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[vending] (
    [id] int IDENTITY(1,1) NOT NULL,
    [ingreso] decimal(10,2) NOT NULL,
    [productId] int NULL,
    [create_at] datetime NOT NULL CONSTRAINT [DF_vending_create_at] DEFAULT (getdate()),
    [update_at] datetime NOT NULL CONSTRAINT [DF_vending_update_at] DEFAULT (getdate()),
    CONSTRAINT [PK__vending__3213E83F815926EF] PRIMARY KEY CLUSTERED ([id])
);
END
GO

-- dbo.walletTransactions
IF OBJECT_ID(N'dbo.walletTransactions', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[walletTransactions] (
    [entryId] bigint IDENTITY(1,1) NOT NULL,
    [companyId] int NOT NULL,
    [clientId] int NULL,
    [entryType] nvarchar(30) NOT NULL,
    [direction] char(1) NOT NULL,
    [amountMXN] decimal(12,2) NOT NULL,
    [referenceType] nvarchar(20) NULL,
    [referenceId] int NULL,
    [idempotencyKey] nvarchar(64) NOT NULL,
    [balanceAfter] decimal(12,2) NULL,
    [note] nvarchar(255) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__walletTra__creat__33758E3C] DEFAULT (getutcdate()),
    CONSTRAINT [PK__walletTr__D124D3D5814961F6] PRIMARY KEY CLUSTERED ([entryId]),
    CONSTRAINT [CK_walletTransactions_amount] CHECK ([amountMXN]>(0)),
    CONSTRAINT [CK_walletTransactions_direction] CHECK ([direction]='C' OR [direction]='D')
);
END
GO

-- dbo.walletTransactions_entryType
IF OBJECT_ID(N'dbo.walletTransactions_entryType', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[walletTransactions_entryType] (
    [entryType] nvarchar(30) NOT NULL,
    [sortOrder] int NOT NULL,
    [description] nvarchar(100) NULL,
    CONSTRAINT [PK__walletTr__0C130830269FAD64] PRIMARY KEY CLUSTERED ([entryType])
);
END
GO

-- dbo.whatsapp_messages
IF OBJECT_ID(N'dbo.whatsapp_messages', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[whatsapp_messages] (
    [messageId] int IDENTITY(1,1) NOT NULL,
    [phoneNumber] varchar(20) NOT NULL,
    [messageBody] nvarchar(max) NOT NULL,
    [responseBody] nvarchar(max) NULL,
    [createdAt] datetime NULL CONSTRAINT [DF__whatsapp___creat__54CB950F] DEFAULT (getdate()),
    [direction] varchar(10) NOT NULL,
    [status] varchar(50) NULL,
    CONSTRAINT [PK__whatsapp__4808B9932417FE84] PRIMARY KEY CLUSTERED ([messageId])
);
END
GO

-- dbo.workflowLogs
IF OBJECT_ID(N'dbo.workflowLogs', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[workflowLogs] (
    [workflowLogId] bigint IDENTITY(1,1) NOT NULL,
    [workflowId] uniqueidentifier NOT NULL,
    [correlationId] uniqueidentifier NULL,
    [companyId] int NOT NULL,
    [clientId] int NULL,
    [userId] int NULL,
    [entityName] varchar(100) NULL,
    [entityId] int NULL,
    [workflowName] varchar(100) NULL,
    [stepName] varchar(100) NULL,
    [actionName] varchar(100) NULL,
    [status] varchar(30) NULL,
    [message] nvarchar(max) NULL,
    [durationMs] int NULL,
    [requestJson] nvarchar(max) NULL,
    [responseJson] nvarchar(max) NULL,
    [exception] nvarchar(max) NULL,
    [ipAddress] varchar(50) NULL,
    [deviceInfo] varchar(200) NULL,
    [appVersion] varchar(50) NULL,
    [apiEndpoint] varchar(200) NULL,
    [created_At] datetime2(7) NOT NULL CONSTRAINT [DF__workflowL__creat__04BA9F53] DEFAULT (sysutcdatetime()),
    CONSTRAINT [PK__workflow__5FDC1A179A92A959] PRIMARY KEY CLUSTERED ([workflowLogId])
);
END
GO

/* ---------- INDICES ---------- */

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_applicationLogs_correlationId' AND object_id = OBJECT_ID(N'dbo.applicationLogs'))
CREATE NONCLUSTERED INDEX [IX_applicationLogs_correlationId] ON [dbo].[applicationLogs] ([correlationId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_applicationLogs_level_time' AND object_id = OBJECT_ID(N'dbo.applicationLogs'))
CREATE NONCLUSTERED INDEX [IX_applicationLogs_level_time] ON [dbo].[applicationLogs] ([level], [created_At]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_auditLogs_correlationId' AND object_id = OBJECT_ID(N'dbo.auditLogs'))
CREATE NONCLUSTERED INDEX [IX_auditLogs_correlationId] ON [dbo].[auditLogs] ([correlationId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_auditLogs_entity' AND object_id = OBJECT_ID(N'dbo.auditLogs'))
CREATE NONCLUSTERED INDEX [IX_auditLogs_entity] ON [dbo].[auditLogs] ([companyId], [entityName], [entityId], [created_At]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_bankAccounts_company_client' AND object_id = OBJECT_ID(N'dbo.bankAccounts'))
CREATE NONCLUSTERED INDEX [IX_bankAccounts_company_client] ON [dbo].[bankAccounts] ([companyId], [clientId], [isActive]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_bankAccounts_clabeHash' AND object_id = OBJECT_ID(N'dbo.bankAccounts'))
CREATE UNIQUE NONCLUSTERED INDEX [UQ_bankAccounts_clabeHash] ON [dbo].[bankAccounts] ([companyId], [clabeHash]) WHERE ([accountStatus]<>'ARCHIVED' AND [isActive]=(1));
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_bankAccounts_client_clabe' AND object_id = OBJECT_ID(N'dbo.bankAccounts'))
CREATE UNIQUE NONCLUSTERED INDEX [UQ_bankAccounts_client_clabe] ON [dbo].[bankAccounts] ([clientId], [clabe]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_buyOffers_source_ts' AND object_id = OBJECT_ID(N'dbo.buyOffers'))
CREATE NONCLUSTERED INDEX [IX_buyOffers_source_ts] ON [dbo].[buyOffers] ([sourceType], [sourceName], [offerTimestamp] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_buyOffers_unified_ts' AND object_id = OBJECT_ID(N'dbo.buyOffers'))
CREATE NONCLUSTERED INDEX [IX_buyOffers_unified_ts] ON [dbo].[buyOffers] ([unifiedProductId], [offerTimestamp] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cashRegisterMovements_CompanyDate' AND object_id = OBJECT_ID(N'dbo.cashRegisterMovements'))
CREATE NONCLUSTERED INDEX [IX_cashRegisterMovements_CompanyDate] ON [dbo].[cashRegisterMovements] ([companyId], [createdAt]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cashRegisterMovements_SessionDate' AND object_id = OBJECT_ID(N'dbo.cashRegisterMovements'))
CREATE NONCLUSTERED INDEX [IX_cashRegisterMovements_SessionDate] ON [dbo].[cashRegisterMovements] ([sessionId], [createdAt]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cashRegisterMovements_incomeId' AND object_id = OBJECT_ID(N'dbo.cashRegisterMovements'))
CREATE NONCLUSTERED INDEX [IX_cashRegisterMovements_incomeId] ON [dbo].[cashRegisterMovements] ([incomeId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cashRegisterMovements_sessionId' AND object_id = OBJECT_ID(N'dbo.cashRegisterMovements'))
CREATE NONCLUSTERED INDEX [IX_cashRegisterMovements_sessionId] ON [dbo].[cashRegisterMovements] ([sessionId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cashRegisterSessions_Status' AND object_id = OBJECT_ID(N'dbo.cashRegisterSessions'))
CREATE NONCLUSTERED INDEX [IX_cashRegisterSessions_Status] ON [dbo].[cashRegisterSessions] ([companyId], [status]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ClientFaceRecognitions_CompanyId' AND object_id = OBJECT_ID(N'dbo.ClientFaceRecognitions'))
CREATE NONCLUSTERED INDEX [IX_ClientFaceRecognitions_CompanyId] ON [dbo].[ClientFaceRecognitions] ([companyId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ClientFaceRecognitions_ConfidenceScore' AND object_id = OBJECT_ID(N'dbo.ClientFaceRecognitions'))
CREATE NONCLUSTERED INDEX [IX_ClientFaceRecognitions_ConfidenceScore] ON [dbo].[ClientFaceRecognitions] ([confidence_score]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ClientFaceRecognitions_Created_At' AND object_id = OBJECT_ID(N'dbo.ClientFaceRecognitions'))
CREATE NONCLUSTERED INDEX [IX_ClientFaceRecognitions_Created_At] ON [dbo].[ClientFaceRecognitions] ([created_At]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ClientFaceRecognitions_accepted_at' AND object_id = OBJECT_ID(N'dbo.ClientFaceRecognitions'))
CREATE NONCLUSTERED INDEX [IX_ClientFaceRecognitions_accepted_at] ON [dbo].[ClientFaceRecognitions] ([accepted_at]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ClientFaceRecognitions_contract_accepted' AND object_id = OBJECT_ID(N'dbo.ClientFaceRecognitions'))
CREATE NONCLUSTERED INDEX [IX_ClientFaceRecognitions_contract_accepted] ON [dbo].[ClientFaceRecognitions] ([contract_accepted]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ClientFaceRecognitions_document_type' AND object_id = OBJECT_ID(N'dbo.ClientFaceRecognitions'))
CREATE NONCLUSTERED INDEX [IX_ClientFaceRecognitions_document_type] ON [dbo].[ClientFaceRecognitions] ([document_type]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ClientFaceRecognitions_is_verified' AND object_id = OBJECT_ID(N'dbo.ClientFaceRecognitions'))
CREATE NONCLUSTERED INDEX [IX_ClientFaceRecognitions_is_verified] ON [dbo].[ClientFaceRecognitions] ([is_verified]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_clientFollowUps_client_risk' AND object_id = OBJECT_ID(N'dbo.clientFollowUps'))
CREATE NONCLUSTERED INDEX [IX_clientFollowUps_client_risk] ON [dbo].[clientFollowUps] ([companyId], [clientId], [riskStatus]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_clientFollowUps_company_due' AND object_id = OBJECT_ID(N'dbo.clientFollowUps'))
CREATE NONCLUSTERED INDEX [IX_clientFollowUps_company_due] ON [dbo].[clientFollowUps] ([companyId], [dueDate]) INCLUDE ([riskStatus]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_clients_email_not_null' AND object_id = OBJECT_ID(N'dbo.clients'))
CREATE UNIQUE NONCLUSTERED INDEX [UX_clients_email_not_null] ON [dbo].[clients] ([email]) WHERE ([email] IS NOT NULL);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_clothesCatalog_company_active' AND object_id = OBJECT_ID(N'dbo.clothesCatalog'))
CREATE NONCLUSTERED INDEX [IX_clothesCatalog_company_active] ON [dbo].[clothesCatalog] ([companyId], [isActive], [sortOrder]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_clothesCatalog_company_name' AND object_id = OBJECT_ID(N'dbo.clothesCatalog'))
CREATE UNIQUE NONCLUSTERED INDEX [UX_clothesCatalog_company_name] ON [dbo].[clothesCatalog] ([companyId], [name]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_commission_terminals_lookup' AND object_id = OBJECT_ID(N'dbo.commission_terminals'))
CREATE NONCLUSTERED INDEX [IX_commission_terminals_lookup] ON [dbo].[commission_terminals] ([provider], [terminalName], [isActive]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_costRules_channel_effective' AND object_id = OBJECT_ID(N'dbo.costRules'))
CREATE NONCLUSTERED INDEX [IX_costRules_channel_effective] ON [dbo].[costRules] ([channel], [effectiveFrom] DESC, [effectiveTo]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_costRules_channel_market_effective' AND object_id = OBJECT_ID(N'dbo.costRules'))
CREATE NONCLUSTERED INDEX [IX_costRules_channel_market_effective] ON [dbo].[costRules] ([channel], [market], [effectiveFrom] DESC, [effectiveTo]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_exchangeRates_AsOf' AND object_id = OBJECT_ID(N'dbo.exchangeRates'))
CREATE NONCLUSTERED INDEX [IX_exchangeRates_AsOf] ON [dbo].[exchangeRates] ([asOfDate] DESC, [fromCurrency], [toCurrency]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ingestState_nextRun' AND object_id = OBJECT_ID(N'dbo.ingestState'))
CREATE NONCLUSTERED INDEX [IX_ingestState_nextRun] ON [dbo].[ingestState] ([status], [nextRunAt], [updatedAt] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_integrationLogs_correlationId' AND object_id = OBJECT_ID(N'dbo.integrationLogs'))
CREATE NONCLUSTERED INDEX [IX_integrationLogs_correlationId] ON [dbo].[integrationLogs] ([correlationId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_integrationLogs_service_time' AND object_id = OBJECT_ID(N'dbo.integrationLogs'))
CREATE NONCLUSTERED INDEX [IX_integrationLogs_service_time] ON [dbo].[integrationLogs] ([service], [created_At]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inventoryMovements_company_date' AND object_id = OBJECT_ID(N'dbo.inventoryMovements'))
CREATE NONCLUSTERED INDEX [IX_inventoryMovements_company_date] ON [dbo].[inventoryMovements] ([companyId], [createdAt] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inventoryMovements_company_product' AND object_id = OBJECT_ID(N'dbo.inventoryMovements'))
CREATE NONCLUSTERED INDEX [IX_inventoryMovements_company_product] ON [dbo].[inventoryMovements] ([companyId], [productId], [createdAt] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_loanProposals_company_borrower' AND object_id = OBJECT_ID(N'dbo.loanProposals'))
CREATE NONCLUSTERED INDEX [IX_loanProposals_company_borrower] ON [dbo].[loanProposals] ([companyId], [borrowerId], [created_At]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_loanProposals_company_lender' AND object_id = OBJECT_ID(N'dbo.loanProposals'))
CREATE NONCLUSTERED INDEX [IX_loanProposals_company_lender] ON [dbo].[loanProposals] ([companyId], [lenderId], [status]) INCLUDE ([created_At]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_marketplaceOrders_status' AND object_id = OBJECT_ID(N'dbo.marketplaceOrders'))
CREATE NONCLUSTERED INDEX [IX_marketplaceOrders_status] ON [dbo].[marketplaceOrders] ([status], [channel], [market], [updatedAt] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_crawl_frontier_status' AND object_id = OBJECT_ID(N'dbo.ml_crawl_frontier'))
CREATE NONCLUSTERED INDEX [IX_ml_crawl_frontier_status] ON [dbo].[ml_crawl_frontier] ([status]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_ml_crawl_frontier_key' AND object_id = OBJECT_ID(N'dbo.ml_crawl_frontier'))
CREATE UNIQUE NONCLUSTERED INDEX [UX_ml_crawl_frontier_key] ON [dbo].[ml_crawl_frontier] ([frontierKey]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_domains_cache_site_query_created' AND object_id = OBJECT_ID(N'dbo.ml_domains_cache'))
CREATE NONCLUSTERED INDEX [IX_ml_domains_cache_site_query_created] ON [dbo].[ml_domains_cache] ([site_id], [query_text], [created_at] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_item_features_site_domain' AND object_id = OBJECT_ID(N'dbo.ml_item_features'))
CREATE NONCLUSTERED INDEX [IX_ml_item_features_site_domain] ON [dbo].[ml_item_features] ([site_id], [domain_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_item_scores_score_created' AND object_id = OBJECT_ID(N'dbo.ml_item_scores'))
CREATE NONCLUSTERED INDEX [IX_ml_item_scores_score_created] ON [dbo].[ml_item_scores] ([score] DESC, [created_at] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_jobs_status_type_created' AND object_id = OBJECT_ID(N'dbo.ml_jobs'))
CREATE NONCLUSTERED INDEX [IX_ml_jobs_status_type_created] ON [dbo].[ml_jobs] ([status], [job_type], [created_at]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_scrape_items_runId' AND object_id = OBJECT_ID(N'dbo.ml_scrape_items'))
CREATE NONCLUSTERED INDEX [IX_ml_scrape_items_runId] ON [dbo].[ml_scrape_items] ([runId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_scrape_items_sellerId' AND object_id = OBJECT_ID(N'dbo.ml_scrape_items'))
CREATE NONCLUSTERED INDEX [IX_ml_scrape_items_sellerId] ON [dbo].[ml_scrape_items] ([sellerId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_ml_scrape_items_itemId' AND object_id = OBJECT_ID(N'dbo.ml_scrape_items'))
CREATE UNIQUE NONCLUSTERED INDEX [UX_ml_scrape_items_itemId] ON [dbo].[ml_scrape_items] ([itemId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_scrape_pages_pageNumber' AND object_id = OBJECT_ID(N'dbo.ml_scrape_pages'))
CREATE NONCLUSTERED INDEX [IX_ml_scrape_pages_pageNumber] ON [dbo].[ml_scrape_pages] ([pageNumber]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_scrape_pages_runId' AND object_id = OBJECT_ID(N'dbo.ml_scrape_pages'))
CREATE NONCLUSTERED INDEX [IX_ml_scrape_pages_runId] ON [dbo].[ml_scrape_pages] ([runId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_scrape_runs_sourceUrl' AND object_id = OBJECT_ID(N'dbo.ml_scrape_runs'))
CREATE NONCLUSTERED INDEX [IX_ml_scrape_runs_sourceUrl] ON [dbo].[ml_scrape_runs] ([sourceUrl]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_scrape_runs_startedAt' AND object_id = OBJECT_ID(N'dbo.ml_scrape_runs'))
CREATE NONCLUSTERED INDEX [IX_ml_scrape_runs_startedAt] ON [dbo].[ml_scrape_runs] ([startedAt]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_scrape_runs_status' AND object_id = OBJECT_ID(N'dbo.ml_scrape_runs'))
CREATE NONCLUSTERED INDEX [IX_ml_scrape_runs_status] ON [dbo].[ml_scrape_runs] ([status]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_search_results_item' AND object_id = OBJECT_ID(N'dbo.ml_search_results'))
CREATE NONCLUSTERED INDEX [IX_ml_search_results_item] ON [dbo].[ml_search_results] ([item_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_ml_search_results_run_item' AND object_id = OBJECT_ID(N'dbo.ml_search_results'))
CREATE UNIQUE NONCLUSTERED INDEX [UX_ml_search_results_run_item] ON [dbo].[ml_search_results] ([search_run_id], [item_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_search_runs_site_query_created' AND object_id = OBJECT_ID(N'dbo.ml_search_runs'))
CREATE NONCLUSTERED INDEX [IX_ml_search_runs_site_query_created] ON [dbo].[ml_search_runs] ([site_id], [query_text], [created_at] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ml_search_runs_status_created' AND object_id = OBJECT_ID(N'dbo.ml_search_runs'))
CREATE NONCLUSTERED INDEX [IX_ml_search_runs_status_created] ON [dbo].[ml_search_runs] ([status], [created_at] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_NotificationDeliveries_PushNotificationId' AND object_id = OBJECT_ID(N'dbo.NotificationDeliveries'))
CREATE NONCLUSTERED INDEX [IX_NotificationDeliveries_PushNotificationId] ON [dbo].[NotificationDeliveries] ([pushNotificationId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_NotificationDeliveries_UserId' AND object_id = OBJECT_ID(N'dbo.NotificationDeliveries'))
CREATE NONCLUSTERED INDEX [IX_NotificationDeliveries_UserId] ON [dbo].[NotificationDeliveries] ([userId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_opportunities_filters' AND object_id = OBJECT_ID(N'dbo.opportunities'))
CREATE NONCLUSTERED INDEX [IX_opportunities_filters] ON [dbo].[opportunities] ([status], [channel], [roi] DESC, [netMarginUsd] DESC, [calculatedAt] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_opportunities_filters_v2' AND object_id = OBJECT_ID(N'dbo.opportunities'))
CREATE NONCLUSTERED INDEX [IX_opportunities_filters_v2] ON [dbo].[opportunities] ([status], [channel], [market], [roi] DESC, [netMarginUsd] DESC, [calculatedAt] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_opportunities_unified' AND object_id = OBJECT_ID(N'dbo.opportunities'))
CREATE NONCLUSTERED INDEX [IX_opportunities_unified] ON [dbo].[opportunities] ([unifiedProductId], [calculatedAt] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_paymentIntents_companyId' AND object_id = OBJECT_ID(N'dbo.paymentIntents'))
CREATE NONCLUSTERED INDEX [IX_paymentIntents_companyId] ON [dbo].[paymentIntents] ([companyId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_paymentIntents_expirySweep' AND object_id = OBJECT_ID(N'dbo.paymentIntents'))
CREATE NONCLUSTERED INDEX [IX_paymentIntents_expirySweep] ON [dbo].[paymentIntents] ([status], [expiresAt]) WHERE ([status]='OPEN');
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_paymentIntents_installmentId' AND object_id = OBJECT_ID(N'dbo.paymentIntents'))
CREATE NONCLUSTERED INDEX [IX_paymentIntents_installmentId] ON [dbo].[paymentIntents] ([installmentId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_paymentIntents_loanId' AND object_id = OBJECT_ID(N'dbo.paymentIntents'))
CREATE NONCLUSTERED INDEX [IX_paymentIntents_loanId] ON [dbo].[paymentIntents] ([loanId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_paymentIntents_openFunding' AND object_id = OBJECT_ID(N'dbo.paymentIntents'))
CREATE UNIQUE NONCLUSTERED INDEX [UQ_paymentIntents_openFunding] ON [dbo].[paymentIntents] ([companyId], [loanId]) WHERE ([intentType]='FUNDING' AND [status]='OPEN');
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_productMatches_unified' AND object_id = OBJECT_ID(N'dbo.productMatches'))
CREATE NONCLUSTERED INDEX [IX_productMatches_unified] ON [dbo].[productMatches] ([unifiedProductId], [entityType], [entityId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_products_company_product' AND object_id = OBJECT_ID(N'dbo.products'))
CREATE NONCLUSTERED INDEX [IX_products_company_product] ON [dbo].[products] ([companyId], [productId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_promotion_targets_promo' AND object_id = OBJECT_ID(N'dbo.promotion_targets'))
CREATE NONCLUSTERED INDEX [IX_promotion_targets_promo] ON [dbo].[promotion_targets] ([promotionId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_promotions_company_code' AND object_id = OBJECT_ID(N'dbo.promotions'))
CREATE UNIQUE NONCLUSTERED INDEX [UX_promotions_company_code] ON [dbo].[promotions] ([companyId], [code]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_publishJobs_status_retry' AND object_id = OBJECT_ID(N'dbo.publishJobs'))
CREATE NONCLUSTERED INDEX [IX_publishJobs_status_retry] ON [dbo].[publishJobs] ([status], [nextRetryAt]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PushNotifications_CompanyId' AND object_id = OBJECT_ID(N'dbo.PushNotifications'))
CREATE NONCLUSTERED INDEX [IX_PushNotifications_CompanyId] ON [dbo].[PushNotifications] ([companyId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PushNotifications_IsRead' AND object_id = OBJECT_ID(N'dbo.PushNotifications'))
CREATE NONCLUSTERED INDEX [IX_PushNotifications_IsRead] ON [dbo].[PushNotifications] ([isRead]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PushNotifications_IsSent' AND object_id = OBJECT_ID(N'dbo.PushNotifications'))
CREATE NONCLUSTERED INDEX [IX_PushNotifications_IsSent] ON [dbo].[PushNotifications] ([isSent]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PushNotifications_NotificationType' AND object_id = OBJECT_ID(N'dbo.PushNotifications'))
CREATE NONCLUSTERED INDEX [IX_PushNotifications_NotificationType] ON [dbo].[PushNotifications] ([notificationType]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PushNotifications_Priority' AND object_id = OBJECT_ID(N'dbo.PushNotifications'))
CREATE NONCLUSTERED INDEX [IX_PushNotifications_Priority] ON [dbo].[PushNotifications] ([priority]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PushNotifications_ScheduledAt' AND object_id = OBJECT_ID(N'dbo.PushNotifications'))
CREATE NONCLUSTERED INDEX [IX_PushNotifications_ScheduledAt] ON [dbo].[PushNotifications] ([scheduledAt]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PushNotifications_SentAt' AND object_id = OBJECT_ID(N'dbo.PushNotifications'))
CREATE NONCLUSTERED INDEX [IX_PushNotifications_SentAt] ON [dbo].[PushNotifications] ([sentAt]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PushNotifications_TargetCompanyId' AND object_id = OBJECT_ID(N'dbo.PushNotifications'))
CREATE NONCLUSTERED INDEX [IX_PushNotifications_TargetCompanyId] ON [dbo].[PushNotifications] ([targetCompanyId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PushNotifications_TargetRoleId' AND object_id = OBJECT_ID(N'dbo.PushNotifications'))
CREATE NONCLUSTERED INDEX [IX_PushNotifications_TargetRoleId] ON [dbo].[PushNotifications] ([targetRoleId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PushNotifications_TargetType' AND object_id = OBJECT_ID(N'dbo.PushNotifications'))
CREATE NONCLUSTERED INDEX [IX_PushNotifications_TargetType] ON [dbo].[PushNotifications] ([targetType]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PushNotifications_TargetUserId' AND object_id = OBJECT_ID(N'dbo.PushNotifications'))
CREATE NONCLUSTERED INDEX [IX_PushNotifications_TargetUserId] ON [dbo].[PushNotifications] ([targetUserId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sellListings_channel_market_ts' AND object_id = OBJECT_ID(N'dbo.sellListings'))
CREATE NONCLUSTERED INDEX [IX_sellListings_channel_market_ts] ON [dbo].[sellListings] ([channel], [market], [listingTimestamp] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sellListings_channel_ts' AND object_id = OBJECT_ID(N'dbo.sellListings'))
CREATE NONCLUSTERED INDEX [IX_sellListings_channel_ts] ON [dbo].[sellListings] ([channel], [listingTimestamp] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sellListings_unified_ts' AND object_id = OBJECT_ID(N'dbo.sellListings'))
CREATE NONCLUSTERED INDEX [IX_sellListings_unified_ts] ON [dbo].[sellListings] ([unifiedProductId], [listingTimestamp] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_sellListings_daily' AND object_id = OBJECT_ID(N'dbo.sellListings'))
CREATE UNIQUE NONCLUSTERED INDEX [UX_sellListings_daily] ON [dbo].[sellListings] ([channel], [market], [channelItemId], [listingDate]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Suppliers_CompanyId' AND object_id = OBJECT_ID(N'dbo.Suppliers'))
CREATE NONCLUSTERED INDEX [IX_Suppliers_CompanyId] ON [dbo].[Suppliers] ([companyId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Suppliers_SupplierName' AND object_id = OBJECT_ID(N'dbo.Suppliers'))
CREATE NONCLUSTERED INDEX [IX_Suppliers_SupplierName] ON [dbo].[Suppliers] ([supplierName]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Suppliers_Email_CompanyId' AND object_id = OBJECT_ID(N'dbo.Suppliers'))
CREATE UNIQUE NONCLUSTERED INDEX [UQ_Suppliers_Email_CompanyId] ON [dbo].[Suppliers] ([email], [companyId]) WHERE ([email] IS NOT NULL);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Suppliers_Phone_CompanyId' AND object_id = OBJECT_ID(N'dbo.Suppliers'))
CREATE UNIQUE NONCLUSTERED INDEX [UQ_Suppliers_Phone_CompanyId] ON [dbo].[Suppliers] ([phone], [companyId]) WHERE ([phone] IS NOT NULL);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_transfers_company_client' AND object_id = OBJECT_ID(N'dbo.transfers'))
CREATE NONCLUSTERED INDEX [IX_transfers_company_client] ON [dbo].[transfers] ([companyId], [toClientId], [created_At] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_transfers_status' AND object_id = OBJECT_ID(N'dbo.transfers'))
CREATE NONCLUSTERED INDEX [IX_transfers_status] ON [dbo].[transfers] ([status]) INCLUDE ([companyId], [created_At]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_transfers_idem' AND object_id = OBJECT_ID(N'dbo.transfers'))
CREATE UNIQUE NONCLUSTERED INDEX [UQ_transfers_idem] ON [dbo].[transfers] ([companyId], [idempotencyKey]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_unifiedProducts_eanupc' AND object_id = OBJECT_ID(N'dbo.unifiedProducts'))
CREATE NONCLUSTERED INDEX [IX_unifiedProducts_eanupc] ON [dbo].[unifiedProducts] ([ean_upc]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_walletTransactions_client' AND object_id = OBJECT_ID(N'dbo.walletTransactions'))
CREATE NONCLUSTERED INDEX [IX_walletTransactions_client] ON [dbo].[walletTransactions] ([companyId], [clientId], [entryId] DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_walletTransactions_reference' AND object_id = OBJECT_ID(N'dbo.walletTransactions'))
CREATE NONCLUSTERED INDEX [IX_walletTransactions_reference] ON [dbo].[walletTransactions] ([referenceType], [referenceId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_walletTransactions_idem' AND object_id = OBJECT_ID(N'dbo.walletTransactions'))
CREATE UNIQUE NONCLUSTERED INDEX [UQ_walletTransactions_idem] ON [dbo].[walletTransactions] ([companyId], [idempotencyKey]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_workflowLogs_company_name' AND object_id = OBJECT_ID(N'dbo.workflowLogs'))
CREATE NONCLUSTERED INDEX [IX_workflowLogs_company_name] ON [dbo].[workflowLogs] ([companyId], [workflowName], [created_At]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_workflowLogs_correlationId' AND object_id = OBJECT_ID(N'dbo.workflowLogs'))
CREATE NONCLUSTERED INDEX [IX_workflowLogs_correlationId] ON [dbo].[workflowLogs] ([correlationId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_workflowLogs_workflowId' AND object_id = OBJECT_ID(N'dbo.workflowLogs'))
CREATE NONCLUSTERED INDEX [IX_workflowLogs_workflowId] ON [dbo].[workflowLogs] ([workflowId], [created_At]);
GO

/* ---------- FOREIGN KEYS ---------- */

IF OBJECT_ID(N'dbo.FK_ClientFaceRecognitions_Company', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[ClientFaceRecognitions] WITH CHECK ADD CONSTRAINT [FK_ClientFaceRecognitions_Company] FOREIGN KEY ([companyId]) REFERENCES [dbo].[companies] ([companyId]);
END
GO
ALTER TABLE [dbo].[ClientFaceRecognitions] CHECK CONSTRAINT [FK_ClientFaceRecognitions_Company];
GO

IF OBJECT_ID(N'dbo.FK_NotificationDeliveries_PushNotifications', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[NotificationDeliveries] WITH CHECK ADD CONSTRAINT [FK_NotificationDeliveries_PushNotifications] FOREIGN KEY ([pushNotificationId]) REFERENCES [dbo].[PushNotifications] ([pushNotificationId]);
END
GO
ALTER TABLE [dbo].[NotificationDeliveries] CHECK CONSTRAINT [FK_NotificationDeliveries_PushNotifications];
GO

IF OBJECT_ID(N'dbo.FK__Suppliers__compa__4AF81212', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[Suppliers] WITH CHECK ADD CONSTRAINT [FK__Suppliers__compa__4AF81212] FOREIGN KEY ([companyId]) REFERENCES [dbo].[companies] ([companyId]);
END
GO
ALTER TABLE [dbo].[Suppliers] CHECK CONSTRAINT [FK__Suppliers__compa__4AF81212];
GO

IF OBJECT_ID(N'dbo.FK__company_m__compa__1A54DAB7', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[company_modules] WITH CHECK ADD CONSTRAINT [FK__company_m__compa__1A54DAB7] FOREIGN KEY ([companyId]) REFERENCES [dbo].[companies] ([companyId]);
END
GO
ALTER TABLE [dbo].[company_modules] CHECK CONSTRAINT [FK__company_m__compa__1A54DAB7];
GO

IF OBJECT_ID(N'dbo.FK__company_m__modul__1B48FEF0', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[company_modules] WITH CHECK ADD CONSTRAINT [FK__company_m__modul__1B48FEF0] FOREIGN KEY ([moduleId]) REFERENCES [dbo].[modules] ([moduleId]);
END
GO
ALTER TABLE [dbo].[company_modules] CHECK CONSTRAINT [FK__company_m__modul__1B48FEF0];
GO

IF OBJECT_ID(N'dbo.FK__productOp__produ__1975C517', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[productOptionChoices] WITH CHECK ADD CONSTRAINT [FK__productOp__produ__1975C517] FOREIGN KEY ([productOptionId]) REFERENCES [dbo].[productOptions] ([productOptionId]);
END
GO
ALTER TABLE [dbo].[productOptionChoices] CHECK CONSTRAINT [FK__productOp__produ__1975C517];
GO

IF OBJECT_ID(N'dbo.FK__role_perm__permi__0C06BB60', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[role_permissions] WITH CHECK ADD CONSTRAINT [FK__role_perm__permi__0C06BB60] FOREIGN KEY ([permissionId]) REFERENCES [dbo].[permissions] ([permissionId]);
END
GO
ALTER TABLE [dbo].[role_permissions] CHECK CONSTRAINT [FK__role_perm__permi__0C06BB60];
GO

IF OBJECT_ID(N'dbo.FK__role_perm__roleI__0B129727', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[role_permissions] WITH CHECK ADD CONSTRAINT [FK__role_perm__roleI__0B129727] FOREIGN KEY ([roleId]) REFERENCES [dbo].[roles] ([roleId]);
END
GO
ALTER TABLE [dbo].[role_permissions] CHECK CONSTRAINT [FK__role_perm__roleI__0B129727];
GO

IF OBJECT_ID(N'dbo.FK_buyOffers_unifiedProducts', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[buyOffers] WITH CHECK ADD CONSTRAINT [FK_buyOffers_unifiedProducts] FOREIGN KEY ([unifiedProductId]) REFERENCES [dbo].[unifiedProducts] ([unifiedProductId]);
END
GO
ALTER TABLE [dbo].[buyOffers] CHECK CONSTRAINT [FK_buyOffers_unifiedProducts];
GO

IF OBJECT_ID(N'dbo.FK_cashRegisterMovements_income', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[cashRegisterMovements] WITH CHECK ADD CONSTRAINT [FK_cashRegisterMovements_income] FOREIGN KEY ([incomeId]) REFERENCES [dbo].[income] ([incomeId]);
END
GO
ALTER TABLE [dbo].[cashRegisterMovements] CHECK CONSTRAINT [FK_cashRegisterMovements_income];
GO

IF OBJECT_ID(N'dbo.FK_cashRegisterMovements_session', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[cashRegisterMovements] WITH CHECK ADD CONSTRAINT [FK_cashRegisterMovements_session] FOREIGN KEY ([sessionId]) REFERENCES [dbo].[cashRegisterSessions] ([sessionId]);
END
GO
ALTER TABLE [dbo].[cashRegisterMovements] CHECK CONSTRAINT [FK_cashRegisterMovements_session];
GO

IF OBJECT_ID(N'dbo.FK_clientFollowUps_status', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[clientFollowUps] WITH CHECK ADD CONSTRAINT [FK_clientFollowUps_status] FOREIGN KEY ([riskStatus]) REFERENCES [dbo].[clientFollowUps_status] ([riskStatus]);
END
GO
ALTER TABLE [dbo].[clientFollowUps] CHECK CONSTRAINT [FK_clientFollowUps_status];
GO

IF OBJECT_ID(N'dbo.FK_expenseDetails_expense', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[expenseDetails] WITH CHECK ADD CONSTRAINT [FK_expenseDetails_expense] FOREIGN KEY ([expenseId]) REFERENCES [dbo].[expenses] ([expenseId]) ON DELETE CASCADE;
END
GO
ALTER TABLE [dbo].[expenseDetails] CHECK CONSTRAINT [FK_expenseDetails_expense];
GO

IF OBJECT_ID(N'dbo.FK_incomeDetails_income', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[incomeDetails] WITH CHECK ADD CONSTRAINT [FK_incomeDetails_income] FOREIGN KEY ([incomeId]) REFERENCES [dbo].[income] ([incomeId]) ON DELETE CASCADE;
END
GO
ALTER TABLE [dbo].[incomeDetails] CHECK CONSTRAINT [FK_incomeDetails_income];
GO

IF OBJECT_ID(N'dbo.FK_listingDrafts_unifiedProducts', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[listingDrafts] WITH CHECK ADD CONSTRAINT [FK_listingDrafts_unifiedProducts] FOREIGN KEY ([unifiedProductId]) REFERENCES [dbo].[unifiedProducts] ([unifiedProductId]);
END
GO
ALTER TABLE [dbo].[listingDrafts] CHECK CONSTRAINT [FK_listingDrafts_unifiedProducts];
GO

IF OBJECT_ID(N'dbo.FK_loanProposals_status', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[loanProposals] WITH CHECK ADD CONSTRAINT [FK_loanProposals_status] FOREIGN KEY ([status]) REFERENCES [dbo].[loanProposals_status] ([statusCode]);
END
GO
ALTER TABLE [dbo].[loanProposals] CHECK CONSTRAINT [FK_loanProposals_status];
GO

IF OBJECT_ID(N'dbo.FK_marketplaceOrders_unifiedProducts', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[marketplaceOrders] WITH CHECK ADD CONSTRAINT [FK_marketplaceOrders_unifiedProducts] FOREIGN KEY ([unifiedProductId]) REFERENCES [dbo].[unifiedProducts] ([unifiedProductId]);
END
GO
ALTER TABLE [dbo].[marketplaceOrders] CHECK CONSTRAINT [FK_marketplaceOrders_unifiedProducts];
GO

IF OBJECT_ID(N'dbo.FK_messageTickets_orders', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[messageTickets] WITH CHECK ADD CONSTRAINT [FK_messageTickets_orders] FOREIGN KEY ([marketplaceOrderId]) REFERENCES [dbo].[marketplaceOrders] ([marketplaceOrderId]);
END
GO
ALTER TABLE [dbo].[messageTickets] CHECK CONSTRAINT [FK_messageTickets_orders];
GO

IF OBJECT_ID(N'dbo.FK_ml_scrape_items_pageId', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[ml_scrape_items] WITH CHECK ADD CONSTRAINT [FK_ml_scrape_items_pageId] FOREIGN KEY ([pageId]) REFERENCES [dbo].[ml_scrape_pages] ([pageId]);
END
GO
ALTER TABLE [dbo].[ml_scrape_items] CHECK CONSTRAINT [FK_ml_scrape_items_pageId];
GO

IF OBJECT_ID(N'dbo.FK_ml_scrape_items_runId', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[ml_scrape_items] WITH CHECK ADD CONSTRAINT [FK_ml_scrape_items_runId] FOREIGN KEY ([runId]) REFERENCES [dbo].[ml_scrape_runs] ([runId]);
END
GO
ALTER TABLE [dbo].[ml_scrape_items] CHECK CONSTRAINT [FK_ml_scrape_items_runId];
GO

IF OBJECT_ID(N'dbo.FK_ml_scrape_pages_runId', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[ml_scrape_pages] WITH CHECK ADD CONSTRAINT [FK_ml_scrape_pages_runId] FOREIGN KEY ([runId]) REFERENCES [dbo].[ml_scrape_runs] ([runId]);
END
GO
ALTER TABLE [dbo].[ml_scrape_pages] CHECK CONSTRAINT [FK_ml_scrape_pages_runId];
GO

IF OBJECT_ID(N'dbo.FK_ml_search_results_run', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[ml_search_results] WITH CHECK ADD CONSTRAINT [FK_ml_search_results_run] FOREIGN KEY ([search_run_id]) REFERENCES [dbo].[ml_search_runs] ([search_run_id]) ON DELETE CASCADE;
END
GO
ALTER TABLE [dbo].[ml_search_results] CHECK CONSTRAINT [FK_ml_search_results_run];
GO

IF OBJECT_ID(N'dbo.FK_opportunities_buyOffers', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[opportunities] WITH CHECK ADD CONSTRAINT [FK_opportunities_buyOffers] FOREIGN KEY ([buyOfferId]) REFERENCES [dbo].[buyOffers] ([buyOfferId]);
END
GO
ALTER TABLE [dbo].[opportunities] CHECK CONSTRAINT [FK_opportunities_buyOffers];
GO

IF OBJECT_ID(N'dbo.FK_opportunities_sellListings', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[opportunities] WITH CHECK ADD CONSTRAINT [FK_opportunities_sellListings] FOREIGN KEY ([sellListingId]) REFERENCES [dbo].[sellListings] ([sellListingId]);
END
GO
ALTER TABLE [dbo].[opportunities] CHECK CONSTRAINT [FK_opportunities_sellListings];
GO

IF OBJECT_ID(N'dbo.FK_opportunities_unifiedProducts', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[opportunities] WITH CHECK ADD CONSTRAINT [FK_opportunities_unifiedProducts] FOREIGN KEY ([unifiedProductId]) REFERENCES [dbo].[unifiedProducts] ([unifiedProductId]);
END
GO
ALTER TABLE [dbo].[opportunities] CHECK CONSTRAINT [FK_opportunities_unifiedProducts];
GO

IF OBJECT_ID(N'dbo.FK_paymentIntents_bankAccountSnapshots', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[paymentIntents] WITH CHECK ADD CONSTRAINT [FK_paymentIntents_bankAccountSnapshots] FOREIGN KEY ([beneficiarySnapshotId]) REFERENCES [dbo].[bankAccountSnapshots] ([snapshotId]);
END
GO
ALTER TABLE [dbo].[paymentIntents] CHECK CONSTRAINT [FK_paymentIntents_bankAccountSnapshots];
GO

IF OBJECT_ID(N'dbo.FK_paymentIntents_loanInstallments', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[paymentIntents] WITH CHECK ADD CONSTRAINT [FK_paymentIntents_loanInstallments] FOREIGN KEY ([installmentId]) REFERENCES [dbo].[loanInstallments] ([installmentId]);
END
GO
ALTER TABLE [dbo].[paymentIntents] CHECK CONSTRAINT [FK_paymentIntents_loanInstallments];
GO

IF OBJECT_ID(N'dbo.FK_paymentIntents_loans', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[paymentIntents] WITH CHECK ADD CONSTRAINT [FK_paymentIntents_loans] FOREIGN KEY ([loanId]) REFERENCES [dbo].[loans] ([loanId]);
END
GO
ALTER TABLE [dbo].[paymentIntents] CHECK CONSTRAINT [FK_paymentIntents_loans];
GO

IF OBJECT_ID(N'dbo.FK_paymentIntents_payeeClients', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[paymentIntents] WITH CHECK ADD CONSTRAINT [FK_paymentIntents_payeeClients] FOREIGN KEY ([payeeClientId]) REFERENCES [dbo].[clients] ([clientId]);
END
GO
ALTER TABLE [dbo].[paymentIntents] CHECK CONSTRAINT [FK_paymentIntents_payeeClients];
GO

IF OBJECT_ID(N'dbo.FK_paymentIntents_payerClients', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[paymentIntents] WITH CHECK ADD CONSTRAINT [FK_paymentIntents_payerClients] FOREIGN KEY ([payerClientId]) REFERENCES [dbo].[clients] ([clientId]);
END
GO
ALTER TABLE [dbo].[paymentIntents] CHECK CONSTRAINT [FK_paymentIntents_payerClients];
GO

IF OBJECT_ID(N'dbo.FK_permissions_modules', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[permissions] WITH CHECK ADD CONSTRAINT [FK_permissions_modules] FOREIGN KEY ([moduleId]) REFERENCES [dbo].[modules] ([moduleId]);
END
GO
ALTER TABLE [dbo].[permissions] CHECK CONSTRAINT [FK_permissions_modules];
GO

IF OBJECT_ID(N'dbo.FK_procurement_orders', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[procurementJobs] WITH CHECK ADD CONSTRAINT [FK_procurement_orders] FOREIGN KEY ([marketplaceOrderId]) REFERENCES [dbo].[marketplaceOrders] ([marketplaceOrderId]);
END
GO
ALTER TABLE [dbo].[procurementJobs] CHECK CONSTRAINT [FK_procurement_orders];
GO

IF OBJECT_ID(N'dbo.FK_productMatches_unifiedProducts', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[productMatches] WITH CHECK ADD CONSTRAINT [FK_productMatches_unifiedProducts] FOREIGN KEY ([unifiedProductId]) REFERENCES [dbo].[unifiedProducts] ([unifiedProductId]);
END
GO
ALTER TABLE [dbo].[productMatches] CHECK CONSTRAINT [FK_productMatches_unifiedProducts];
GO

IF OBJECT_ID(N'dbo.FK_promotion_targets_promotions', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[promotion_targets] WITH CHECK ADD CONSTRAINT [FK_promotion_targets_promotions] FOREIGN KEY ([promotionId]) REFERENCES [dbo].[promotions] ([promotionId]);
END
GO
ALTER TABLE [dbo].[promotion_targets] CHECK CONSTRAINT [FK_promotion_targets_promotions];
GO

IF OBJECT_ID(N'dbo.FK_publishJobs_listingDrafts', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[publishJobs] WITH CHECK ADD CONSTRAINT [FK_publishJobs_listingDrafts] FOREIGN KEY ([draftId]) REFERENCES [dbo].[listingDrafts] ([draftId]);
END
GO
ALTER TABLE [dbo].[publishJobs] CHECK CONSTRAINT [FK_publishJobs_listingDrafts];
GO

IF OBJECT_ID(N'dbo.FK_sellListingAttributes_sellListings', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[sellListingAttributes] WITH CHECK ADD CONSTRAINT [FK_sellListingAttributes_sellListings] FOREIGN KEY ([sellListingId]) REFERENCES [dbo].[sellListings] ([sellListingId]);
END
GO
ALTER TABLE [dbo].[sellListingAttributes] CHECK CONSTRAINT [FK_sellListingAttributes_sellListings];
GO

IF OBJECT_ID(N'dbo.FK_sellListings_scrapeItemId', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[sellListings] WITH CHECK ADD CONSTRAINT [FK_sellListings_scrapeItemId] FOREIGN KEY ([scrapeItemId]) REFERENCES [dbo].[ml_scrape_items] ([scrapeItemId]);
END
GO
ALTER TABLE [dbo].[sellListings] CHECK CONSTRAINT [FK_sellListings_scrapeItemId];
GO

IF OBJECT_ID(N'dbo.FK_sellListings_unifiedProducts', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[sellListings] WITH CHECK ADD CONSTRAINT [FK_sellListings_unifiedProducts] FOREIGN KEY ([unifiedProductId]) REFERENCES [dbo].[unifiedProducts] ([unifiedProductId]);
END
GO
ALTER TABLE [dbo].[sellListings] CHECK CONSTRAINT [FK_sellListings_unifiedProducts];
GO

IF OBJECT_ID(N'dbo.FK_shipments_orders', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[shipments] WITH CHECK ADD CONSTRAINT [FK_shipments_orders] FOREIGN KEY ([marketplaceOrderId]) REFERENCES [dbo].[marketplaceOrders] ([marketplaceOrderId]);
END
GO
ALTER TABLE [dbo].[shipments] CHECK CONSTRAINT [FK_shipments_orders];
GO

IF OBJECT_ID(N'dbo.FK_transfers_bankAccount', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[transfers] WITH CHECK ADD CONSTRAINT [FK_transfers_bankAccount] FOREIGN KEY ([toBankAccountId]) REFERENCES [dbo].[bankAccounts] ([bankAccountId]);
END
GO
ALTER TABLE [dbo].[transfers] CHECK CONSTRAINT [FK_transfers_bankAccount];
GO

IF OBJECT_ID(N'dbo.FK_transfers_status', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[transfers] WITH CHECK ADD CONSTRAINT [FK_transfers_status] FOREIGN KEY ([status]) REFERENCES [dbo].[transfers_status] ([statusCode]);
END
GO
ALTER TABLE [dbo].[transfers] CHECK CONSTRAINT [FK_transfers_status];
GO

IF OBJECT_ID(N'dbo.FK_users_companies', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[users] WITH CHECK ADD CONSTRAINT [FK_users_companies] FOREIGN KEY ([companyId]) REFERENCES [dbo].[companies] ([companyId]);
END
GO
ALTER TABLE [dbo].[users] CHECK CONSTRAINT [FK_users_companies];
GO

IF OBJECT_ID(N'dbo.FK_users_companies_roles', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[userCompanies] WITH CHECK ADD CONSTRAINT [FK_users_companies_roles] FOREIGN KEY ([roleId]) REFERENCES [dbo].[roles] ([roleId]);
END
GO
ALTER TABLE [dbo].[userCompanies] CHECK CONSTRAINT [FK_users_companies_roles];
GO

IF OBJECT_ID(N'dbo.FK_walletTransactions_entryType', N'F') IS NULL
BEGIN
ALTER TABLE [dbo].[walletTransactions] WITH CHECK ADD CONSTRAINT [FK_walletTransactions_entryType] FOREIGN KEY ([entryType]) REFERENCES [dbo].[walletTransactions_entryType] ([entryType]);
END
GO
ALTER TABLE [dbo].[walletTransactions] CHECK CONSTRAINT [FK_walletTransactions_entryType];
GO
