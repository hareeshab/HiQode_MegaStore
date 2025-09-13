from fastapi import FastAPI, Form, Header
import os, psycopg2, json, pika

app = FastAPI(title="Orders Service")

def conn():
    return psycopg2.connect(
        host=os.getenv("DB_HOST","postgres"),
        user=os.getenv("DB_USER","postgres"),
        password=os.getenv("DB_PASSWORD","postgres"),
        dbname=os.getenv("DB_NAME","ordersdb"),
        port=int(os.getenv("DB_PORT","5432"))
    )

def publish(msg: dict):
    url = os.getenv("AMQP_URL","amqp://guest:guest@rabbitmq:5672/")
    params = pika.URLParameters(url)
    connection = pika.BlockingConnection(params)
    channel = connection.channel()
    channel.queue_declare(queue='orders', durable=False)
    channel.basic_publish(exchange='', routing_key='orders', body=json.dumps(msg).encode())
    connection.close()

def current_user(authorization: str | None):
    if authorization == "Bearer demo-token-123":
        return "user@hiqode.in"
    return None

@app.post("/create")
def create(product_id: str = Form(...), authorization: str | None = Header(default=None)):
    user = current_user(authorization) or "anonymous@guest"
    c = conn(); cur = c.cursor()
    cur.execute("insert into orders(user_email, product_id, status) values(%s,%s,'created') returning id", (user, product_id))
    order_id = cur.fetchone()[0]
    c.commit(); cur.close(); c.close()
    publish({"order_id": order_id, "product_id": product_id, "user_email": user})
    return {"order_id": order_id, "status":"queued"}

@app.get("/list")
def list_orders(authorization: str | None = Header(default=None)):
    user = current_user(authorization)
    if not user:
        return {"error":"unauthorized"}
    c = conn(); cur = c.cursor()
    cur.execute("select id, user_email, product_id, status, created_at from orders where user_email=%s order by id desc limit 50", (user,))
    rows = cur.fetchall(); cur.close(); c.close()
    return [{"id":r[0], "user_email":r[1], "product_id":r[2], "status":r[3], "created_at":r[4].isoformat()} for r in rows]
