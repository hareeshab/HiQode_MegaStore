#!/usr/bin/env bash
set -euo pipefail

### === USER VARS (EDIT) =====================================================
: "${CLUSTER:=megashop}"
: "${AWS_REGION:=us-east-1}"
: "${DOCKERHUB_USER:=30051989}"
: "${DOCKERHUB_TOKEN:=CHANGE_ME}"   # <-- put your Docker Hub access token here
### ==========================================================================

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
for b in aws eksctl kubectl helm; do need "$b"; done

echo "==> Using: CLUSTER=$CLUSTER REGION=$AWS_REGION DOCKERHUB_USER=$DOCKERHUB_USER"

# -----------------------------------------------------------------------------
# 0) Create EKS (idempotent-ish; skip if exists)
# -----------------------------------------------------------------------------
if ! aws eks describe-cluster --name "$CLUSTER" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "==> Creating EKS cluster '$CLUSTER' in $AWS_REGION ..."
  eksctl create cluster \
    --name "$CLUSTER" \
    --region "$AWS_REGION" \
    --version 1.29 \
    --nodegroup-name ng-1 \
    --nodes 3 --nodes-min 3 --nodes-max 6 \
    --managed
else
  echo "==> EKS cluster '$CLUSTER' already exists."
fi

aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION" >/dev/null
kubectl get nodes -o wide

# -----------------------------------------------------------------------------
# 1) IRSA + EBS CSI add-on (uses IRSA SA we create)
# -----------------------------------------------------------------------------
echo "==> Associate OIDC provider for IRSA..."
eksctl utils associate-iam-oidc-provider --cluster "$CLUSTER" --region "$AWS_REGION" --approve

echo "==> Create IRSA ServiceAccount for EBS CSI (policy: AmazonEBSCSIDriverPolicy)..."
eksctl create iamserviceaccount \
  --cluster "$CLUSTER" \
  --region  "$AWS_REGION" \
  --namespace kube-system \
  --name ebs-csi-controller-sa \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --override-existing-serviceaccounts || true

