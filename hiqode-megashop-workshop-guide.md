# HiQode MegaShop — End‑to‑End Workshop (EKS)

This is a copy‑paste friendly runbook to stand up the **MegaShop** microservices app on **AWS EKS**, using images from your **private Docker Hub** repo `30051989/hiqode` with service‑as‑tag naming.

It covers:
1) Cluster creation  
2) Cluster configuration (EBS CSI, StorageClass, Ingress)  
3) Manifests with fixes (gateway image and Postgres `PGDATA`)  
4) Troubleshooting  
5) Demo storyline & talking points

---

## 0) Prereqs (local)

- AWS CLI v2, `eksctl`, `kubectl`, `helm`
- IAM user/role with permission to create EKS, IAM roles, add‑ons, and ALB resources
- Your Docker Hub credentials (private repo access token)

```bash
aws --version
eksctl version
kubectl version --client
helm version
```

---

## 1) Create an EKS cluster

> **Region**: `us-east-1` (adjust as needed)

```bash
export CLUSTER=megashop
export AWS_REGION=us-east-1

eksctl create cluster   --name $CLUSTER   --region $AWS_REGION   --version 1.29   --nodegroup-name ng-1   --nodes 3   --nodes-min 3   --nodes-max 6   --managed
```

Update kubeconfig (if needed):
```bash
aws eks update-kubeconfig --name $CLUSTER --region $AWS_REGION
kubectl get nodes
```

---

## 2) Cluster configuration

### 2.1 Associate OIDC for IRSA
```bash
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER --approve
```

### 2.2 Install **AWS EBS CSI** (managed add‑on with IRSA)

Create an IAM role for the controller ServiceAccount and attach AWS‑managed policy:
```bash
eksctl create iamserviceaccount   --cluster $CLUSTER   --region $AWS_REGION   --namespace kube-system   --name ebs-csi-controller-sa   --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy   --approve   --override-existing-serviceaccounts
```

Tell the EKS add‑on to use that role:
```bash
ROLE_ARN=$(kubectl -n kube-system get sa ebs-csi-controller-sa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')

aws eks create-addon   --cluster-name $CLUSTER   --addon-name aws-ebs-csi-driver   --service-account-role-arn "$ROLE_ARN"   --resolve-conflicts OVERWRITE
```

Verify:
```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-ebs-csi-driver
kubectl get csidriver | grep ebs.csi.aws.com
```

### 2.3 Make **gp3** the single default StorageClass

Create gp3 if needed:
```bash
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
```

Ensure **only** gp3 is default:
```bash
kubectl annotate sc gp2 storageclass.kubernetes.io/is-default-class- --overwrite 2>/dev/null || true
kubectl get sc
```

### 2.4 Install **AWS Load Balancer Controller** (ALB Ingress)

> One‑liner via Helm (uses IRSA created by the chart):
```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Replace with your VPC ID for the cluster
VPC_ID=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query "cluster.resourcesVpcConfig.vpcId" -o text)

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller   -n kube-system   --set clusterName=$CLUSTER   --set region=$AWS_REGION   --set vpcId=$VPC_ID   --set serviceAccount.create=true   --set serviceAccount.name=aws-load-balancer-controller

kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
```

---

## 3) Deploy MegaShop (manifests with fixes)

### 3.1 Download bundle
This bundle has:
- **Postgres fix** (`PGDATA=/var/lib/postgresql/data/pgdata`) to avoid `lost+found` issue
- **Gateway** uses `nginx:1.25-alpine` with app routing via ConfigMap
- PVCs use **gp3** (cluster default)

**Download**: use the `hiqode-megashop-dockerhub-k8s-fixed.zip` from this chat (next to these instructions).  
_Unzip and `cd` into the folder that contains `k8s/`._

### 3.2 Create namespace + imagePullSecret for Docker Hub (private)
```bash
export DOCKERHUB_USER=30051989
export DOCKERHUB_TOKEN=<your_dockerhub_access_token>

kubectl apply -f k8s/00-namespace.yaml

kubectl -n megashop create secret docker-registry dockerhub-cred   --docker-server=index.docker.io   --docker-username="$DOCKERHUB_USER"   --docker-password="$DOCKERHUB_TOKEN"   --docker-email="noreply@example.com"   --dry-run=client -o yaml | kubectl apply -f -

# Attach secret to default SA so all pods can pull
kubectl -n megashop patch serviceaccount default   -p '{"imagePullSecrets":[{"name":"dockerhub-cred"}]}'
```

