from fastapi import FastAPI, Form, Header
import os, psycopg2

app = FastAPI(title="Auth Service")

def conn():
    return psycopg2.connect(
        host=os.getenv("DB_HOST","postgres"),
        user=os.getenv("DB_USER","postgres"),
        password=os.getenv("DB_PASSWORD","postgres"),
        dbname=os.getenv("DB_NAME","usersdb"),
        port=int(os.getenv("DB_PORT","5432"))
    )

@app.post("/login")
def login(email: str = Form(...), password: str = Form(...)):
    c = conn(); cur = c.cursor()
    cur.execute("select name from users where email=%s and password=%s", (email, password))
    row = cur.fetchone()
    cur.close(); c.close()
    if row:
        return {"token":"demo-token-123","user":{"email":email,"name":row[0]}}
    return {"error":"invalid credentials"}

@app.get("/me")
def me(authorization: str | None = Header(default=None)):
    if authorization == "Bearer demo-token-123":
        return {"email":"user@hiqode.in","name":"HiQode User"}
    return {"error":"unauthorized"}
