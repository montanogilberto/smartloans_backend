import json
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from dotenv import load_dotenv
load_dotenv()

from observability import ObservabilityMiddleware, writer

# Routers
from routes_ import (
    login, utils, swagger, users, symptoms, scannertext, products, checks,
    departaments, employmentTypes, statuses, employees, projects,
    employeeProjectAssignments, contractors, whatsapp, orders, commands,
    vending_v2, contact_email, laundry, income, IOT, tickets, clients,
    expenses, exchangeRates, buyOffers, unifiedProducts, costRules,
    listingDrafts, messageTickets, procurementJobs, productMatches,
    publishJobs, sellListings, shipments, opportunities, marketplaceOrders, mercadolibre, ml_proxy,
    mlSearchRuns, mlJobs, routes_ml_proxy, cashRegister, companies, companiesBranches, productCategories,
    supplier, loan, clientFaceRecognition,
    pushNotification,
    loanProposals, loanOffers, stripe_payments,
    creditScore, walletBalance, automatedPayments, signatureUpload,
    manufacturing, rewards, loanChat, clientDashboards,
    digitalContracts, legalCases, disbursement,
    document_intelligence, geocoding, onboardingReminders, registrationReminders,
    clientFollowUps,
    bankAccounts, walletTransactions, transfers,
    paymentIntents, fundingTransactions, transferEvidence, paymentHistory,
)

app = FastAPI(
    title="SmartLoans Backend API",
    version="1.0.0"
)



# --------------------------------------------------
# Health Check (Azure App Service)
# --------------------------------------------------
@app.get("/health", tags=["Health"])
def health_check():
    """
    Azure Health Check endpoint.
    Must return HTTP 200 when the app is healthy.
    """
    return {"status": "ok"}

