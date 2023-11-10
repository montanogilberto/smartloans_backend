from fastapi import FastAPI
from utils import select_all_tables
import uvicorn

app = FastAPI()

@app.get("/select_all_tables/{table_name}")
def select_all_tables_route(table_name: str):
    return select_all_tables(table_name)  

if __name__ == '__main__':
    uvicorn.run(app, host="0.0.0.0", port=8000)