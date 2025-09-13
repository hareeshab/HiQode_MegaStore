HiQode MegaShop — Multi-Tier DevOps Demo

A realistic, multi-container e-commerce demo used for DevOps workshops.
It shows a typical microservices stack with a gateway, frontend, multiple backend services, a message queue, background worker, SMTP capture, and databases.

✨ What you get

Gateway: NGINX reverse proxy (routes to all services)

Frontend: React (Vite + Tailwind) storefront with categories, cart, checkout, login, coupons, order history

Auth Service: FastAPI + Postgres

Catalog Service: Node + MongoDB (+ seeded data, images, categories)

Orders Service: FastAPI + Postgres (+ “my orders” endpoint)

Payments Service: Node (mock)

RabbitMQ: message broker (+ management UI)

Worker: Python consumer (process payments, send emails, cache status)

MailHog: in-cluster SMTP + web UI (view order emails)

Redis: cache

🧰 Prerequisites

Linux VM (Ubuntu 22.04+ recommended)

Docker Engine + Docker Compose plugin

sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker

🚀 Quick Start
# 1) Clone
git clone https://github.com/<you>/hiqode-megashop.git
cd hiqode-megashop

# 2) Build + run everything
docker compose up -d --build

Open these URLs
App	URL
Storefront (Gateway)	http://<server-ip>:8080
MailHog (emails)	http://<server-ip>:8025
RabbitMQ UI	http://<server-ip>:15672 (user: megashop, pass: megashop)
Demo login (for checkout)
email: user@hiqode.in
pass:  pass123

Coupons

HIQODE10 → 10% off

DEVOPS20 → 20% off

🏗️ Project Structure (top-level)
docker-compose.yml
gateway/nginx.conf
frontend/...
services/
  auth/         (FastAPI)
  catalog/      (Node)
  orders/       (FastAPI)
  payments/     (Node)
  worker/       (Python consumer)
db/init.sql     (Postgres bootstrap: usersdb + ordersdb)

🔌 Services & Ports (inside the network)
Service	Port	Notes
gateway	80	Exposed on host as 8080
frontend	80	Served behind gateway
auth	8001	FastAPI → Postgres usersdb
catalog	8002	Node → MongoDB megashop
orders	8003	FastAPI → Postgres ordersdb
payments	8004	Mock payment
rabbitmq	5672	AMQP (UI on 15672)
mailhog	1025	SMTP (UI on 8025)
redis	6379	Cache
🧪 First-Run Checklist

Seed catalog data (images + categories)
The service seeds automatically on first boot. If you ever need to reseed:

# through the gateway (verifies routing too)
curl -s "http://127.0.0.1:8080/api/catalog/seed?reset=1"


Check:

curl -s http://127.0.0.1:8080/api/catalog/categories
curl -s "http://127.0.0.1:8080/api/catalog/products?category=Clothing"


Visit the store: http://<server-ip>:8080

Browse categories (All / Clothing / Footwear / Groceries)

Add to cart → Checkout

If logged out, a Login modal appears (use demo login above)

Apply coupon → place order

Verify email in MailHog: http://<server-ip>:8025
You should see order confirmation messages.

RabbitMQ queue drains: http://<server-ip>:15672
Login megashop/megashop → queues → orders.
Messages briefly appear then go to 0 as the worker processes them.

⚙️ Configuration (sensible defaults)

docker-compose.yml already includes:

RabbitMQ credentials + healthcheck

rabbitmq:
  image: rabbitmq:3-management-alpine
  environment:
    RABBITMQ_DEFAULT_USER: megashop
    RABBITMQ_DEFAULT_PASS: megashop
  ports: ["15672:15672"]
  healthcheck:
    test: ["CMD","rabbitmq-diagnostics","-q","ping"]
    interval: 5s
    timeout: 3s
    retries: 20


Worker waits for dependencies and auto-retries on network hiccups

worker:
  build: ./services/worker
  restart: unless-stopped
  environment:
    AMQP_URL: amqp://megashop:megashop@rabbitmq:5672/
    PAYMENTS_URL: http://payments:8004
    SMTP_HOST: mailhog
    SMTP_PORT: 1025
    REDIS_URL: redis://redis:6379/0
  depends_on:
    rabbitmq:
      condition: service_healthy
    payments:
      condition: service_started
    mailhog:
      condition: service_started
    redis:
      condition: service_started


Gateway uses Docker DNS dynamically (avoids random 502s):

# gateway/nginx.conf
server {
  listen 80;
  server_name _;
  resolver 127.0.0.11 ipv6=off valid=10s;

  set $frontend_upstream http://frontend:80;
  location / { proxy_pass $frontend_upstream; }

  set $auth_upstream     http://auth:8001;
  set $catalog_upstream  http://catalog:8002;
  set $orders_upstream   http://orders:8003;
  set $pay_upstream      http://payments:8004;

  location /api/auth/    { proxy_pass $auth_upstream; }
  location /api/catalog/ { proxy_pass $catalog_upstream; }
  location /api/orders/  { proxy_pass $orders_upstream; }
  location /api/pay/     { proxy_pass $pay_upstream; }
}

🧭 Common Tasks
Rebuild just the frontend
docker compose build frontend
docker compose up -d frontend
docker compose restart gateway

Reseed products (safe and idempotent)
curl -s "http://127.0.0.1:8080/api/catalog/seed?reset=1"

Watch worker logs
docker compose logs -f worker

Test SMTP from inside worker
docker exec -it hiqode-megashop-worker-1 bash -lc 'python - <<PY
import smtplib
s=smtplib.SMTP("mailhog",1025,timeout=5)
print("SMTP OK:", s.noop()); s.quit()
PY'

🐞 Troubleshooting
“502 Bad Gateway” on /:

Likely NGINX cached an old container IP.
Fix: docker compose restart gateway

Ensure gateway config has resolver 127.0.0.11 (dynamic Docker DNS) and you didn’t modify service names.

“502” on /api/* (e.g., /api/catalog/products)

Confirm service is up:
docker compose ps catalog
docker compose logs --tail=80 catalog

Verify from inside gateway:
docker exec -it hiqode-megashop-gateway-1 sh -lc 'apk add --no-cache curl >/dev/null && curl -I http://catalog:8002/products'

No emails in MailHog

Make sure worker is running:
docker compose ps worker (should be Up)
docker compose logs --tail=100 worker

RabbitMQ queue not draining? Check UI :15672 (login megashop/megashop).

Restart in order:

docker compose up -d rabbitmq mailhog payments redis
docker compose up -d worker

Mongo seed not showing categories/images

Run the seed endpoint:
curl -s "http://127.0.0.1:8080/api/catalog/seed?reset=1"

Postgres port already used on host

The compose maps Postgres to host 5435. Change if needed in docker-compose.yml.

🌐 Put the app under your domain (optional)

If this host has a public IP and a domain (e.g., megashop.hiqode.co.in), point an A record to the VM IP.
Then either:

Option A (simple): Keep using the built-in gateway on port 8080 and have your external reverse proxy forward to it.

Option B (certs on host): Terminate TLS on host NGINX/Caddy/Traefik and reverse-proxy to http://127.0.0.1:8080.

Tip: Keep container service names (frontend, auth, etc.) unchanged or update gateway/nginx.conf accordingly.

🧹 Clean Up
# stop stack
docker compose down

# remove volumes (databases!)
docker compose down -v

📜 License

For workshop/demo use. Adapt freely.

🙋 Support

If installation on a fresh VM doesn’t behave exactly as above, run:

docker compose ps
docker compose logs --tail=150 gateway catalog worker

