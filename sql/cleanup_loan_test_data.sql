-- ============================================================
-- LIMPIEZA DE DATOS DE PRUEBA DEL CICLO DE PRÉSTAMO
-- Reinicia el marketplace/dinero de prueba para correr el E2E
-- desde cero. CONSERVA: users, clients, KYC (ClientFaceRecognitions),
-- bankAccounts (CLABEs verificadas), savedPaymentMethods (tarjeta),
-- stripeConnectedAccounts, clientWallets y observabilidad.
-- Solo entorno de desarrollo — es un hard delete.
-- ============================================================

-- Orden por dependencias (hijos primero)
DELETE FROM loanInstallments;                                   -- cuotas de prueba
DELETE FROM loans            WHERE companyId IN (1, 1008);      -- préstamos huérfanos/prueba
DELETE FROM loanProposals    WHERE companyId IN (1, 1008);      -- propuestas
DELETE FROM loanOffers;                                         -- ofertas publicadas (test v1/v2/v3)
DELETE FROM loanMessages;                                       -- chat de prueba
DELETE FROM loanConversations;                                  --   (incluye conv con lenderId=0 y agente)
DELETE FROM walletTransactions WHERE companyId IN (1, 1008);    -- ledger SPEI de prueba → saldo $0
DELETE FROM transfers          WHERE companyId IN (1, 1008);    -- dispersiones MOCKSTP
DELETE FROM stripeTransactions WHERE companyId IN (1, 1008);    -- intentos de cargo fallidos/cancelados
DELETE FROM NotificationDeliveries
 WHERE pushNotificationId IN (SELECT pushNotificationId FROM PushNotifications WHERE companyId IN (1, 1008));
DELETE FROM PushNotifications  WHERE companyId IN (1, 1008);    -- notificaciones de prueba

-- Verificación post-limpieza
SELECT 'loans' AS tabla, COUNT(*) AS quedan FROM loans WHERE companyId IN (1,1008)
UNION ALL SELECT 'loanInstallments', COUNT(*) FROM loanInstallments
UNION ALL SELECT 'loanProposals', COUNT(*) FROM loanProposals WHERE companyId IN (1,1008)
UNION ALL SELECT 'loanOffers', COUNT(*) FROM loanOffers
UNION ALL SELECT 'loanConversations', COUNT(*) FROM loanConversations
UNION ALL SELECT 'loanMessages', COUNT(*) FROM loanMessages
UNION ALL SELECT 'walletTransactions', COUNT(*) FROM walletTransactions WHERE companyId IN (1,1008)
UNION ALL SELECT 'transfers', COUNT(*) FROM transfers WHERE companyId IN (1,1008)
UNION ALL SELECT 'stripeTransactions', COUNT(*) FROM stripeTransactions WHERE companyId IN (1,1008)
UNION ALL SELECT 'PushNotifications', COUNT(*) FROM PushNotifications WHERE companyId IN (1,1008)
-- Lo conservado (debe seguir igual):
UNION ALL SELECT '── bankAccounts (se conserva)', COUNT(*) FROM bankAccounts WHERE companyId = 1008
UNION ALL SELECT '── ClientFaceRecognitions (se conserva)', COUNT(*) FROM ClientFaceRecognitions WHERE companyId = 1008
UNION ALL SELECT '── savedPaymentMethods (se conserva)', COUNT(*) FROM savedPaymentMethods WHERE companyId = 1008
UNION ALL SELECT '── stripeConnectedAccounts (se conserva)', COUNT(*) FROM stripeConnectedAccounts WHERE companyId = 1008;
