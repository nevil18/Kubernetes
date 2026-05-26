#!/bin/bash
echo "=== Saving all images locally ==="
mkdir -p /home/ubuntu/images

# Force pull latest versions
docker pull nevilanghan/cksfinbot-node-backend:latest
docker pull nevilanghan/cksfinbot-python-backend:latest
docker pull nevilanghan/cksfinbot-frontend:latest

docker save registry.k8s.io/ingress-nginx/controller:v1.11.3 -o /home/ubuntu/images/ingress-controller.tar
docker save registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.4 -o /home/ubuntu/images/certgen.tar
docker save nevilanghan/cksfinbot-node-backend:latest -o /home/ubuntu/images/node-backend.tar
docker save nevilanghan/cksfinbot-python-backend:latest -o /home/ubuntu/images/python-backend.tar
docker save nevilanghan/cksfinbot-frontend:latest -o /home/ubuntu/images/frontend.tar
docker save mongo:7.0 -o /home/ubuntu/images/mongo.tar
docker save kindest/node:v1.31.0 -o /home/ubuntu/images/kindest-node.tar

echo "=== Images saved to /home/ubuntu/images/ ==="
ls -lh /home/ubuntu/images/
