from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes_ import login, utils, swagger, users, symptoms, scannertext, products, checks
from routes_ import (departaments, employmentTypes, statuses, employees, projects, employeeProjectAssignments,
                     contractors, whatsapp, orders, commands, vending_v2, contact_email, laundry, income,IOT,
                     tickets, clients)

import uvicorn

app = FastAPI()

# Set up CORS
origins = [
    "https://localhost",
    "http://localhost",
    "https://localhost:8100",
    "http://localhost:8101",
    "http://localhost:8000",
    "http://localhost:8100",
    "http://localhost:3000",
    "https://wonderful-island-0e351d910.5.azurestaticapps.net",
    "https://delightful-river-039129e0f.5.azurestaticapps.net",
    "capacitor://localhost",
    "ionic://localhost",
    "https://www.rpmtoolsmx.com",
    "https://mango-smoke-0323ed91e.3.azurestaticapps.net"
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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


if __name__ == '__main__':
    uvicorn.run(app, host="0.0.0.0", port=8000)