ROLE_ARN=$(kubectl -n kube-system get sa ebs-csi-controller-sa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
echo "==> EBS CSI SA Role: $ROLE_ARN"

echo "==> Install/Update aws-ebs-csi-driver add-on with IRSA..."
aws eks create-addon \
  --cluster-name "$CLUSTER" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "$ROLE_ARN" \
  --resolve-conflicts OVERWRITE >/dev/null 2>&1 || \
aws eks update-addon \
  --cluster-name "$CLUSTER" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "$ROLE_ARN" \
  --resolve-conflicts OVERWRITE >/dev/null

kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-ebs-csi-driver

# -----------------------------------------------------------------------------
# 2) gp3 default StorageClass (single default)
# -----------------------------------------------------------------------------
echo "==> Creating gp3 StorageClass as default..."
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
kubectl annotate sc gp2 storageclass.kubernetes.io/is-default-class- --overwrite 2>/dev/null || true
kubectl get sc

# -----------------------------------------------------------------------------
# 3) AWS Load Balancer Controller with IRSA (broad policies for workshop)
# -----------------------------------------------------------------------------
echo "==> Create IRSA SA for aws-load-balancer-controller (broad AWS policies for speed)..."
eksctl create iamserviceaccount \
  --cluster "$CLUSTER" \
  --region  "$AWS_REGION" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --attach-policy-arn arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
  --approve \
  --override-existing-serviceaccounts || true

helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo update >/dev/null
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER" --region "$AWS_REGION" \
  --output json | jq -r '.cluster.resourcesVpcConfig.vpcId')
echo "==> VPC_ID=$VPC_ID"

echo "==> Install/Upgrade aws-load-balancer-controller to use the IRSA SA..."
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER" \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

kubectl -n kube-system rollout status deploy/aws-load-balancer-controller

# -----------------------------------------------------------------------------
# 4) Build manifests locally (fixed) and apply
# -----------------------------------------------------------------------------
WORKDIR="$(pwd)/megashop-k8s"
mkdir -p "$WORKDIR"
echo "==> Writing manifests to $WORKDIR ..."

# 00-namespace
cat > "$WORKDIR/00-namespace.yaml" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: megashop
EOF

# 01-gateway-config
cat > "$WORKDIR/01-gateway-config.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: gateway-nginx
  namespace: megashop
data:
  nginx.conf: |
    worker_processes auto;
    events { worker_connections 1024; }
    http {
      resolver kube-dns.kube-system.svc.cluster.local valid=10s ipv6=off;
      server {
        listen 80;
        location / { proxy_pass http://frontend.megashop.svc.cluster.local:80; }
        location /api/auth/ { proxy_pass http://auth.megashop.svc.cluster.local:8001/; }
        location /api/catalog/ { proxy_pass http://catalog.megashop.svc.cluster.local:8002/; }
        location /api/orders/ { proxy_pass http://orders.megashop.svc.cluster.local:8003/; }
        location /api/pay/ { proxy_pass http://payments.megashop.svc.cluster.local:8004/; }
      }
    }
EOF

# 02-data (secrets + postgres/mongo/rabbitmq/redis/mailhog)
cat > "$WORKDIR/02-data.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: megashop-secrets
  namespace: megashop
type: Opaque
stringData:
  POSTGRES_USER: megashop
  POSTGRES_PASSWORD: megashop
  RABBITMQ_USER: megashop
  RABBITMQ_PASSWORD: megashop
  JWT_SECRET: supersecretjwt
  MAILHOG_HOST: mailhog
  MAILHOG_PORT: "1025"
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: megashop
spec:
  ports: [{ name: pg, port: 5432, targetPort: 5432 }]
  selector: { app: postgres }
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: megashop
spec:
  serviceName: postgres
  replicas: 1
  selector: { matchLabels: { app: postgres } }
  template:
    metadata: { labels: { app: postgres } }
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        imagePullPolicy: IfNotPresent
        ports: [{ containerPort: 5432, name: pg }]
        envFrom: [{ secretRef: { name: megashop-secrets } }]
        env:
        - { name: POSTGRES_DB, value: "usersdb" }
        - { name: PGDATA, value: "/var/lib/postgresql/data/pgdata" }
        volumeMounts:
        - { name: pgdata, mountPath: /var/lib/postgresql/data }
  volumeClaimTemplates:
  - metadata: { name: pgdata }
    spec:
      accessModes: ["ReadWriteOnce"]
      resources: { requests: { storage: 10Gi } }
---
apiVersion: v1
kind: Service
metadata:
  name: mongo
  namespace: megashop
spec:
  ports: [{ name: mongo, port: 27017, targetPort: 27017 }]
  selector: { app: mongo }
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongo
  namespace: megashop
spec:
  serviceName: mongo
  replicas: 1
  selector: { matchLabels: { app: mongo } }
  template:
    metadata: { labels: { app: mongo } }
    spec:
      containers:
      - name: mongo
        image: mongo:7-jammy
        imagePullPolicy: IfNotPresent
        ports: [{ containerPort: 27017, name: mongo }]
        volumeMounts:
        - { name: mongodata, mountPath: /data/db }
  volumeClaimTemplates:
  - metadata: { name: mongodata }
    spec:
      accessModes: ["ReadWriteOnce"]
      resources: { requests: { storage: 10Gi } }
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
  namespace: megashop
spec:
  ports:
  - { name: amqp, port: 5672, targetPort: 5672 }
  - { name: http, port: 15672, targetPort: 15672 }
  selector: { app: rabbitmq }
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rabbitmq
  namespace: megashop
spec:
  serviceName: rabbitmq
  replicas: 1
  selector: { matchLabels: { app: rabbitmq } }
  template:
    metadata: { labels: { app: rabbitmq } }
    spec:
      containers:
      - name: rabbitmq
        image: rabbitmq:3-management-alpine
        imagePullPolicy: IfNotPresent
        ports:
        - { containerPort: 5672, name: amqp }
        - { containerPort: 15672, name: http }
        env:
        - name: RABBITMQ_DEFAULT_USER
          valueFrom: { secretKeyRef: { name: megashop-secrets, key: RABBITMQ_USER } }
        - name: RABBITMQ_DEFAULT_PASS
          valueFrom: { secretKeyRef: { name: megashop-secrets, key: RABBITMQ_PASSWORD } }
        volumeMounts:
        - { name: rmqdata, mountPath: /var/lib/rabbitmq }
  volumeClaimTemplates:
  - metadata: { name: rmqdata }
    spec:
      accessModes: ["ReadWriteOnce"]
      resources: { requests: { storage: 5Gi } }
---
apiVersion: v1
kind: Service
metadata: { name: redis, namespace: megashop }
spec:
  ports: [{ name: redis, port: 6379, targetPort: 6379 }]
  selector: { app: redis }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: redis, namespace: megashop }
spec:
  replicas: 1
  selector: { matchLabels: { app: redis } }
  template:
    metadata: { labels: { app: redis } }
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        imagePullPolicy: IfNotPresent
        ports: [{ containerPort: 6379, name: redis }]
---
apiVersion: v1
kind: Service
metadata:
  name: mailhog
  namespace: megashop
spec:
  ports:
  - { name: smtp, port: 1025, targetPort: 1025 }
  - { name: ui,   port: 8025, targetPort: 8025 }
  selector: { app: mailhog }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mailhog
  namespace: megashop
spec:
  replicas: 1
  selector: { matchLabels: { app: mailhog } }
  template:
    metadata: { labels: { app: mailhog } }
    spec:
      containers:
      - name: mailhog
        image: mailhog/mailhog:v1.0.1
        imagePullPolicy: IfNotPresent
        ports:
        - { containerPort: 1025, name: smtp }
        - { containerPort: 8025, name: ui }
EOF

# 03-apps (deployments + services)
cat > "$WORKDIR/03-apps.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata: { name: frontend, namespace: megashop }
spec:
  ports: [{ port: 80, targetPort: 80 }]
  selector: { app: frontend }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: frontend, namespace: megashop }
spec:
  replicas: 2
  selector: { matchLabels: { app: frontend } }
  template:
    metadata: { labels: { app: frontend } }
    spec:
      imagePullSecrets: [{ name: dockerhub-cred }]
      containers:
      - name: frontend
        image: 30051989/hiqode:hiqode-megashop-frontend
        imagePullPolicy: IfNotPresent
        ports: [{ containerPort: 80 }]
---
apiVersion: v1
kind: Service
metadata: { name: auth, namespace: megashop }
spec:
  ports: [{ port: 8001, targetPort: 8001 }]
  selector: { app: auth }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: auth, namespace: megashop }
spec:
  replicas: 2
  selector: { matchLabels: { app: auth } }
  template:
    metadata: { labels: { app: auth } }
    spec:
      imagePullSecrets: [{ name: dockerhub-cred }]
      containers:
      - name: auth
        image: 30051989/hiqode:hiqode-megashop-auth
        imagePullPolicy: IfNotPresent
        ports: [{ containerPort: 8001 }]
        env:
        - { name: DATABASE_URL, value: "postgresql://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@postgres.megashop.svc.cluster.local:5432/usersdb" }
        - { name: JWT_SECRET,   valueFrom: { secretKeyRef: { name: megashop-secrets, key: JWT_SECRET } } }
        envFrom: [{ secretRef: { name: megashop-secrets } }]
---
apiVersion: v1
kind: Service
metadata: { name: catalog, namespace: megashop }
spec:
  ports: [{ port: 8002, targetPort: 8002 }]
  selector: { app: catalog }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: catalog, namespace: megashop }
spec:
  replicas: 2
  selector: { matchLabels: { app: catalog } }
  template:
    metadata: { labels: { app: catalog } }
    spec:
      imagePullSecrets: [{ name: dockerhub-cred }]
      containers:
      - name: catalog
        image: 30051989/hiqode:hiqode-megashop-catalog
        imagePullPolicy: IfNotPresent
        ports: [{ containerPort: 8002 }]
        env:
        - { name: MONGO_URL, value: "mongodb://mongo.megashop.svc.cluster.local:27017/megashop" }
---
apiVersion: v1
kind: Service
metadata: { name: orders, namespace: megashop }
spec:
  ports: [{ port: 8003, targetPort: 8003 }]
  selector: { app: orders }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: orders, namespace: megashop }
spec:
  replicas: 2
  selector: { matchLabels: { app: orders } }
  template:
    metadata: { labels: { app: orders } }
    spec:
      imagePullSecrets: [{ name: dockerhub-cred }]
      containers:
      - name: orders
        image: 30051989/hiqode:hiqode-megashop-orders
        imagePullPolicy: IfNotPresent
        ports: [{ containerPort: 8003 }]
        env:
        - { name: DATABASE_URL, value: "postgresql://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@postgres.megashop.svc.cluster.local:5432/usersdb" }
        - { name: AMQP_URL,      value: "amqp://$(RABBITMQ_USER):$(RABBITMQ_PASSWORD)@rabbitmq.megashop.svc.cluster.local:5672" }
        envFrom: [{ secretRef: { name: megashop-secrets } }]
---
apiVersion: v1
kind: Service
metadata: { name: payments, namespace: megashop }
spec:
  ports: [{ port: 8004, targetPort: 8004 }]
  selector: { app: payments }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: payments, namespace: megashop }
