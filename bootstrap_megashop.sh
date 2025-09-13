#!/usr/bin/env bash
set -euo pipefail

# ---------- docker-compose ----------
cat > docker-compose.yml <<'YAML'
services:
  gateway:
    image: nginx:1.25-alpine
    volumes:
      - ./gateway/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    ports:
      - "8080:80"
    depends_on: [frontend, auth, catalog, orders, payments]

  frontend:
    build: ./frontend
    depends_on: [auth, catalog, orders]

  auth:
    build: ./services/auth
    environment:
      DB_HOST: postgres
      DB_USER: postgres
      DB_PASSWORD: postgres
      DB_NAME: usersdb
      DB_PORT: 5432
    depends_on: [postgres]

  catalog:
    build: ./services/catalog
    environment:
      MONGO_URL: mongodb://mongo:27017/megashop
    depends_on: [mongo]

  orders:
    build: ./services/orders
    environment:
      DB_HOST: postgres
      DB_USER: postgres
      DB_PASSWORD: postgres
      DB_NAME: ordersdb
      DB_PORT: 5432
      AMQP_URL: amqp://guest:guest@rabbitmq:5672/
    depends_on: [postgres, rabbitmq]

  payments:
    build: ./services/payments

  worker:
    build: ./services/worker
    environment:
      AMQP_URL: amqp://guest:guest@rabbitmq:5672/
      PAYMENTS_URL: http://payments:8004
      SMTP_HOST: mailhog
      SMTP_PORT: 1025
      REDIS_URL: redis://redis:6379/0
    depends_on: [rabbitmq, payments, mailhog, redis]

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: postgres
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./db/init.sql:/docker-entrypoint-initdb.d/00-init.sql:ro
    ports:
      - "5435:5432"

  mongo:
    image: mongo:7-jammy
    volumes:
      - mongodata:/data/db

  rabbitmq:
    image: rabbitmq:3-management-alpine
    ports:
      - "15672:15672"

  mailhog:
    image: mailhog/mailhog:v1.0.1
    ports:
      - "8025:8025"

  redis:
    image: redis:7-alpine

volumes:
  pgdata: {}
  mongodata: {}
YAML

# ---------- gateway ----------
mkdir -p gateway
cat > gateway/nginx.conf <<'NGINX'
server {
  listen 80;
  server_name _;

  location / {
    proxy_pass http://frontend:80;
  }
  location /api/auth/ {
    proxy_pass http://auth:8001/;
  }
  location /api/catalog/ {
    proxy_pass http://catalog:8002/;
  }
  location /api/orders/ {
    proxy_pass http://orders:8003/;
  }
  location /api/pay/ {
    proxy_pass http://payments:8004/;
  }
}
NGINX

# ---------- frontend (React + Vite minimal) ----------
mkdir -p frontend/src
cat > frontend/package.json <<'PKG'
{
  "name": "megashop-frontend",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview --port 5173"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.0",
    "vite": "^5.2.0"
  }
}
PKG

cat > frontend/index.html <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1"/>
    <title>HiQode MegaShop</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
HTML

cat > frontend/src/main.jsx <<'JSX'
import React, { useState } from 'react'
import { createRoot } from 'react-dom/client'

function App(){
  const [products, setProducts] = useState([])
  const [msg, setMsg] = useState('')
  const [token, setToken] = useState(null)

  async function loadProducts(){
    const r = await fetch('/api/catalog/products')
    const d = await r.json()
    setProducts(d)
  }

  async function login(){
    const form = new FormData()
    form.append('email', 'user@hiqode.in')
    form.append('password', 'pass123')
    const r = await fetch('/api/auth/login', { method: 'POST', body: form })
    const d = await r.json()
    if (d?.token) { setToken(d.token); setMsg('Logged in!') } else { setMsg('Login failed') }
  }

  async function placeOrder(pid){
    const form = new FormData()
    form.append('product_id', pid)
    const headers = token ? { 'Authorization': `Bearer ${token}` } : {}
    const r = await fetch('/api/orders/create', { method: 'POST', headers, body: form })
    const d = await r.json()
    setMsg('Order placed: ' + JSON.stringify(d))
  }

  return (
    <div style={{fontFamily:'system-ui', padding:24}}>
      <h1>HiQode MegaShop</h1>
      <p>Gateway routes → Auth, Catalog, Orders, Payments + RabbitMQ Worker + MailHog.</p>
      <div style={{display:'flex', gap:12}}>
        <button onClick={loadProducts}>List Products</button>
        <button onClick={login}>{token?'Logged in':'Login'}</button>
      </div>
      <p>{msg}</p>
      <ul>
        {products.map(p => (
          <li key={p._id}>
            {p.name} — ₹{p.price} &nbsp;
            <button onClick={()=>placeOrder(p._id)}>Order</button>
          </li>
        ))}
      </ul>
    </div>
  )
}
createRoot(document.getElementById('root')).render(<App/>)
JSX

