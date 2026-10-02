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
- Until a template is approved, Meta answers `132001` and the backend falls
  back to Twilio free-form text, which only arrives inside the 24h window.

| Name | Category | Sent from |
|---|---|---|
| `codigo_verificacion` | Authentication | `users._send_sms_otp` |
| `cuenta_creada` | Utility | `users.send_account_created` |
| `comprobante_listo` | Utility | `notificationDispatch` (with receiptUrl), `send_ticket_whatsapp` |
| `detalle_compra` | Utility | `notificationDispatch` (no receiptUrl, e.g. income_created), `send_ticket_whatsapp` |
| `capital_publicado` | Utility | `loanOffers._send_offer_published_ticket` |
| `reservacion_confirmada` | Utility | `reservations._send_confirmation_whatsapp` |
| `registro_pendiente` | Utility | `registrationReminders._notify_cellphone` |

---

## codigo_verificacion — Authentication

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

```
¡Bienvenido a SmartLoans! Tu cuenta fue creada.

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

## capital_publicado — Utility

```
SmartLoans: publicaste {{1}} MXN de capital disponible (folio {{2}}).

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
Aún te falta completar tu registro en SmartLoans: {{1}}.

Termínalo para acceder al sistema.
```
Sample: `{{1}}` = `Perfil de aplicación, Verificación de identidad`

---

## Notes for approval

- Meta rejects templates that **start or end with a variable**. All of the
  above begin and end with fixed text.
- `comprobante_listo` / `detalle_compra` carry a free-form `{{1}}` (the
  message text the POS builds). If Meta re-categorizes either one as
  Marketing, fall back to fixed wording plus a `Total: {{1}}` variable.
- The backend replaces newlines in variables with ` · `, since Meta rejects
  newlines inside parameters (132018).