spec:
  replicas: 2
  selector: { matchLabels: { app: payments } }
  template:
    metadata: { labels: { app: payments } }
    spec:
      imagePullSecrets: [{ name: dockerhub-cred }]
      containers:
      - name: payments
        image: 30051989/hiqode:hiqode-megashop-payments
        imagePullPolicy: IfNotPresent
        ports: [{ containerPort: 8004 }]
---
apiVersion: v1
kind: Service
metadata: { name: gateway, namespace: megashop }
spec:
  ports: [{ port: 80, targetPort: 80 }]
  selector: { app: gateway }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: gateway, namespace: megashop }
spec:
  replicas: 2
  selector:
    matchLabels: { app: gateway }
  template:
    metadata: { labels: { app: gateway } }
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        imagePullPolicy: IfNotPresent
        ports: [{ containerPort: 80 }]
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
      volumes:
      - name: config
        configMap:
          name: gateway-nginx
          items: [{ key: nginx.conf, path: nginx.conf }]
EOF

# 04-ingress (ALB)
cat > "$WORKDIR/04-ingress.yaml" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: megashop
  namespace: megashop
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: gateway
            port: { number: 80 }
EOF

# 05-seed job
cat > "$WORKDIR/05-seed-job.yaml" <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: seed-catalog
  namespace: megashop
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: curl
        image: curlimages/curl:8.8.0
        imagePullPolicy: IfNotPresent
        args: ["-sS", "http://gateway.megashop.svc.cluster.local/api/catalog/seed?reset=1"]
