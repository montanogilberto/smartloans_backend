-- ============================================================
-- LIMPIEZA DE DATOS DE PRUEBA DEL CICLO DE PRÉSTAMO (v2)
-- Reinicia el marketplace/dinero de prueba para correr el E2E de la
-- arquitectura no-custodial (SPEI directo) desde cero.
--
-- v2 extiende sql/cleanup_loan_test_data.sql (que quedó desactualizado
-- tras la migración 2026-08-11_add_capital_vocabulary) agregando las
-- tablas nuevas: loanContracts/loanContractSignatures, paymentIntents,
-- bankAccountSnapshots, loanDisbursements, legalCases/legalCaseNotes.
--
-- NO incluye los 4 logs de observabilidad (workflowLogs, auditLogs,
-- applicationLogs, integrationLogs) a propósito — un intento anterior
-- de este script SÍ los incluía (companyId IN (1,1008)) y tronó el
-- transaction log de la base ("transaction log is full due to
-- ACTIVE_TRANSACTION") porque applicationLogs tiene ~7k filas que en
-- su mayoría son registro/OTP/login de company 1008, NO actividad de
-- préstamos — companyId no es un filtro loan-specific en esas tablas.
-- Por memoria del proyecto, loans/Stripe/SPEI no emiten nada a esas 4
-- tablas todavía (gap de instrumentación pendiente en el backend), así
-- que no había nada útil que limpiar ahí de todos modos.
--
-- CONSERVA (sin cambios): users, clients, KYC (ClientFaceRecognitions),
-- bankAccounts (CLABEs verificadas), savedPaymentMethods (tarjeta),
-- stripeConnectedAccounts, clientWallets.
-- Solo entorno de desarrollo — es un hard delete, NO reversible.
-- Alcance: companyId IN (1, 1008) — igual que el script original;
-- estos son los únicos companyId bajo los que se han creado préstamos
-- (ver memoria "companyId 1008 vs 1 onboarding bug"), así que cubre
-- "todos los préstamos" sin arriesgar datos de otros tenants si el
-- mismo servidor SQL llega a alojar más companies en el futuro.
--
-- RECOMENDADO: tomar un backup/point-in-time restore de la base antes
-- de correr esto — es irreversible.
-- ============================================================

-- TRY/CATCH: si CUALQUIER DELETE falla (ej. transaction log lleno, deadlock,
-- violación de FK), el CATCH hace ROLLBACK automático — ya no depende de que
-- alguien corra ROLLBACK/KILL a mano después de un error a medias, como pasó
-- las dos veces anteriores con este script.
BEGIN TRY
    BEGIN TRANSACTION;

    -- Orden por dependencias (hijos primero) ------------------------------

    -- paymentIntents referencia loans, loanInstallments y bankAccountSnapshots
    -- (FK declaradas) — debe borrarse antes que las tres.
    DELETE FROM paymentIntents WHERE companyId IN (1, 1008);

    -- Firmas antes que el contrato que firman.
    DELETE FROM loanContractSignatures
     WHERE contractId IN (SELECT contractId FROM loanContracts WHERE companyId IN (1, 1008));

    -- Referencia loanId y (opcionalmente) contractId — antes de loanContracts.
    DELETE FROM loanDisbursements WHERE companyId IN (1, 1008);

    -- Notas antes que el caso legal que documentan.
    DELETE FROM legalCaseNotes
     WHERE caseId IN (SELECT caseId FROM legalCases WHERE companyId IN (1, 1008));
    DELETE FROM legalCases WHERE companyId IN (1, 1008);

    DELETE FROM loanContracts WHERE companyId IN (1, 1008);

    -- Snapshots de CLABE congelados por préstamo (después de paymentIntents,
    -- que los referencia vía FK).
    DELETE FROM bankAccountSnapshots WHERE companyId IN (1, 1008);

    DELETE FROM loanInstallments WHERE companyId IN (1, 1008);          -- cuotas de prueba
    DELETE FROM loans            WHERE companyId IN (1, 1008);          -- préstamos huérfanos/prueba
    DELETE FROM loanProposals    WHERE companyId IN (1, 1008);          -- propuestas
    DELETE FROM loanOffers;                                             -- ofertas publicadas (test v1/v2/v3)
    DELETE FROM loanMessages;                                           -- chat de prueba
    DELETE FROM loanConversations;                                      --   (incluye conv con lenderId=0 y agente)
    DELETE FROM walletTransactions WHERE companyId IN (1, 1008);        -- ledger SPEI de prueba → saldo $0
    DELETE FROM transfers          WHERE companyId IN (1, 1008);        -- dispersiones MOCKSTP
    DELETE FROM stripeTransactions WHERE companyId IN (1, 1008);        -- intentos de cargo fallidos/cancelados
    DELETE FROM NotificationDeliveries
     WHERE pushNotificationId IN (SELECT pushNotificationId FROM PushNotifications WHERE companyId IN (1, 1008));
    DELETE FROM PushNotifications  WHERE companyId IN (1, 1008);        -- notificaciones de prueba

    PRINT 'Todos los DELETE corrieron sin error. Revisa la verificación abajo y luego COMMIT o ROLLBACK a mano — la transacción sigue ABIERTA a propósito.';
END TRY
BEGIN CATCH
    DECLARE @ErrMsg     NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrNumber  INT            = ERROR_NUMBER();
    DECLARE @ErrLine    INT            = ERROR_LINE();

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    PRINT 'FALLÓ y se hizo ROLLBACK automático. No se guardó nada.';
    PRINT 'Error ' + CAST(@ErrNumber AS NVARCHAR) + ' en línea ' + CAST(@ErrLine AS NVARCHAR) + ': ' + @ErrMsg;

    -- Re-lanza el error para que la herramienta de query lo muestre también
    -- en rojo/como fallo, no solo en el PRINT.
    THROW;
END CATCH

-- Si llegaste aquí sin error, la transacción sigue abierta. Revisa el
-- resultado abajo ANTES de decidir COMMIT vs ROLLBACK.
-- COMMIT TRANSACTION;
-- ROLLBACK TRANSACTION;

-- Verificación post-limpieza (corre esto mientras la transacción sigue abierta)
SELECT 'loans' AS tabla, COUNT(*) AS quedan FROM loans WHERE companyId IN (1,1008)
UNION ALL SELECT 'loanInstallments', COUNT(*) FROM loanInstallments WHERE companyId IN (1,1008)
UNION ALL SELECT 'loanProposals', COUNT(*) FROM loanProposals WHERE companyId IN (1,1008)
UNION ALL SELECT 'loanOffers', COUNT(*) FROM loanOffers
UNION ALL SELECT 'loanConversations', COUNT(*) FROM loanConversations
UNION ALL SELECT 'loanMessages', COUNT(*) FROM loanMessages
UNION ALL SELECT 'walletTransactions', COUNT(*) FROM walletTransactions WHERE companyId IN (1,1008)
UNION ALL SELECT 'transfers', COUNT(*) FROM transfers WHERE companyId IN (1,1008)
UNION ALL SELECT 'stripeTransactions', COUNT(*) FROM stripeTransactions WHERE companyId IN (1,1008)
UNION ALL SELECT 'PushNotifications', COUNT(*) FROM PushNotifications WHERE companyId IN (1,1008)
UNION ALL SELECT 'paymentIntents', COUNT(*) FROM paymentIntents WHERE companyId IN (1,1008)
UNION ALL SELECT 'bankAccountSnapshots', COUNT(*) FROM bankAccountSnapshots WHERE companyId IN (1,1008)
UNION ALL SELECT 'loanContracts', COUNT(*) FROM loanContracts WHERE companyId IN (1,1008)
UNION ALL SELECT 'loanContractSignatures', COUNT(*) FROM loanContractSignatures
UNION ALL SELECT 'loanDisbursements', COUNT(*) FROM loanDisbursements WHERE companyId IN (1,1008)
UNION ALL SELECT 'legalCases', COUNT(*) FROM legalCases WHERE companyId IN (1,1008)
UNION ALL SELECT 'legalCaseNotes', COUNT(*) FROM legalCaseNotes
-- Lo conservado (debe seguir igual que antes de correr el script):
UNION ALL SELECT '── bankAccounts (se conserva)', COUNT(*) FROM bankAccounts WHERE companyId = 1008
UNION ALL SELECT '── ClientFaceRecognitions (se conserva)', COUNT(*) FROM ClientFaceRecognitions WHERE companyId = 1008
UNION ALL SELECT '── savedPaymentMethods (se conserva)', COUNT(*) FROM savedPaymentMethods WHERE companyId = 1008
UNION ALL SELECT '── stripeConnectedAccounts (se conserva)', COUNT(*) FROM stripeConnectedAccounts WHERE companyId = 1008
UNION ALL SELECT '── clientWallets (se conserva)', COUNT(*) FROM clientWallets WHERE companyId = 1008;

-- Descomenta UNA de estas dos líneas después de revisar el resultado:
-- COMMIT TRANSACTION;
-- ROLLBACK TRANSACTION;
