/* =============================================================================
   2026-11-18 — Seed of dbo.agents (catalog of LoanAgents_SmartLoans agents).

   Run AFTER the factory-generated dbo.agents table + SPs exist.
   Idempotent: MERGE on agentKey. Inserts missing agents and refreshes the
   descriptive columns of existing ones; never retires or deletes a row, and
   never touches status of a row that already exists (an admin may have
   retired it from the POS).

   Verified 2026-11-18 against LoanAgents_SmartLoans agents/__init__.py and the
   @app.post routes in main.py (development == origin/main for those files).
   Sub-agents are folded into the agent that owns the route:
     whatsapp_reservations ⊃ whatsapp_registration, whatsapp_campaign, whatsapp_topic
     orchestrator          ⊃ risk, recommendation, borrower, lender, negotiation
     analysis              ⊃ risk, recommendation
   Not seeded: business_intake (/intake/analyze, factory intake — not a POS
   agent) and support (runner defined, no route uses it).

   No secrets, no hosts: endpoint is the route path only.
   ============================================================================= */
SET NOCOUNT ON;

MERGE dbo.agents AS t
USING (VALUES
  -- agentKey, name, description, area, endpoint, model, customerFacing
  (N'whatsapp_reservations', N'Asistente de WhatsApp',
   N'Atiende a los clientes por WhatsApp: reservaciones, dudas del negocio, puntos y registro de clientes nuevos. Incluye los sub-agentes de registro, campaña y clasificación de temas.',
   N'whatsapp', N'/support/whatsapp-reservations', N'gemini-2.5-flash', 1),
  (N'whatsapp_insights', N'Análisis de conversaciones WhatsApp',
   N'Lee los mensajes de un periodo y resume qué piden los clientes y qué oportunidades hay, para el tablero del POS.',
   N'whatsapp', N'/support/whatsapp-insights', N'gemini-2.5-flash', 0),
  (N'pos_clients_support', N'Soporte POS: Clientes',
   N'Asistente de chat para el personal en el módulo de clientes; puede proponer dar de alta un cliente.',
   N'pos_support', N'/support/pos-clients', N'gemini-2.5-flash', 0),
  (N'pos_income_support', N'Soporte POS: Ingresos',
   N'Responde preguntas del personal sobre los ingresos registrados.',
   N'pos_support', N'/support/pos-income', N'gemini-2.5-flash', 0),
  (N'pos_expenses_support', N'Soporte POS: Egresos',
   N'Responde preguntas del personal sobre los egresos registrados.',
   N'pos_support', N'/support/pos-expenses', N'gemini-2.5-flash', 0),
  (N'pos_accounting_support', N'Soporte POS: Contabilidad',
   N'Responde preguntas del personal sobre la contabilidad (pólizas y catálogo de cuentas).',
   N'pos_support', N'/support/pos-accounting', N'gemini-2.5-flash', 0),
  (N'pos_rewards_support', N'Soporte de recompensas',
   N'Asistente para el cliente del negocio sobre sus puntos y recompensas.',
   N'pos_support', N'/support/pos-rewards', N'gemini-2.5-flash', 1),
  (N'order_triage', N'Resumen de órdenes',
   N'Resume las órdenes del día y señala las que llevan demasiado tiempo detenidas.',
   N'pos_support', N'/orders/triage-summary', N'gemini-2.5-flash', 0),
  (N'client_followup', N'Seguimiento de clientes',
   N'Lee el historial de seguimiento de un cliente y sugiere la siguiente acción.',
   N'pos_support', N'/clients/follow-up-suggestion', N'gemini-2.5-flash', 0),
  (N'cash_register', N'Revisión de corte de caja',
   N'Revisa el resumen del corte de caja diario y señala diferencias.',
   N'pos_support', N'/cash-register/review-closeout', N'gemini-2.5-flash', 0),
  (N'expense', N'Categorización de egresos',
   N'Sugiere la categoría de un egreso nuevo y detecta posibles duplicados.',
   N'pos_support', N'/expenses/categorize', N'gemini-2.5-flash', 0),
  (N'ticket_extraction', N'Lectura de tickets',
   N'Lee la foto de un ticket de compra y extrae sus datos para registrar el egreso.',
   N'extraction', N'/expenses/extract-ticket', N'gemini-2.5-flash', 0),
  (N'product_extraction', N'Lectura de etiquetas de producto',
   N'Lee las fotos de la etiqueta de un producto y extrae sus datos.',
   N'extraction', N'/products/extract-label', N'gemini-2.5-flash', 0),
  (N'product_web_lookup', N'Búsqueda de producto en la web',
   N'Busca en la web el producto que corresponde a una línea de ticket.',
   N'extraction', N'/products/web-lookup', N'gemini-2.5-flash', 0),
  (N'transfer_extraction', N'Lectura de comprobantes SPEI',
   N'Lee el monto, la clave de rastreo, la fecha y el banco de la foto de un comprobante SPEI.',
   N'extraction', N'/transfers/extract-evidence', N'gemini-2.5-flash', 0),
  (N'id_document', N'Lectura de INE',
   N'Lee las fotos de una INE y extrae los datos de identidad.',
   N'extraction', N'/extract-id-fields', N'gemini-2.5-flash', 0),
  (N'evidence_validation', N'Validación de comprobantes',
   N'Revisa la foto de un comprobante de transferencia contra el pago esperado.',
   N'loans', N'/validate-transfer-evidence', N'gemini-2.5-flash', 0),
  (N'face_validation', N'Validación facial',
   N'Revisa el conjunto de fotos de alta (posiciones de la cabeza y la INE). Su veredicto es orientativo.',
   N'loans', N'/validate-face', N'gemini-2.5-flash', 0),
  (N'contract', N'Contrato de préstamo',
   N'Cuando prestatario y prestamista acuerdan los términos, prepara el contrato.',
   N'loans', N'/contract', N'gemini-2.5-flash', 0),
  (N'analysis', N'Análisis de propuesta',
   N'Analiza una propuesta de préstamo: riesgo y recomendación.',
   N'loans', N'/analyze-proposal', N'gemini-2.5-flash', 0),
  (N'orchestrator', N'Negociación de préstamos',
   N'Flujo completo de negociación: riesgo, recomendación, prestatario, prestamista y negociación.',
   N'loans', N'/negotiate', N'gemini-2.5-flash', 0),
  (N'voice_secretary', N'Secretaria de voz',
   N'Asistente telefónico: llama al cliente cuya orden está lista y acuerda la entrega o recolección.',
   N'other', N'/voice/twilio-stream', N'gemini-2.5-flash-native-audio-latest', 1)
) AS s (agentKey, name, description, area, endpoint, model, customerFacing)
ON t.agentKey = s.agentKey
WHEN MATCHED THEN UPDATE SET
  t.name = s.name, t.description = s.description, t.area = s.area,
  t.endpoint = s.endpoint, t.model = s.model, t.customerFacing = s.customerFacing,
  t.updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET THEN
  INSERT (agentKey, name, description, area, endpoint, model, customerFacing, status)
  VALUES (s.agentKey, s.name, s.description, s.area, s.endpoint, s.model, s.customerFacing, N'activo');

SELECT agentKey, area, endpoint, status FROM dbo.agents ORDER BY area, agentKey;
