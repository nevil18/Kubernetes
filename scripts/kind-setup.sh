#!/bin/bash
set -euo pipefail

echo "=== Kind Fresh Setup ==="
IMAGES_DIR="/home/ubuntu/images"

# ── Stop nginx (conflicts with port 80) ───────────────────────
systemctl stop nginx 2>/dev/null || true

# ── Create Kind cluster ───────────────────────────────────────
echo "[0/7] Creating Kind cluster..."
kind delete cluster --name kind-cluster 2>/dev/null || true
kind create cluster --config /home/ubuntu/config.yml
echo "Kind cluster created ✅"

# ── Pull images if local tar not found ────────────────────────
echo "[1/7] Checking/Pulling images..."
mkdir -p $IMAGES_DIR

if [ ! -f "$IMAGES_DIR/ingress-controller.tar" ]; then
  echo "Pulling ingress controller..."
  docker pull --platform linux/amd64 registry.k8s.io/ingress-nginx/controller:v1.11.3
  docker save registry.k8s.io/ingress-nginx/controller:v1.11.3 -o $IMAGES_DIR/ingress-controller.tar
fi

if [ ! -f "$IMAGES_DIR/certgen.tar" ]; then
  echo "Pulling certgen..."
  docker pull --platform linux/amd64 registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.4
  docker save registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.4 -o $IMAGES_DIR/certgen.tar
fi

if [ ! -f "$IMAGES_DIR/node-backend.tar" ]; then
  echo "Pulling node-backend..."
  docker pull --platform linux/amd64 nevilanghan/cksfinbot-node-backend:latest
  docker save nevilanghan/cksfinbot-node-backend:latest -o $IMAGES_DIR/node-backend.tar
fi

if [ ! -f "$IMAGES_DIR/python-backend.tar" ]; then
  echo "Pulling python-backend..."
  docker pull --platform linux/amd64 nevilanghan/cksfinbot-python-backend:latest
  docker save nevilanghan/cksfinbot-python-backend:latest -o $IMAGES_DIR/python-backend.tar
fi

if [ ! -f "$IMAGES_DIR/frontend.tar" ]; then
  echo "Pulling frontend..."
  docker pull --platform linux/amd64 nevilanghan/cksfinbot-frontend:latest
  docker save nevilanghan/cksfinbot-frontend:latest -o $IMAGES_DIR/frontend.tar
fi

if [ ! -f "$IMAGES_DIR/mongo.tar" ]; then
  echo "Pulling mongo..."
  docker pull --platform linux/amd64 mongo:7.0
  docker save mongo:7.0 -o $IMAGES_DIR/mongo.tar
fi

echo "All images ready ✅"

# ── Load images into Docker ───────────────────────────────────
echo "[2/7] Loading images into Docker..."
docker load -i $IMAGES_DIR/ingress-controller.tar 2>/dev/null || true
docker load -i $IMAGES_DIR/certgen.tar 2>/dev/null || true
docker load -i $IMAGES_DIR/node-backend.tar 2>/dev/null || true
docker load -i $IMAGES_DIR/python-backend.tar 2>/dev/null || true
docker load -i $IMAGES_DIR/frontend.tar 2>/dev/null || true
docker load -i $IMAGES_DIR/mongo.tar 2>/dev/null || true
echo "Docker images loaded ✅"

# ── Load images into kind nodes ───────────────────────────────
echo "[3/7] Loading images into kind..."
for img in ingress-controller certgen node-backend python-backend frontend mongo; do
  docker exec -i kind-cluster-control-plane ctr --namespace=k8s.io images import - < $IMAGES_DIR/$img.tar
  docker exec -i kind-cluster-worker ctr --namespace=k8s.io images import - < $IMAGES_DIR/$img.tar
done
echo "Kind images loaded ✅"

# ── Ingress Nginx ─────────────────────────────────────────────
echo "[4/7] Installing Ingress Nginx..."
curl -o /tmp/ingress.yaml https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml
sed -i 's/@sha256:[a-f0-9]*//g' /tmp/ingress.yaml
kubectl apply -f /tmp/ingress.yaml
kubectl label node kind-cluster-control-plane ingress-ready=true --overwrite
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
echo "Ingress ready ✅"

# ── Metrics Server ────────────────────────────────────────────
echo "[5/7] Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' \
  2>/dev/null || true
echo "Metrics server applied ✅"

# ── VPA (optional) ────────────────────────────────────────────
echo "[6/7] Installing VPA..."
VPA_DIR="/home/ubuntu/autoscaler/vertical-pod-autoscaler"
if [ ! -d "$VPA_DIR" ]; then
  git clone --depth=1 https://github.com/kubernetes/autoscaler.git /home/ubuntu/autoscaler 2>/dev/null || true
fi
if [ -d "$VPA_DIR" ]; then
  cd "$VPA_DIR" && bash hack/vpa-up.sh 2>/dev/null || echo "VPA install skipped"
  cd ~
fi
echo "VPA step done ✅"

