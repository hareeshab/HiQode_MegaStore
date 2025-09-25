# Observability Add‑on Pack (Prometheus + Loki + Grafana)

Namespace: **observability**

## Install (copy/paste)
```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-blackbox-exporter.yaml
kubectl apply -f 02-node-exporter.yaml
kubectl apply -f 03-cadvisor.yaml
kubectl apply -f 04-prometheus-config.yaml
kubectl apply -f 05-loki.yaml
kubectl apply -f 06-promtail.yaml
kubectl apply -f 07-grafana.yaml
```

> Ensure your cluster has a default gp3 StorageClass (EBS CSI) so Loki can provision its PVC.

## Open UIs
```bash
kubectl -n observability port-forward svc/prometheus 9090:9090
kubectl -n observability port-forward svc/grafana    3000:3000
# Prometheus → http://localhost:9090
# Grafana    → http://localhost:3000  (admin / admin123)
```

## What is scraped
- **Node Exporter** (DaemonSet): `node-exporter:9100`
- **cAdvisor** (DaemonSet): `cadvisor:9323` (per‑node container metrics)
- **RabbitMQ**: `rabbitmq.megashop.svc:15692/metrics`
- **Blackbox HTTP Probes** (Gateway and key API endpoints):
  - `/` (storefront)
  - `/api/catalog/products`
  - `/api/auth/login`

## Logs
- **Promtail** tails `/var/log/containers/*.log` on every node and ships to **Loki**
- **Grafana** has Prometheus + Loki datasources pre‑provisioned
- Included dashboard: **MegaShop Overview** (HTTP probe, RabbitMQ scrape duration, Node CPU, Logs view)

## Tweaks
- Add more HTTP targets in `04-prometheus-config.yaml` under `blackbox_http` static_configs
- Add service metrics endpoints (e.g., expose `/metrics` from services) and extend the Prometheus config
