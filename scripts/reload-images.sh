#!/bin/bash
echo "=== Reloading all images into kind ==="
IMAGES_DIR="/home/ubuntu/images"

for tar in ingress-controller certgen node-backend python-backend frontend mongo; do
  echo "Loading $tar..."
  docker exec -i kind-cluster-control-plane ctr --namespace=k8s.io images import - < $IMAGES_DIR/$tar.tar 2>/dev/null || echo "Skipped $tar on control-plane"
  docker exec -i kind-cluster-worker ctr --namespace=k8s.io images import - < $IMAGES_DIR/$tar.tar 2>/dev/null || echo "Skipped $tar on worker"
done

echo "=== Done! ==="
docker exec kind-cluster-worker crictl images