# ── Deploy App ────────────────────────────────────────────────
echo "[7/7] Deploying app..."
cd /home/ubuntu/project/CKsFinBot/k8s
kubectl apply -f namespace.yml
kubectl apply -f mongo-secret.yml -f mongo-configmap.yml -f mongo-init-configmap.yaml
kubectl apply -f mongo-pv.yml -f mongo-statefulset.yml -f mongo-service.yml
kubectl apply -f node-backend-secret.yml -f node-backend-configmap.yml
kubectl apply -f node-backend-deployment.yml -f node-backend-service.yml -f node-backend-hpa.yml
kubectl apply -f python-backend-secret.yml -f python-backend-configmap.yml
kubectl apply -f python-backend-deployment.yml -f python-backend-service.yml
kubectl apply -f frontend-configmap.yml -f frontend-deployment.yml -f frontend-service.yml
kubectl apply -f ingress-merged.yaml
kubectl apply -f vpa.yml 2>/dev/null || echo "VPA resources skipped"
echo "App deployed ✅"

# ── Wait and fix MongoDB ──────────────────────────────────────
echo "Waiting for MongoDB..."
kubectl wait --for=condition=ready pod/mongo-0 -n finbot --timeout=180s

USER_EXISTS=$(kubectl exec -n finbot mongo-0 -- mongosh --quiet \
  --eval "db.getSiblingDB('admin').getUsers().users.length" 2>/dev/null || echo "0")

if [ "$USER_EXISTS" = "0" ] || [ -z "$USER_EXISTS" ]; then
  echo "Creating MongoDB user..."
  kubectl exec -n finbot mongo-0 -- mongosh --quiet --eval "
    db.getSiblingDB('admin').createUser({
      user: 'finbotuser',
      pwd:  'finbotpass',
      roles: [{role: 'root', db: 'admin'}]
    })"
  echo "MongoDB user created ✅"
else
  echo "MongoDB user already exists ✅"
fi

kubectl rollout restart deployment/node-backend -n finbot
sleep 20

# ── Fix public IP routing ─────────────────────────────────────
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.route_localnet=1
sudo sysctl -w net.ipv4.conf.enp39s0.route_localnet=1
sudo iptables -t nat -D PREROUTING -i enp39s0 -p tcp --dport 80 -j DNAT --to-destination 127.0.0.1:80 2>/dev/null || true
sudo iptables -t nat -D PREROUTING -i enp39s0 -p tcp --dport 443 -j DNAT --to-destination 127.0.0.1:443 2>/dev/null || true
sudo iptables -t nat -I PREROUTING -i enp39s0 -p tcp --dport 80 -j DNAT --to-destination 127.0.0.1:80
sudo iptables -t nat -I PREROUTING -i enp39s0 -p tcp --dport 443 -j DNAT --to-destination 127.0.0.1:443
echo "Public IP routing fixed ✅"

# ── Fix pod internet access (MUST come after public IP rules) ──
sudo iptables -t nat -I PREROUTING 1 -s 172.19.0.2 -j RETURN
sudo iptables -t nat -I PREROUTING 1 -s 10.244.1.0/24 -j RETURN
sudo iptables -t nat -I PREROUTING 1 -s 10.244.0.0/16 -j RETURN
sudo iptables -t nat -I PREROUTING 1 -s 172.19.0.0/16 -j RETURN
sudo iptables -t nat -A POSTROUTING -s 172.19.0.0/16 -o enp39s0 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 10.244.0.0/16 -o enp39s0 -j MASQUERADE
sudo iptables -I DOCKER-USER -i br-ee77f4ede037 -o enp39s0 -j ACCEPT
sudo iptables -I DOCKER-USER -i enp39s0 -o br-ee77f4ede037 -j ACCEPT
sudo netfilter-persistent save
echo "Pod internet access fixed ✅"

# ── Increase python-backend resources ─────────────────────────
kubectl patch deployment python-backend -n finbot --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "3Gi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "1Gi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/timeoutSeconds", "value": 30},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/failureThreshold", "value": 5},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds", "value": 60}
]'
echo "Python backend resources updated ✅"

echo "=== Kind Setup Complete ==="
kubectl get pods -n finbot
curl -s http://localhost/ | head -3

# ── Wait for node-backend to be ready then fix frontend ───────
echo "Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod -l app=node-backend -n finbot --timeout=120s
kubectl wait --for=condition=ready pod -l app=python-backend -n finbot --timeout=120s

# ── Copy latest frontend build ────────────────────────────────
FRONTEND_POD=$(kubectl get pods -n finbot -l app=finbot-frontend -o jsonpath='{.items[0].metadata.name}')
if [ -d "/home/ubuntu/project/CKsFinBot/Frontend/dist" ]; then
  kubectl cp /home/ubuntu/project/CKsFinBot/Frontend/dist/. finbot/$FRONTEND_POD:/usr/share/nginx/html/
  echo "Frontend build copied ✅"
fi

echo "=== All done! App is ready at http://23.21.187.113 ==="
