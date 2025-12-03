from fastapi import FastAPI
import os

app = FastAPI()

@app.get("/")
def root():
    return {"message": os.getenv("WELCOME_MSG", "Hello from Project 3 FastAPI!")}

@app.get("/health")
def health():
    return {"status": "ok"}