cat > frontend/vite.config.js <<'VITE'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
export default defineConfig({ plugins:[react()], build:{ outDir:'dist' } })
VITE

cat > frontend/Dockerfile <<'DOCKER'
FROM node:18-alpine AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci || npm i
COPY . .
RUN npm run build

FROM nginx:1.25-alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx","-g","daemon off;"]
DOCKER

# ---------- Postgres init ----------
mkdir -p db
cat > db/init.sql <<'SQL'
-- create two DBs: usersdb and ordersdb
create database usersdb;
create database ordersdb;

\connect usersdb;
create table if not exists users(
  id serial primary key,
  email text unique not null,
  password text not null,
  name text
);
insert into users(email, password, name) values('user@hiqode.in','pass123','HiQode User')
on conflict (email) do nothing;

\connect ordersdb;
create table if not exists orders(
  id serial primary key,
  user_email text not null,
  product_id text not null,
  status text default 'created',
  created_at timestamp default now()
);
SQL

# ---------- Auth service (FastAPI) ----------
mkdir -p services/auth
cat > services/auth/requirements.txt <<'REQ'
fastapi==0.112.0
uvicorn==0.30.1
psycopg2-binary==2.9.9
python-multipart==0.0.9
REQ

cat > services/auth/main.py <<'PY'
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
PY

cat > services/auth/Dockerfile <<'DOCKER'
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PIP_ROOT_USER_ACTION=ignore PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --no-compile -r requirements.txt
COPY . .
EXPOSE 8001
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8001"]
DOCKER

# ---------- Catalog service (Node + Mongo) ----------
mkdir -p services/catalog
cat > services/catalog/package.json <<'PKG'
{
  "name": "catalog-service",
  "version": "1.0.0",
  "type": "module",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.3",
    "mongodb": "^6.8.0",
    "cors": "^2.8.5"
  },
  "scripts": {
    "start": "node server.js"
  }
}
PKG

cat > services/catalog/server.js <<'JS'
import express from 'express'
import cors from 'cors'
import { MongoClient } from 'mongodb'

const app = express()
app.use(cors())
app.use(express.json())

const url = process.env.MONGO_URL || 'mongodb://mongo:27017/megashop'
const client = new MongoClient(url)
await client.connect()
const db = client.db()
const products = db.collection('products')

const exists = await products.countDocuments()
if (exists === 0){
  await products.insertMany([
    { name: 'Kubernetes T-Shirt', price: 799 },
    { name: 'DevOps Hoodie', price: 1299 },
    { name: 'Docker Mug', price: 399 }
  ])
}

app.get('/products', async (req,res)=>{
  const list = await products.find({}).limit(50).toArray()
  res.json(list)
})

app.listen(8002, ()=> console.log('Catalog on 8002'))
JS

cat > services/catalog/Dockerfile <<'DOCKER'
FROM node:18-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci || npm i
COPY . .
EXPOSE 8002
CMD ["npm","start"]
DOCKER

# ---------- Orders service (FastAPI + RabbitMQ producer) ----------
mkdir -p services/orders
cat > services/orders/requirements.txt <<'REQ'
fastapi==0.112.0
uvicorn==0.30.1
psycopg2-binary==2.9.9
pika==1.3.2
python-multipart==0.0.9
REQ

cat > services/orders/main.py <<'PY'
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

