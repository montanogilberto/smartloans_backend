# Company requirements for the WhatsApp agent

What a new company must provide before it can use the agent. This is the input
for the future **company configuration module**: each item below becomes a field
or a check in that module.

Status: requirements only, nothing here is built yet. Code and real data checked
2026-11-04, see [Validation](#validation-2026-11-04).

**Rule for the module:** a company can turn the agent on only when every
**Required** item is complete. Everything else improves the answers, but its
absence never blocks activation.

> This repo is public. Keep real CLABEs, tokens, account ids and company data out
> of this file, and out of any example added to it.

## Summary

| # | Area | Level | Who provides it | Where it lives today |
|---|---|---|---|---|
| 1 | Company and branch | Required | GMO | `companies`, `companiesBranch` |
| 2 | WhatsApp number | Required | Company + GMO | `whatsappChannels` |
| 3 | Address and contact | Required | Company | `businessInfo` |
| 4 | Payment types | Required | Company | `businessInfo.paymentMethods` (free text) |
| 5 | Bank account (CLABE) | Required if they accept transfers | Company | Free text only, no real field |
| 6 | Hours | Required | Company | `reservationHours` |
| 7 | Reservable services | Required for bookings | Company | `reservationServices` |
| 8 | Prices and policies | Recommended | Company | `businessInfo` |
| 9 | Promotions and FAQs | Recommended | Company | `posRewardCatalogItems` (coupons), `businessFaqs` |
| 10 | Rewards | Optional | Company | `posReward*` tables |
| 11 | Laundry machines | Optional | GMO | `laundryDevices` |
| 12 | Terminals | Required if they accept cards | Company + GMO | `commissionTerminals` (global) |
| 13 | Accounting base | Required | GMO | `chartOfAccounts` |
| 14 | POS users | Required | GMO | `users`, `userCompanies` |
| 15 | Stripe account | Not needed by the agent today, see section 15 | GMO + company | `stripeConnectedAccounts` |

## What the company must provide

### 1. Company and branch

| Field | Notes |
|---|---|
| Company name | `companies.name`. The agent uses it as the business name. |
| Branch name | `companiesBranch.name`. The agent mentions it when greeting and confirming. |

### 2. WhatsApp number

One number per branch. A message to an unregistered number is dropped: the customer
gets no answer and the backend only writes a warning to the log.

| Field | Notes |
|---|---|
| `phoneNumberId` | Meta's id. It routes each message to the company. |
| `wabaId` | WhatsApp Business account. |
| `displayPhoneNumber` | The number customers see. |
| `companyId`, `branchId` | Owner of the number. |
| `accessTokenRef` | Name of the App Service setting that holds the token, never the token itself. Empty means `WA_ACCESS_TOKEN`, GMO's own Meta portfolio. |
| `botEnabled` | Defaults to on. With it off, only BAJA/ALTA keywords are answered. |

Registered through `POST /whatsapp/channels`, which needs the worker key. The POS has no screen for this.

### 3. Address and contact

`Agente WhatsApp › Configurar › Negocio`.

| Field | Level | If it's missing |
|---|---|---|
| `street`, `city`, `postalCode` | Required | The agent can't say where the business is, and offers a person instead. |
| `mapsUrl` | Required | No tappable link for customers or delivery drivers. |
| `phone` | Required | No contact number to share. |
| `email`, `websiteUrl`, `whatsappNumber` | Recommended | The agent doesn't mention them. |

### 4. Payment types

Two separate things are configured today, and nothing keeps them in sync:

- **What the agent tells customers:** `businessInfo.paymentMethods`, free text, up to
  300 characters. If it's empty, the agent says it doesn't have the information and
  offers a person.
- **What the POS can charge:** fixed buttons, `Efectivo`, `Tarjeta` and `Transferir`,
  plus split payment. They are the same for every company.

For each payment type, the company should say whether it accepts it and where it
applies, for example "tarjeta solo en sucursal".

### 5. Bank account (CLABE)

Required if the company accepts transfers.

| Field | Notes |
|---|---|
| CLABE | 18 digits. Must pass `validate_clabe` (`modules/bankAccounts.py`). |
| Bank | Name shown to the customer. |
| Account holder | Name shown to the customer. |

The agent copies these digit for digit, so a typo sends a customer's money to the
wrong account. The company must review them and confirm before activation.

The agent never confirms a payment. When a customer says they paid or sends proof,
it hands the chat to a person.

### 6. Hours

`Configurar › Horarios`. One row per open day, `dayOfWeek` 0 = lunes through
6 = domingo. A day with no row is closed, so with no rows the business is closed all
week and no slots are ever offered.

### 7. Reservable services

`Configurar › Reservaciones`. At least one active service, if the company wants
bookings by chat.

| Field | Notes |
|---|---|
| `name`, `description` | The agent matches the customer's request against these. |
| `durationMinutes` | Also sets the slot size. Defaults to the machine cycle, then 60. |
| `capacity` | Simultaneous bookings. Defaults to the machine count, then 1. |
| `machineType` | `washer`, `dryer`, `combo` or none. |

### 8. Prices and policies

`Configurar › Precios y políticas`. `servicesInfo`, `pickupPolicy`, `deliveryPolicy`
and `extraInfo`. The agent only quotes a price if it's written in `servicesInfo` or an
FAQ, so without them it can't answer "¿cuánto cuesta?".

### 9. Promotions and FAQs

`Configurar › Promociones` and `Preguntas`. Both optional. With no promotions the
agent says there are none, and without FAQs it answers from business info alone.

### 10. Rewards

The points catalog and `posRewardSettings.earnPct`, if the company uses points.
Customers are matched by the last 10 digits of their registered cellphone. A customer
who isn't registered sees 0 points and can't get a client QR.

### 11. Laundry machines

Only for self-service laundries. `laundryDevices` per branch. Without devices, the
agent treats "¿hay lugar?" as a reservation question.

### 12. Terminals

Required if the company accepts cards.

| Field | Notes |
|---|---|
| `provider`, `terminalName` | For example, the bank or processor. |
| `paymentMethod` | Must be `tarjeta` for the POS to pick it. |
| `commissionRatePct`, `fixedFeeAmount` | The company's negotiated cost. |

`commissionTerminals` is a global catalog with no `companyId`. The POS always uses the
active `tarjeta` terminal with the lowest id, so today every company gets the same
terminal and rate. See gap G2.

The agent doesn't read terminals. They only affect the commission booked on each sale.

### 13. Accounting base

GMO runs `EXEC dbo.sp_chartOfAccounts_seed @companyId = <id>` by hand. Nothing does this
when a company is created, and without it, journal entries for sales and expenses
can't be posted for that company.

### 14. POS users

At least one active POS user with the app installed. Reservation and handoff alerts
are push notifications to the company's POS users, so with no users, a customer who
asks for a person gets no follow-up. The WhatsApp screens use the
`notificationDispatchLog` permission.

### 15. Stripe account (created by GMO)

**The agent doesn't use Stripe today.** It can't charge, and it only explains the ways
to pay. A company needs Stripe only for online card payments, which aren't available yet.

GMO can create the account and run the process, but the data and the terms belong to
the company:

| Field | Provided by |
|---|---|
| Legal name and RFC | Company |
| Legal representative: name, birth date, ID | Company |
| Fiscal address, email, phone | Company |
| Website or business profile | Company |
| Payout CLABE | Company |
| Acceptance of Stripe's terms | Company's representative, in person |

Confirm the final list against Stripe's requirements for Mexican companies when this
is built.

Money rule: card payments must be direct charges on the company's own Stripe account,
so the money never passes through SmartLoans (RFC-010 in POSVending).

## Platform settings (once, not per company)

| Setting | Where | Effect if missing |
|---|---|---|
| `NEGOTIATION_AGENT_URL` | Backend | The agent can't be reached. |
| `WA_ACCESS_TOKEN`, `WA_APP_SECRET`, `WA_VERIFY_TOKEN` | Backend | Webhook rejected or sends fail. |
| `WORKER_KEY` | Backend and agent, same value | Points are unavailable and token usage isn't recorded. |
| Webhook subscription | Meta | Messages for that WhatsApp account never arrive. |
| Approved templates | Meta, see `docs/whatsapp-templates.md` | Messages started by the business fail outside the 24 h window. |

## Gaps the config module must close

| # | Gap | Today | Needed |
|---|---|---|---|
| G1 | No company bank account | `bankAccounts` belongs to clients (`clientId` is mandatory), so the company CLABE sits in free text with no validation | Structured CLABE, bank and holder per company, validated, and used by the agent |
| G2 | Terminals are global | One terminal and rate for all companies | Link terminals to a company, and pick the terminal by company in the POS |
| G3 | Payment types are unlinked | POS buttons and agent text can disagree | One per-company catalog that feeds both |
| G4 | No company Stripe account | Accounts are per `(clientId, companyId)`, created as `individual` with only `transfers`, and RFC-010 covers companyId 1 only | Company-level account, plus an RFC extending RFC-010 to all companies |
| G5 | WhatsApp channel has no screen | `POST /whatsapp/channels` by hand | Channel setup in the module |
| G6 | Wizard is company-wide only | Branch values for `businessInfo` need a direct API call | Edit per branch |
| G7 | Hours and services are per company | Branches share hours, services and slots | Decide if branches need their own |
| G8 | Accounting seed is manual | Forgotten seed means missing journal entries | Run it when the company is created |
| G9 | Time zone is fixed | Agent, slots and POS all use Hermosillo (UTC-7) | Time zone per company, before onboarding one outside that zone |
| G10 | No readiness check | Nothing says what's missing | A checklist that gates `botEnabled` |
| G11 | Agent offers what isn't set up | It offers bookings, hours, points and QR even with nothing configured | Offer only what the company has configured |
| G12 | No isolated test environment | DEV and QA use the production backend and database, and the local `.env` database matched production on every value compared | A separate database, so onboarding can be tested end to end |

## Readiness check

The module should show this checklist and only allow `botEnabled = 1` when all pass:

- [ ] Company and branch exist
- [ ] Active WhatsApp channel for the branch
- [ ] `street`, `city`, `postalCode`, `mapsUrl` and `phone` are filled in
- [ ] At least one payment type is set
- [ ] If transfers are accepted: valid CLABE, bank and holder, confirmed by the company
- [ ] If cards are accepted: terminal and commission rate set
- [ ] At least one open day in `reservationHours`
- [ ] If bookings are offered: at least one active service
- [ ] Accounting base seeded
- [ ] At least one POS user with the app installed

Then, from a real phone, send "hola", ask for the address, hours and how to pay, make
a booking and ask for a person. Confirm that the staff alert arrives.

## Validation (2026-11-04)

Checked read-only, with no writes to any database. The real agent ran locally against
production data: 7 customer questions, 3 runs each, on two companies. One had nothing
configured, the other is the only company live on WhatsApp. Slowest turn: 4.8 s of the
30 s limit. It ran with the uncommitted agent prompt changes of that date.

| Check | Company with nothing configured | Live company |
|---|---|---|
| Invented an address, CLABE, price or hours | 0 of 21 turns | 0 of 21 turns |
| Gave the address | No: says it doesn't have it | No: nothing loaded, 3 of 3 |
| Explained how to pay | No: says it doesn't have it | No: nothing loaded, 3 of 3 |
| Gave prices | No | No: nothing loaded, 3 of 3 |
| Gave hours | No | Yes, 3 of 3 |
| Offered services to book | No | Yes, 3 of 3 |
| Handed off to a person when asked | 3 of 3 | 3 of 3 |

What this means:

- **Missing data is safe but useless.** The agent doesn't make things up, it just can't help.
- **The live company fails this checklist.** It has no `street`, `postalCode`, `mapsUrl`,
  `phone` or `paymentMethods`, no prices, and no FAQs.
- **A company with nothing still greets customers** with a full list of services (G11).

Not validated:

- A booking through to its confirmation, and the slots shown for each service
- The company creation flow, because no test environment exists (G12)
- Whether each company has POS users and a seeded accounting base
- Sending and receiving on a real WhatsApp number
- The staff alert after a handoff, since the agent promises a reply either way
- Other agents in `LoanAgents_SmartLoans`, which may need more company data

## Open decisions

1. **Stripe:** is it mandatory at onboarding, or only once card payments are built?
   This document assumes the second.
2. **Bookings:** can a company use the agent without them? This document assumes yes.
3. **Token balance:** usage is recorded, but a company at zero isn't stopped. Should a
   new company start with a balance, and should the agent stop at zero?
4. **Meta:** do all companies use GMO's portfolio, or can each bring its own?
5. **Existing companies:** the readiness check would fail the live company. Should it
   apply only to new activations, or also turn off companies that fail?
