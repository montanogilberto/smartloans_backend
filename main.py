from fastapi import FastAPI
from flask_cors import CORS
from modules.utils import select_all_tables
from modules.login import login_sp
import uvicorn

app = FastAPI()
CORS(app)

@app.get("/select_all_tables/{table_name}")
def select_all_tables_route(table_name: str):
    return select_all_tables(table_name)

@app.post("/login")
def login(json: dict):
    return login_sp(json)

if __name__ == '__main__':
    uvicorn.run(app, host="0.0.0.0", port=8000)