@app.post("/create")
def create(product_id: str = Form(...), authorization: str | None = Header(default=None)):
    user = "anonymous@guest"
    if authorization == "Bearer demo-token-123":
        user = "user@hiqode.in"
    c = conn(); cur = c.cursor()
    cur.execute("insert into orders(user_email, product_id, status) values(%s,%s,'created') returning id", (user, product_id))
    order_id = cur.fetchone()[0]
    c.commit(); cur.close(); c.close()
    publish({"order_id": order_id, "product_id": product_id, "user_email": user})
    return {"order_id": order_id, "status":"queued"}
PY

cat > services/orders/Dockerfile <<'DOCKER'
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PIP_ROOT_USER_ACTION=ignore PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --no-compile -r requirements.txt
COPY . .
EXPOSE 8003
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8003"]
DOCKER

# ---------- Payments service (Node mock) ----------
mkdir -p services/payments
cat > services/payments/package.json <<'PKG'
{
  "name": "payments-service",
  "version": "1.0.0",
  "type": "module",
  "main": "server.js",
  "dependencies": { "express": "^4.18.3", "cors": "^2.8.5" },
  "scripts": { "start": "node server.js" }
}
PKG

cat > services/payments/server.js <<'JS'
import express from 'express'
import cors from 'cors'

const app = express()
app.use(cors())
app.use(express.json())

app.post('/charge', (req,res)=>{
  setTimeout(()=> res.json({status:'success', txn_id: 'TXN'+Date.now()}), 300)
})

app.listen(8004, ()=> console.log('Payments on 8004'))
JS

cat > services/payments/Dockerfile <<'DOCKER'
FROM node:18-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci || npm i
COPY . .
EXPOSE 8004
CMD ["npm","start"]
DOCKER

# ---------- Worker (Python: RabbitMQ consumer -> payments + email via MailHog) ----------
mkdir -p services/worker
cat > services/worker/requirements.txt <<'REQ'
pika==1.3.2
requests==2.32.3
redis==5.0.8
REQ

cat > services/worker/worker.py <<'PY'
import os, json, smtplib, requests, redis, pika
from email.mime.text import MIMEText

AMQP_URL = os.getenv("AMQP_URL","amqp://guest:guest@rabbitmq:5672/")
PAY_URL = os.getenv("PAYMENTS_URL","http://payments:8004")
SMTP_HOST = os.getenv("SMTP_HOST","mailhog")
SMTP_PORT = int(os.getenv("SMTP_PORT","1025"))
REDIS_URL = os.getenv("REDIS_URL","redis://redis:6379/0")

r = redis.Redis.from_url(REDIS_URL)

def send_email(to, subject, body):
    msg = MIMEText(body)
    msg['Subject'] = subject
    msg['From'] = 'noreply@megashop.local'
    msg['To'] = to
    s = smtplib.SMTP(SMTP_HOST, SMTP_PORT)
    s.sendmail(msg['From'], [to], msg.as_string())
    s.quit()

def handle_order(order):
    try:
        resp = requests.post(f"{PAY_URL}/charge", json={"order_id": order['order_id'], "amount": 100})
        data = resp.json()
        result = data.get('status','failed')
    except Exception:
        result = 'failed'
    r.setex(f"order:{order['order_id']}:payment", 300, result)
    send_email(order['user_email'], "Your MegaShop order", f"Order {order['order_id']} payment {result}!")
    print(f"[worker] processed order {order['order_id']} => {result}")

def main():
    params = pika.URLParameters(AMQP_URL)
    conn = pika.BlockingConnection(params)
    ch = conn.channel()
    ch.queue_declare(queue='orders', durable=False)
    def cb(ch_in, method, props, body):
        order = json.loads(body.decode())
        handle_order(order)
        ch_in.basic_ack(delivery_tag=method.delivery_tag)
    ch.basic_consume('orders', cb, auto_ack=False)
    print("[worker] waiting for messages...")
    ch.start_consuming()

if __name__ == "__main__":
    main()
PY

cat > services/worker/Dockerfile <<'DOCKER'
FROM python:3.11-slim
ENV PIP_NO_CACHE_DIR=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python","worker.py"]
DOCKER

echo "✅ Files written."
