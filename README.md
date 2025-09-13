<!-- PROJECT HEADER -->
<p align="center">
  <img src="https://img.shields.io/badge/HiQode-MegaShop-0b5cff?style=for-the-badge&logo=storefront&logoColor=white" />
  <img src="https://img.shields.io/badge/Stack-React%20%7C%20FastAPI%20%7C%20Node%20%7C%20NGINX%20%7C%20RabbitMQ%20%7C%20MailHog%20%7C%20Redis-111?style=for-the-badge" />
  <br/>
  <img src="https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white&style=for-the-badge" />
  <img src="https://img.shields.io/badge/License-Workshop%20Demo-success?style=for-the-badge" />
</p>

<h1 align="center">HiQode MegaShop – Multi-Tier DevOps Demo</h1>

<p align="center">
A realistic, multi-container e-commerce demo for workshops: gateway ➜ frontend ➜ microservices ➜ queue ➜ worker ➜ email.
</p>

<p align="center">
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-architecture">Architecture</a> •
  <a href="#-urls--credentials">URLs & Credentials</a> •
  <a href="#-features">Features</a> •
  <a href="#-troubleshooting">Troubleshooting</a>
</p>

---

## ✨ Features

- **Gateway** (NGINX) with dynamic service discovery (no stale IP 502s)
- **Frontend**: React + Vite + Tailwind, categories, cart, **login-required checkout**, coupons, **order history**
- **Auth** (FastAPI + Postgres), **Catalog** (Node + Mongo + seeding), **Orders** (FastAPI + Postgres)
- **Payments** (mock Node service), **RabbitMQ** + **Worker** (Python) sending emails to **MailHog**
- **Redis** cache
- One-command up: **`docker compose up -d --build`**

---

## 🚀 Quick Start

> [!TIP]
> Use a clean Ubuntu 22.04+ VM with Docker Engine + Compose plugin installed.

```bash
# 0) Install Docker (Ubuntu)
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker

# 1) Clone repo
git clone https://github.com/<your-org-or-user>/hiqode-megashop.git
cd hiqode-megashop

# 2) Bring everything up
docker compose up -d --build

# 3) (First run) Seed catalog (images + categories)
curl -s "http://127.0.0.1:8080/api/catalog/seed?reset=1"



## 🌐 URLs & Credentials

| Component       | URL                         | Notes                              |
|-----------------|-----------------------------|------------------------------------|
| **Storefront**  | `http://<server-ip>:8080`   | Browse, add to cart, checkout      |
| **MailHog**     | `http://<server-ip>:8025`   | View order emails                  |
| **RabbitMQ UI** | `http://<server-ip>:15672`  | Login: `megashop / megashop`       |

**Demo login for checkout**
```text
email: user@hiqode.in
pass:  pass123