EOF

echo "==> Applying namespace..."
kubectl apply -f "$WORKDIR/00-namespace.yaml"

echo "==> Creating/patching Docker Hub imagePullSecret..."
kubectl -n megashop create secret docker-registry dockerhub-cred \
  --docker-server='https://index.docker.io/v1/' \
  --docker-username="$DOCKERHUB_USER" \
  --docker-password="$DOCKERHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n megashop patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"dockerhub-cred"}]}' >/dev/null

echo "==> Applying configs and services..."
kubectl apply -f "$WORKDIR/01-gateway-config.yaml"
kubectl apply -f "$WORKDIR/02-data.yaml"
kubectl apply -f "$WORKDIR/03-apps.yaml"
kubectl apply -f "$WORKDIR/04-ingress.yaml"

echo "==> Waiting for deployments (stateless)..."
for d in frontend auth catalog orders payments gateway; do
  kubectl -n megashop rollout status deploy/$d --timeout=180s || true
done

echo "==> Waiting for statefulsets (data plane) PVC bind..."
kubectl -n megashop get pvc

echo "==> Seeding products..."
kubectl apply -f "$WORKDIR/05-seed-job.yaml"
sleep 5
kubectl -n megashop logs -f job/seed-catalog --tail=100 || true

echo "==> Fetching ALB URL..."
for i in {1..30}; do
  ALB=$(kubectl -n megashop get ingress megashop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "${ALB:-}" ]]; then break; fi
  echo "   waiting for ALB to be ready..."
  sleep 10
done

if [[ -n "${ALB:-}" ]]; then
  echo "✅ MegaShop is up: http://${ALB}/"
else
  echo "⚠️ Ingress pending. Check controller logs:"
  echo "kubectl -n kube-system logs deploy/aws-load-balancer-controller -f --tail=200"
fi
