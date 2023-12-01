from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_swagger_ui_html, get_redoc_html
from fastapi.openapi.utils import get_openapi
from starlette.responses import JSONResponse

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

# Swagger UI and ReDoc routes
@app.get("/docs", include_in_schema=False)
async def custom_swagger_ui_html():
    return get_swagger_ui_html(openapi_url="/openapi.json", title="docs")

@app.get("/redoc", include_in_schema=False)
async def redoc_html():
    return get_redoc_html(openapi_url="/openapi.json", title="redoc")

@app.get("/openapi.json", include_in_schema=False)
async def openapi_json():
    return JSONResponse(content=get_openapi(title="Your API Title", version="1.0.0", routes=app.routes))


if __name__ == '__main__':
    uvicorn.run(app, host="0.0.0.0", port=8000)