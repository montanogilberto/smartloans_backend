-- ============================================================
-- SEMÁFORO DE OPERACIONES — ¿qué está funcionando?
-- Una fila por subsistema: volumen, último evento y estado derivado.
--   ✅ OK        = hay actividad real y sin señales de falla
--   ⚠️ ATENCIÓN  = existe pero con fallas/pendientes que revisar
--   ⛔ SIN DATOS = el subsistema aún no registra operaciones
-- Ejecutar completo (una sola SELECT). companyId 1008 = SmartLoans.
-- ============================================================
DECLARE @co INT = 1008;

SELECT * FROM (

-- ── 1. Onboarding / identidad ───────────────────────────────
SELECT '01 Registro de clientes' AS operacion,
       COUNT(*) AS total,
       CONVERT(NVARCHAR(19), MAX(created_At), 120) AS ultimo_evento,
       CASE WHEN COUNT(*) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END AS estado,
       CAST(NULL AS NVARCHAR(200)) AS detalle
FROM clients WHERE companyId = @co

UNION ALL
SELECT '02 KYC verificado (biometría)',
       SUM(CASE WHEN is_verified = 1 THEN 1 ELSE 0 END),
       CONVERT(NVARCHAR(19), MAX(updated_at), 120),
       CASE WHEN SUM(CASE WHEN is_verified = 1 THEN 1 ELSE 0 END) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END,
       CONCAT(SUM(CASE WHEN is_verified = 0 THEN 1 ELSE 0 END), ' sin verificar')
FROM ClientFaceRecognitions WHERE companyId = @co

UNION ALL
SELECT '03 Contratos + pagarés firmados',
       SUM(CASE WHEN contract_accepted = 1 AND pagare_accepted = 1 THEN 1 ELSE 0 END),
       CONVERT(NVARCHAR(19), MAX(contract_accepted_at), 120),
       CASE WHEN SUM(CASE WHEN contract_accepted = 1 AND pagare_accepted = 1 THEN 1 ELSE 0 END) > 0
            THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END, NULL
FROM ClientFaceRecognitions WHERE companyId = @co

-- ── 2. Rieles de dinero ─────────────────────────────────────
UNION ALL
SELECT '04 CLABEs verificadas (riel SPEI)',
       SUM(CASE WHEN isVerified = 1 THEN 1 ELSE 0 END),
       CONVERT(NVARCHAR(19), MAX(verifiedAt), 120),
       CASE WHEN SUM(CASE WHEN isVerified = 1 THEN 1 ELSE 0 END) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END,
       CONCAT(SUM(CASE WHEN isVerified = 0 AND isActive = 1 THEN 1 ELSE 0 END), ' pendientes de micro-depósito')
FROM bankAccounts WHERE companyId = @co

UNION ALL
SELECT '05 Stripe Connect (riel 2ª opción)',
       SUM(CASE WHEN payoutsEnabled = 1 THEN 1 ELSE 0 END),
       CONVERT(NVARCHAR(19), MAX(updated_at), 120),
       CASE WHEN SUM(CASE WHEN payoutsEnabled = 1 THEN 1 ELSE 0 END) > 0 THEN N'✅ OK' ELSE N'⚠️ ATENCIÓN' END,
       CONCAT(SUM(CASE WHEN identitySubmitted = 1 AND hasExternalAccount = 0 THEN 1 ELSE 0 END), ' con identidad pero sin banco')
FROM stripeConnectedAccounts WHERE companyId = @co

UNION ALL
SELECT '06 Tarjetas guardadas (cuotas)',
       COUNT(*), CONVERT(NVARCHAR(19), MAX(createdAt), 120),
       CASE WHEN COUNT(*) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END, NULL
FROM savedPaymentMethods WHERE companyId = @co

UNION ALL
SELECT '07 Ledger SPEI (walletTransactions)',
       COUNT(*), CONVERT(NVARCHAR(19), MAX(created_At), 120),
       CASE WHEN COUNT(*) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END,
       CONCAT('depósitos $', ISNULL(SUM(CASE WHEN entryType = 'DEPOSIT' THEN amountMXN END), 0),
              ' · retiros $', ISNULL(SUM(CASE WHEN entryType = 'WITHDRAWAL' THEN amountMXN END), 0),
              ' · reversas ', SUM(CASE WHEN entryType = 'REVERSAL' THEN 1 ELSE 0 END))
FROM walletTransactions WHERE companyId = @co

UNION ALL
SELECT '08 Transferencias SPEI (dispersión)',
       SUM(CASE WHEN status = 'settled' THEN 1 ELSE 0 END),
       CONVERT(NVARCHAR(19), MAX(created_At), 120),
       CASE WHEN SUM(CASE WHEN status = 'settled' THEN 1 ELSE 0 END) > 0
                 AND SUM(CASE WHEN status IN ('failed','returned') THEN 1 ELSE 0 END) = 0 THEN N'✅ OK'
            WHEN COUNT(*) > 0 THEN N'⚠️ ATENCIÓN' ELSE N'⛔ SIN DATOS' END,
       CONCAT(SUM(CASE WHEN status IN ('failed','returned') THEN 1 ELSE 0 END), ' fallidas · ',
              CASE WHEN MAX(CASE WHEN providerRef LIKE 'MOCKSTP%' THEN 1 ELSE 0 END) = 1
                   THEN 'MODO MOCK (sin dinero real)' ELSE 'riel real' END)
FROM transfers WHERE companyId = @co

UNION ALL
SELECT '09 Pagos Stripe (cargos tarjeta)',
       SUM(CASE WHEN status = 'succeeded' THEN 1 ELSE 0 END),
       CONVERT(NVARCHAR(19), MAX(created_At), 120),
       CASE WHEN SUM(CASE WHEN status = 'succeeded' THEN 1 ELSE 0 END) > 0 THEN N'✅ OK'
            WHEN COUNT(*) > 0 THEN N'⚠️ ATENCIÓN' ELSE N'⛔ SIN DATOS' END,
       CONCAT(SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END), ' fallidos de ', COUNT(*), ' intentos')
