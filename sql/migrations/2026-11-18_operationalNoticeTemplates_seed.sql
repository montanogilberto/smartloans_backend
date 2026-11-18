-- =============================================================================
-- Seed: Biblioteca GMO de plantillas de avisos operativos.
-- Requires sql/sp_operationalNoticeTemplates.sql (table) to have run first.
--
-- Idempotent: MERGE on templateKey. Re-running refreshes the texts of the
-- platform templates; it never touches notices companies already published
-- (those store their own final text). Run once per environment (DEV → QA → PROD).
--
-- Placeholders the POS fills before publishing:
--   {nombre_empresa} (automatic) · {motivo} · {fecha_reapertura} · {horario} · {servicio_afectado}
-- =============================================================================
SET NOCOUNT ON;

MERGE [dbo].[operationalNoticeTemplates] AS t
USING (VALUES
  ('falta_agua', N'Falta de agua', N'Cierre por falta de suministro.', N'waterOutline', N'cierre',
   N'Cierre por falta de agua',
   N'¡Hola! 😊 Te informamos que hoy permaneceremos cerrados debido a {motivo}. Reanudaremos nuestras operaciones el {fecha_reapertura} en {horario}. ¡Gracias por tu comprensión!',
   N'motivo,fecha_reapertura,horario', 1, 10),

  ('mantenimiento', N'Mantenimiento', N'Equipos o instalaciones.', N'constructOutline', N'cierre',
   N'Cierre por mantenimiento',
   N'¡Hola! Estamos realizando mantenimiento en {motivo}, por lo que no podremos atenderte por el momento. Reanudaremos el {fecha_reapertura} en {horario}. ¡Gracias por tu paciencia!',
   N'motivo,fecha_reapertura,horario', 1, 20),

  ('cambio_horario', N'Cambio de horario', N'Apertura o cierre especial.', N'timeOutline', N'horario_especial',
   N'Horario especial',
   N'¡Hola! Te informamos que en {nombre_empresa} tendremos un horario especial: {horario}. {motivo}',
   N'horario,motivo', 0, 30),

  ('clima', N'Clima', N'Lluvia, tormentas y contingencias.', N'thunderstormOutline', N'cierre',
   N'Cierre por clima',
   N'¡Hola! Por {motivo} y para cuidar la seguridad de todos, hoy no abriremos. Reanudaremos el {fecha_reapertura} en {horario}. ¡Cuídate mucho!',
   N'motivo,fecha_reapertura,horario', 1, 40),

  ('falla_electrica', N'Falla eléctrica', N'Interrupción de operaciones.', N'flashOffOutline', N'cierre',
   N'Cierre por falla eléctrica',
   N'¡Hola! Tenemos una falla eléctrica ({motivo}) y por ahora no podemos operar. Reanudaremos el {fecha_reapertura} en {horario}. Disculpa las molestias.',
   N'motivo,fecha_reapertura,horario', 1, 50),

  ('dia_festivo', N'Día festivo', N'Cierres y horarios especiales.', N'calendarOutline', N'cierre',
   N'Cierre por día festivo',
   N'¡Hola! Con motivo de {motivo}, {nombre_empresa} permanecerá cerrado. Te esperamos el {fecha_reapertura} en {horario}. ¡Felices fiestas!',
   N'motivo,fecha_reapertura,horario', 1, 60),

  ('servicio_limitado', N'Servicio limitado', N'Servicios temporalmente no disponibles.', N'alertCircleOutline', N'aviso',
   N'Servicio limitado: {servicio_afectado}',
   N'¡Hola! Te informamos que por el momento {servicio_afectado} no está disponible debido a {motivo}. Los demás servicios funcionan con normalidad. Esperamos restablecerlo el {fecha_reapertura}.',
   N'servicio_afectado,motivo,fecha_reapertura', 0, 70),

  ('reanudacion', N'Reanudación', N'Regreso a operaciones normales.', N'checkmarkCircleOutline', N'aviso',
   N'Reanudación de operaciones',
   N'¡Buenas noticias! 🎉 {nombre_empresa} ya reanudó operaciones en {horario}. ¡Gracias por tu paciencia, te esperamos!',
   N'horario', 0, 80)
) AS s (templateKey, name, description, icon, noticeType, defaultTitle, defaultMessage, variables,
        blocksReservations, sortOrder)
ON t.templateKey = s.templateKey
WHEN MATCHED THEN UPDATE SET
  t.name = s.name, t.description = s.description, t.icon = s.icon, t.noticeType = s.noticeType,
  t.defaultTitle = s.defaultTitle, t.defaultMessage = s.defaultMessage, t.variables = s.variables,
  t.blocksReservations = s.blocksReservations, t.sortOrder = s.sortOrder, t.updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET THEN INSERT
  (templateKey, name, description, icon, noticeType, defaultTitle, defaultMessage, variables,
   blocksReservations, sortOrder, status)
  VALUES (s.templateKey, s.name, s.description, s.icon, s.noticeType, s.defaultTitle, s.defaultMessage,
          s.variables, s.blocksReservations, s.sortOrder, N'activo');

SELECT templateKey, name, noticeType, blocksReservations, status
FROM [dbo].[operationalNoticeTemplates] ORDER BY sortOrder;
GO