### 3.3 Apply config, data layer, apps, ingress
```bash
kubectl apply -f k8s/01-gateway-config.yaml
kubectl apply -f k8s/02-data.yaml        # StatefulSets for Postgres/Mongo/RabbitMQ (PVCs on gp3)
kubectl apply -f k8s/03-apps.yaml        # Uses images from 30051989/hiqode:<service-tag>
kubectl apply -f k8s/04-ingress.yaml     # ALB Ingress (internet-facing)

# Wait for rollouts
for d in frontend auth catalog orders payments gateway; do
  kubectl -n megashop rollout status deploy/$d --timeout=180s || true
done
```

### 3.4 Seed products
```bash
kubectl apply -f k8s/05-seed-job.yaml
kubectl -n megashop logs -f job/seed-catalog --tail=100
```

### 3.5 Open the app
```bash
ALB=$(kubectl -n megashop get ingress megashop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://$ALB/"
```

---

## 4) Troubleshooting (field‑tested)

### EBS CSI controller CrashLoop with 403 `UnauthorizedOperation`
- Ensure **IRSA** is set for `kube-system/ebs-csi-controller-sa` and the **EKS add‑on** uses that role:
  ```bash
  kubectl -n kube-system get sa ebs-csi-controller-sa -o yaml | grep role-arn -n
  kubectl -n kube-system logs deploy/ebs-csi-controller -c ebs-plugin --tail=100
  aws eks update-addon --cluster-name $CLUSTER --addon-name aws-ebs-csi-driver --service-account-role-arn "$ROLE_ARN" --resolve-conflicts OVERWRITE
  ```

### PVCs `Pending`
- Ensure **gp3** is the only default SC and the EBS CSI controller pods are **Ready**:
  ```bash
  kubectl get sc
  kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-ebs-csi-driver
  ```
- Recreate stuck PVCs (scale down StatefulSets, delete PVCs, scale up).

### Postgres `initdb: directory exists and not empty (lost+found)`
- We already set `PGDATA=/var/lib/postgresql/data/pgdata`. If you see it again, confirm env on the Pod:
  ```bash
  kubectl -n megashop exec -it postgres-0 -- env | grep PGDATA
  ```

### `ImagePullBackOff` for gateway
- We intentionally use public `nginx:1.25-alpine` with config from ConfigMap. Confirm image + mount:
  ```bash
  kubectl -n megashop get deploy gateway -o yaml | grep image:
  kubectl -n megashop describe pod -l app=gateway | grep -A2 Mounts
  ```

### App healthy but no products
```bash
kubectl apply -f k8s/05-seed-job.yaml
kubectl -n megashop logs -f job/seed-catalog --tail=100
```

### Mail not visible
```bash
kubectl -n megashop port-forward deploy/mailhog 8025:8025
# open http://localhost:8025
```

---

## 5) Demo storyline & talking points

1. **Architecture overview** (gateway → frontend → services → data services).  
   - Show `k8s/01-gateway-config.yaml` routes (/ → frontend, /api/* → services).  
   - Mention RabbitMQ + MailHog integration (worker optional).

2. **Resilience**: replicas=2 for stateless services, EBS‑backed StatefulSets for data.

3. **Ingress**: ALB Ingress with a single DNS for the whole app.

4. **Images**: private Docker Hub with **service‑as‑tag** (e.g., `30051989/hiqode:hiqode-megashop-frontend`).

5. **Monitoring hooks** (optional, if installed): Prometheus/Grafana + Loki/Promtail dashboards.

6. **Demo flow**
   - Browse storefront → categories → add to cart → checkout
   - Login (demo creds) → apply coupon → Pay & Place Order
   - MailHog: show order email
   - RabbitMQ UI (optional): show queues (port-forward if internal)

7. **Ops runbook highlights**
   - Rolling updates: `kubectl set image deploy/frontend frontend=30051989/hiqode:hiqode-megashop-frontend-v2`  
   - Rollback: `kubectl -n megashop rollout undo deploy/frontend`

---

## Appendix — Image references used

- `30051989/hiqode:hiqode-megashop-frontend`
- `30051989/hiqode:hiqode-megashop-auth`
- `30051989/hiqode:hiqode-megashop-catalog`
- `30051989/hiqode:hiqode-megashop-orders`
- `30051989/hiqode:hiqode-megashop-payments`
- `nginx:1.25-alpine` (gateway — config via ConfigMap)
- Data plane: `postgres:16-alpine`, `mongo:7-jammy`, `rabbitmq:3-management-alpine`, `redis:7-alpine`, `mailhog/mailhog:v1.0.1`

Happy shipping 🚀