FROM stripeTransactions WHERE companyId = @co

-- ── 3. Marketplace / préstamos ──────────────────────────────
UNION ALL
SELECT '10 Ofertas de capital activas',
       SUM(CASE WHEN isActive = 1 AND (expiresAt IS NULL OR expiresAt > GETUTCDATE()) THEN 1 ELSE 0 END),
       CONVERT(NVARCHAR(19), MAX(created_At), 120),
       CASE WHEN SUM(CASE WHEN isActive = 1 THEN 1 ELSE 0 END) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END,
       CONCAT('capital publicado $', ISNULL(SUM(CASE WHEN isActive = 1 THEN availableCapital END), 0))
FROM loanOffers WHERE companyId = @co

UNION ALL
SELECT '11 Propuestas de préstamo',
       COUNT(*), CONVERT(NVARCHAR(19), MAX(created_At), 120),
       CASE WHEN COUNT(*) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END,
       CONCAT(SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END), ' pendientes · ',
              SUM(CASE WHEN status = 'accepted' THEN 1 ELSE 0 END), ' aceptadas')
FROM loanProposals WHERE companyId = @co

UNION ALL
SELECT '12 Préstamos',
       COUNT(*), CONVERT(NVARCHAR(19), MAX(created_At), 120),
       CASE WHEN COUNT(*) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END,
       CONCAT(SUM(CASE WHEN loanStatus = 'active' THEN 1 ELSE 0 END), ' activos · principal $',
              ISNULL(SUM(CASE WHEN loanStatus = 'active' THEN principalAmount END), 0))
FROM loans WHERE companyId = @co

UNION ALL
SELECT '13 Tabla de cuotas (installments)',
       COUNT(*), CONVERT(NVARCHAR(19), MAX(createdAt), 120),
       CASE WHEN COUNT(*) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END,
       CONCAT(SUM(CASE WHEN status = 'paid' THEN 1 ELSE 0 END), ' pagadas · ',
              SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END), ' pendientes')
FROM loanInstallments

-- ── 4. Comunicación ─────────────────────────────────────────
UNION ALL
SELECT '14 Chat de negociación',
       (SELECT COUNT(*) FROM loanMessages),
       CONVERT(NVARCHAR(19), MAX(lastMessageAt), 120),
       CASE WHEN COUNT(*) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END,
       CONCAT(COUNT(*), ' conversaciones (',
              SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END), ' abiertas)')
FROM loanConversations WHERE companyId = @co

UNION ALL
SELECT '15 Notificaciones push',
       COUNT(*), CONVERT(NVARCHAR(19), MAX(created_At), 120),
       CASE WHEN COUNT(*) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END, NULL
FROM PushNotifications WHERE companyId = @co

-- ── 5. Observabilidad ───────────────────────────────────────
UNION ALL
SELECT '16 Observabilidad: applicationLogs',
       COUNT(*), CONVERT(NVARCHAR(19), MAX(created_At), 120),
       CASE WHEN MAX(created_At) > DATEADD(HOUR, -24, GETUTCDATE()) THEN N'✅ OK'
            WHEN COUNT(*) > 0 THEN N'⚠️ ATENCIÓN' ELSE N'⛔ SIN DATOS' END,
       CONCAT(SUM(CASE WHEN [level] = 'ERROR' AND created_At > DATEADD(HOUR, -24, GETUTCDATE()) THEN 1 ELSE 0 END),
              ' errores en 24h · ',
              SUM(CASE WHEN [level] = 'SECURITY' THEN 1 ELSE 0 END), ' eventos SECURITY')
FROM applicationLogs

UNION ALL
SELECT '17 Observabilidad: workflowLogs',
       COUNT(*), CONVERT(NVARCHAR(19), MAX(created_At), 120),
       CASE WHEN COUNT(*) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END,
       CONCAT(COUNT(DISTINCT workflowId), ' workflows · ',
              SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END), ' pasos fallidos')
FROM workflowLogs

UNION ALL
SELECT '18 Observabilidad: integrationLogs',
       COUNT(*), CONVERT(NVARCHAR(19), MAX(created_At), 120),
       CASE WHEN COUNT(*) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END,
       CONCAT(SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END), ' llamadas externas fallidas')
FROM integrationLogs

UNION ALL
SELECT '19 Observabilidad: auditLogs',
       COUNT(*), CONVERT(NVARCHAR(19), MAX(created_At), 120),
       CASE WHEN COUNT(*) > 0 THEN N'✅ OK' ELSE N'⛔ SIN DATOS' END, NULL
FROM auditLogs

) board
ORDER BY operacion;
