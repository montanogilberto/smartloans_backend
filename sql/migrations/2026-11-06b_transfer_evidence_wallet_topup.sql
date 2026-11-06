-- =============================================================================
-- transferEvidence: accepts the comprobante of a saldo top-up (RFC-010 R3).
-- referenceId is the clientId. UQ_transferEvidence_claveRastreo already keeps a
-- clave de rastreo from being used twice in a company, and sp_transferEvidence
-- needs no change: only FUNDING is cross-validated on create.
-- =============================================================================
ALTER TABLE dbo.transferEvidence DROP CONSTRAINT CK_transferEvidence_referenceType;
GO
ALTER TABLE dbo.transferEvidence ADD CONSTRAINT CK_transferEvidence_referenceType CHECK (
    referenceType IN ('FUNDING', 'INSTALLMENT', 'PARTIAL', 'PAYOFF', 'WALLET_TOPUP')
);
GO

-- Saldo is money the company owes its client until it is spent (RFC-009 P4):
-- a liability, not income. Added next to 2105 for every company with a chart.
INSERT INTO dbo.chartOfAccounts (companyId, code, name, accountType, normalBalance, parentAccountId, level, isPostable, isActive)
SELECT a.companyId, '2115', 'Anticipos de clientes', a.accountType, a.normalBalance, a.parentAccountId, a.level, 1, 1
FROM dbo.chartOfAccounts a
WHERE a.code = '2105'
  AND NOT EXISTS (SELECT 1 FROM dbo.chartOfAccounts x WHERE x.companyId = a.companyId AND x.code = '2115');
GO
