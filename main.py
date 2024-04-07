from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes_ import login, utils, swagger, users, symptoms, scannertext
import uvicorn

app = FastAPI()

# Set up CORS
origins = [
    "https://localhost",
    "http://localhost",
    "https://localhost:8100",
    "http://localhost:8101",
    "http://localhost:60733"
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



if __name__ == '__main__':
    uvicorn.run(app, host="0.0.0.0", port=8000)