#!/bin/bash
sleep 15

# Stop nginx (conflicts with Kind port 80)
systemctl stop nginx 2>/dev/null || true

# Start worker first
docker start kind-cluster-worker 2>/dev/null || true
sleep 5

# Assign IP to Kind bridge before starting control plane
ip addr add 172.19.0.1/16 dev br-ee77f4ede037 2>/dev/null || true

# Start control plane
docker start kind-cluster-control-plane 2>/dev/null || true
sleep 90

# Restore iptables
netfilter-persistent reload
iptables -t nat -I PREROUTING 1 -s 172.19.0.2 -j RETURN
iptables -t nat -I PREROUTING 1 -s 10.244.1.0/24 -j RETURN
iptables -t nat -I PREROUTING 1 -s 10.244.0.0/16 -j RETURN
iptables -t nat -I PREROUTING 1 -s 172.19.0.0/16 -j RETURN
iptables -t nat -A POSTROUTING -s 172.19.0.0/16 -o enp39s0 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.244.0.0/16 -o enp39s0 -j MASQUERADE
iptables -I DOCKER-USER -i br-ee77f4ede037 -o enp39s0 -j ACCEPT
iptables -I DOCKER-USER -i enp39s0 -o br-ee77f4ede037 -j ACCEPT

echo "Startup complete $(date)" >> /home/ubuntu/startup.log
