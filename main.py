from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
#from dotenv import load_dotenv
#load_dotenv()

# Routers
from routes_ import (
    login, utils, swagger, users, symptoms, scannertext, products, checks,
    departaments, employmentTypes, statuses, employees, projects,
    employeeProjectAssignments, contractors, whatsapp, orders, commands,
    vending_v2, contact_email, laundry, income, IOT, tickets, clients,
    expenses, exchangeRates, buyOffers, unifiedProducts, costRules,
    listingDrafts, messageTickets, procurementJobs, productMatches,
    publishJobs, sellListings, shipments, opportunities, marketplaceOrders, mercadolibre, ml_proxy
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
    "http://localhost:3000",
    "http://localhost:8000",
    "http://localhost:8100",
    "capacitor://localhost",
    "ionic://localhost",

    # Azure Static Web Apps / Production
    "https://wonderful-island-0e351d910.5.azurestaticapps.net",
    "https://delightful-river-039129e0f.5.azurestaticapps.net",
    "https://mango-smoke-0323ed91e.3.azurestaticapps.net",

    # Custom domain
    "https://www.rpmtoolsmx.com",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
