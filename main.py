from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes_ import login,utils,swagger,users


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

app.include_router(swagger.router)
app.include_router(utils.router)
app.include_router(login.router)
app.include_router(users.router)



if __name__ == '__main__':
    uvicorn.run(app, host="0.0.0.0", port=8000)