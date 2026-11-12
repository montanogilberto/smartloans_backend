# WhatsApp message templates (Meta Cloud API)

Messages the app **starts** (receipts, codes, offers, reservations, reminders)
only reach people who haven't written to us in the last 24h as **approved
templates**. Register each one below in **WhatsApp Manager → Message templates
→ Create template**, under the WhatsApp Business account of the number set in
`WA_SENDER_PHONE_NUMBER_ID`.

- **Language:** Spanish (MEX), code `es_MX` (override with `WA_TEMPLATE_LANG`)
- **Name:** must match exactly. The backend sends by name (`send_whatsapp(..., template=...)`).
- **Variables:** `{{1}}`, `{{2}}`… in order. Meta asks for a sample value per
  variable; use the samples given.
- Until a template is approved, Meta answers `132001` and the WhatsApp send
  fails — Twilio is disabled (2026-10-16); notificationDispatch moves on to SMS.

| Name | Category | Sent from |
|---|---|---|
| `codigo_verificacion` | Authentication | `users._send_sms_otp` |
| `cuenta_creada` | Utility | `users.send_account_created` |
| `comprobante_listo` | Utility | `notificationDispatch` (with receiptUrl), `send_ticket_whatsapp` |
| `detalle_compra` | Utility | `notificationDispatch` (no receiptUrl, e.g. income_created), `send_ticket_whatsapp` |
| `abono_saldo` | Utility | `walletTopUps.notify_top_up` (saldo top-up ticket) |
| `mensaje_negocio` | Marketing | `whatsappCloud.staff_reply` with asTemplate (staff write first, outside 24 h) |
| `capital_publicado` | Utility | `loanOffers._send_offer_published_ticket` |
| `reservacion_confirmada` | Utility | `reservations._send_confirmation_whatsapp` |
| `registro_pendiente` | Utility | `registrationReminders._notify_cellphone` |
| `aviso_apertura` | Marketing | **Not wired yet.** For the demand signals with `notifyOptIn = 1` (Client Acquisition) |

---

## codigo_verificacion — Authentication

> Not created (2026-10-16): Meta only allows Authentication templates on a
> **verified** business. Until then `_send_sms_otp` sends the code by SMS.

Meta writes the text for authentication templates itself; you only pick
options:

- Code delivery: **Copy code** (button text: `Copiar código`)
- ✅ Add security recommendation
- ✅ Add expiration time: **10 minutes**

Result (Meta's text): *"123456 es tu código de verificación. Por tu seguridad,
no lo compartas. Este código caduca en 10 minutos."*

Backend sends: body `{{1}}` = code, button param = code.

---

## cuenta_creada — Utility

> No greeting ("¡Bienvenido…!"): Meta rejected that wording as Marketing
> (INCORRECT_CATEGORY, 2026-10-16).

```
Tu cuenta GMO fue creada.

Tu usuario para iniciar sesión es: {{1}}

Guárdalo para acceder a la app.
```
Sample: `{{1}}` = `juan.perez`

---

## comprobante_listo — Utility

```
Tu comprobante está listo.

Detalle: {{1}}

Consúltalo aquí: {{2}}

Gracias por tu preferencia.
```
Samples: `{{1}}` = `Gracias por su compra. Total: $250.00 MXN`,
`{{2}}` = `https://posgmo.blob.core.windows.net/receipts/ticket-1234.html`

---

## detalle_compra — Utility

```
Registramos tu compra.

Detalle: {{1}}

Gracias por tu preferencia.
```
Sample: `{{1}}` = `Gracias por su compra. Total: $250.00 MXN · Descuento aplicado (VERANO10): -$25.00 MXN`

---

## abono_saldo — Utility

```
Registramos tu abono de saldo.

Detalle: {{1}}

Gracias por tu preferencia.
```
Sample: `{{1}}` = `Abono de $50.00 MXN con transferencia en Lavanderia GMO. · Saldo disponible: $310.00 MXN · Folio: 1234`

---

## mensaje_negocio — Marketing (Meta rejected Utility; submitted 2026-11-09)

```
Hola, te escribimos de {{1}}.

{{2}}

Si tienes dudas, responde a este mensaje.
```
Samples: `{{1}}` = `Lavanderia GMO`, `{{2}}` = `Tu ropa ya está lista, puedes pasar por ella hoy antes de las 8 pm.`

`{{2}}` is whatever the staff typed. If Meta files it as Marketing, it still
sends but costs more and needs the client's opt-in (BAJA/ALTA).

---

## capital_publicado — Utility

```
GMO: publicaste {{1}} MXN de capital disponible (folio {{2}}).

No implica transferir ni bloquear fondos.
```
Samples: `{{1}}` = `$15,000.00`, `{{2}}` = `482`

---

## reservacion_confirmada — Utility

```
✅ *Reservación confirmada - {{1}}*

Hola *{{2}}*, tu reservación para *{{3}}* está lista.

📅 *Fecha:* {{4}}
🕐 *Hora:* {{5}}
🔖 *Folio:* #{{6}}

Te esperamos. Para cancelar responde CANCELAR.
```
Samples: `{{1}}` = `Lavandería GMO`, `{{2}}` = `María`, `{{3}}` = `Lavado y secado`,
`{{4}}` = `2026-10-05`, `{{5}}` = `10:30`, `{{6}}` = `1027`

---

## registro_pendiente — Utility

```
Aún te falta completar tu registro en GMO: {{1}}.

Termínalo para acceder al sistema.
```
Sample: `{{1}}` = `Perfil de aplicación, Verificación de identidad`

---

## aviso_apertura — Marketing (draft 2026-11-11, not submitted)

Tells someone who said "sí, avísenme" during the validation campaign that the
service they asked for is now open in their zone. These people are in
`dbo.demandSignals` with `notifyOptIn = 1`. It's almost always sent outside the
24 h window, so it must be a template. A "service X is open now" message is
promotional, so submit it as **Marketing** (Utility would get
INCORRECT_CATEGORY, like `cuenta_creada`).

```
Hola, te escribimos de {{1}}.

Nos pediste avisarte cuando abriéramos: {{2}} ya está disponible en {{3}}.

Responde a este mensaje si quieres saber cómo usarlo.
```
Samples: `{{1}}` = `Lavanderia GMO`, `{{2}}` = `el Autoservicio 24 h`,
`{{3}}` = `Pitic, Hermosillo`

Buttons (quick reply): `Quiero más info` · `No me interesa`.
Also turn on Meta's **marketing opt-out button** (`Detener promociones`).

`{{2}}` per concept (from `demandSignals.concept`):
`autoservicio_24h` → `el Autoservicio 24 h` · `lockers` → `el Locker GMO` ·
`qr_gmo` → `Tu QR GMO`. `{{3}}` = the zone that opened (`preferredZoneName`).

Send it only to `notifyOptIn = 1`. Clicking the ad is not permission. A
"No me interesa" reply should clear `notifyOptIn`.

---

## Notes for approval

- Meta rejects templates that **start or end with a variable**. All of the
  above begin and end with fixed text.
- `comprobante_listo` / `detalle_compra` carry a free-form `{{1}}` (the
  message text the POS builds). If Meta re-categorizes either one as
  Marketing, fall back to fixed wording plus a `Total: {{1}}` variable.
- The backend replaces newlines in variables with ` · `, since Meta rejects
  newlines inside parameters (132018).