# --------------------------------------------------
# CORS configuration
# --------------------------------------------------
origins = [
    # Local development
    "http://localhost",
    "https://localhost",
    "http://localhost:3000",
    "http://localhost:8000",
    "http://localhost:8100",
    "http://localhost:5173",
    "capacitor://localhost",
    "ionic://localhost",

    # Azure Static Web Apps / Production
    "https://wonderful-island-0e351d910.5.azurestaticapps.net",
    "https://delightful-river-039129e0f.5.azurestaticapps.net",
    "https://mango-smoke-0323ed91e.3.azurestaticapps.net",
    "https://proud-grass-09761cb1e.1.azurestaticapps.net",
    "https://ashy-ground-041405f1e.7.azurestaticapps.net",

    # Custom domain
    "https://www.rpmtoolsmx.com",

    # Azure Functions / Backend API
    "https://smartloansbackend.azurewebsites.net",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Observability layer — traces every request (correlationId), auto-emits an
# applicationLog, and lets business code log workflow/audit/integration events.
# Added after CORS so it sits outermost and captures the full request lifecycle.
app.add_middleware(ObservabilityMiddleware)

# --------------------------------------------------
# Routers
# --------------------------------------------------
app.include_router(swagger.router)
app.include_router(utils.router)
app.include_router(login.router)
app.include_router(users.router)
app.include_router(symptoms.router)
app.include_router(scannertext.router)
app.include_router(products.router)
app.include_router(checks.router)

app.include_router(departaments.router)
app.include_router(employmentTypes.router)
app.include_router(statuses.router)
app.include_router(employees.router)
app.include_router(projects.router)
app.include_router(employeeProjectAssignments.router)
app.include_router(contractors.router)

app.include_router(whatsapp.router)
app.include_router(orders.router)
app.include_router(commands.router)
app.include_router(vending_v2.router)
app.include_router(contact_email.router)

app.include_router(laundry.router)
app.include_router(IOT.router)
app.include_router(income.router)
app.include_router(tickets.router)
app.include_router(clients.router)
app.include_router(expenses.router)
app.include_router(cashRegister.router)

app.include_router(exchangeRates.router)
app.include_router(buyOffers.router)
app.include_router(unifiedProducts.router)
app.include_router(costRules.router)
app.include_router(listingDrafts.router)
app.include_router(messageTickets.router)

app.include_router(procurementJobs.router)
app.include_router(productMatches.router)
app.include_router(publishJobs.router)
app.include_router(sellListings.router)
app.include_router(shipments.router)
app.include_router(opportunities.router)
app.include_router(marketplaceOrders.router)

app.include_router(mercadolibre.router)
app.include_router(ml_proxy.router)
app.include_router(mlSearchRuns.router)
app.include_router(mlJobs.router)
app.include_router(routes_ml_proxy.router)
app.include_router(companies.router)
app.include_router(companiesBranches.router)
app.include_router(productCategories.router)
app.include_router(supplier.router)
app.include_router(loan.router)
app.include_router(clientDashboards.router)
app.include_router(clientFaceRecognition.router)
app.include_router(pushNotification.router)
app.include_router(clientFollowUps.router)
app.include_router(loanProposals.router)
app.include_router(loanOffers.router)
app.include_router(stripe_payments.router)
app.include_router(paymentIntents.router)
app.include_router(fundingTransactions.router)
app.include_router(transferEvidence.router)
app.include_router(paymentHistory.router)
# Banking-first Phase 1 (docs/payment-banking-first-redesign.md):
# CLABEs verificadas + ledger inmutable + dispersión SPEI (STP, mock hasta contrato)
app.include_router(bankAccounts.router)
app.include_router(walletTransactions.router)
app.include_router(transfers.router)
app.include_router(creditScore.router)
app.include_router(walletBalance.router)
app.include_router(automatedPayments.router)
app.include_router(signatureUpload.router)
app.include_router(manufacturing.router)
app.include_router(rewards.router)
app.include_router(loanChat.router)
app.include_router(digitalContracts.router)
app.include_router(legalCases.router)
app.include_router(disbursement.router)
app.include_router(document_intelligence.router)
app.include_router(geocoding.router)
app.include_router(onboardingReminders.router)
app.include_router(registrationReminders.router)

# --------------------------------------------------
# Daily automated-repayment job
# Charges every due loan installment (off-session, saved card) once a day.
# Requires Azure App Service's "Always On" setting enabled — otherwise the
# process idles between requests and this scheduler stops running silently.
# --------------------------------------------------
from modules.companies import all_companies_sp
from modules.automatedPayments import charge_due_installments
from modules.onboardingReminders import check_onboarding_completeness
from modules.registrationReminders import check_registration_completeness
from modules.offerReminders import check_active_offers
from modules.bankAccountReminders import check_missing_bank_accounts
from modules.paymentIntents import payment_intents_sp
from modules.fundingTransactions import funding_transactions_sp

scheduler = AsyncIOScheduler()


async def _list_company_ids():
    try:
        companies_response = all_companies_sp()
        companies = json.loads(companies_response.body).get("companies", [])
        return [c.get("companyId") for c in companies if c.get("companyId")]
    except Exception as e:
        print(f"[scheduler] failed to list companies: {e}")
        return []


async def _run_daily_charge_due():
    for company_id in await _list_company_ids():
        try:
            await charge_due_installments({"companyId": company_id})
            print(f"[scheduler] charge-due: ran for companyId={company_id}")
        except Exception as e:
            print(f"[scheduler] charge-due: failed for companyId={company_id}: {e}")


async def _run_daily_onboarding_reminders():
    for company_id in await _list_company_ids():
        try:
            await check_onboarding_completeness({"companyId": company_id})
            print(f"[scheduler] onboarding-reminders: ran for companyId={company_id}")
        except Exception as e:
            print(f"[scheduler] onboarding-reminders: failed for companyId={company_id}: {e}")


async def _run_daily_offer_reminders():
    for company_id in await _list_company_ids():
        try:
            await check_active_offers({"companyId": company_id})
            print(f"[scheduler] offer-reminders: ran for companyId={company_id}")
        except Exception as e:
            print(f"[scheduler] offer-reminders: failed for companyId={company_id}: {e}")


async def _run_daily_bank_account_reminders():
    for company_id in await _list_company_ids():
        try:
            await check_missing_bank_accounts({"companyId": company_id})
            print(f"[scheduler] bank-account-reminders: ran for companyId={company_id}")
        except Exception as e:
            print(f"[scheduler] bank-account-reminders: failed for companyId={company_id}: {e}")


async def _run_daily_registration_reminders():
    # Not company-scoped like the two jobs above — an incomplete
    # registration may not have a company yet (that's the "Acceso" step).
    try:
        await check_registration_completeness({})
        print("[scheduler] registration-reminders: ran")
    except Exception as e:
        print(f"[scheduler] registration-reminders: failed: {e}")


# RFC-002 Phase 1: global sweeps (no companyId loop — both SPs already accept
# an optional companyId and default to a global sweep when omitted, matching
# how sp_paymentIntents.expire_due/sp_fundingTransactions.escalate_due are
# written). Interval, not daily-cron: these bound a 5-day expiry (D12) and a
# 2-day-default escalation window (D5) — a once-a-day check risks sitting on
# a stale OPEN/PENDING_CONFIRMATION row for up to 24h past its threshold,
# which matters more here than for the once-daily reminder jobs above.
async def _run_payment_intents_expire_due():
    try:
        payment_intents_sp({"paymentIntents": [{"action": "expire_due"}]})
        print("[scheduler] paymentIntents.expire_due: ran")
    except Exception as e:
        print(f"[scheduler] paymentIntents.expire_due: failed: {e}")


async def _run_funding_transactions_escalate_due():
    try:
        funding_transactions_sp({"fundingTransactions": [{"action": "escalate_due"}]})
        print("[scheduler] fundingTransactions.escalate_due: ran")
    except Exception as e:
        print(f"[scheduler] fundingTransactions.escalate_due: failed: {e}")


@app.on_event("startup")
async def start_scheduler():
    # Start the observability background log writer (async best-effort path).
    writer.start()
    # 07:00 UTC ≈ early morning in Mexico (UTC-6/-5) — off-peak for billing.
    scheduler.add_job(_run_daily_charge_due, "cron", hour=7, minute=0, id="daily_charge_due")
    # 15:00 UTC ≈ mid-morning in Mexico — a time a client is likely to see
    # and act on the notification, unlike the pre-dawn billing run above.
    scheduler.add_job(_run_daily_onboarding_reminders, "cron", hour=15, minute=0, id="daily_onboarding_reminders")
    scheduler.add_job(_run_daily_registration_reminders, "cron", hour=16, minute=0, id="daily_registration_reminders")
    # 15:30 UTC ≈ media mañana en México — recuerda a los prestatarios el
    # capital publicado en el marketplace mientras siga activo (solo envía
    # si hay ofertas vivas; una notificación consolidada por compañía).
    scheduler.add_job(_run_daily_offer_reminders, "cron", hour=15, minute=30, id="daily_offer_reminders")
    # 15:45 UTC — invita a los clientes verificados SIN cuenta bancaria a
    # vincular su CLABE (sin ella el desembolso SPEI se bloquea al aceptar).
    scheduler.add_job(_run_daily_bank_account_reminders, "cron", hour=15, minute=45, id="daily_bank_account_reminders")
    # Every 6h — RFC-002 Phase 1 funding sweeps (see functions above for why
    # these run more often than the daily jobs).
    scheduler.add_job(_run_payment_intents_expire_due, "interval", hours=6, id="payment_intents_expire_due")
    scheduler.add_job(_run_funding_transactions_escalate_due, "interval", hours=6, id="funding_transactions_escalate_due")
    scheduler.start()


@app.on_event("shutdown")
async def stop_observability_writer():
    # Flush any queued logs before the process exits.
    writer.flush_and_stop()

# --------------------------------------------------
# Local development only
# (Azure ignores this block)
# --------------------------------------------------
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )
