from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from modules.utils import select_all_tables
from modules.login import login_sp
import uvicorn

app = FastAPI()

# Set up CORS
origins = [
    "http://localhost",
    "http://localhost:8100",  # Assuming this is your frontend URL
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/select_all_tables/{table_name}")
def select_all_tables_route(table_name: str):
    return select_all_tables(table_name)

@app.post("/login")
def login(json: dict):
    return login_sp(json)

if __name__ == '__main__':
    uvicorn.run(app, host="0.0.0.0", port=8000)