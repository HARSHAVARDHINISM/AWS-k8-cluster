#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
export HOME=/home/ubuntu

# Update packages

apt-get update

# Install iptables persistence

apt-get install -y iptables-persistent netfilter-persistent

# Enable IP forwarding immediately

sysctl -w net.ipv4.ip_forward=1

# Enable IP forwarding permanently

echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Detect the primary network interface (ens5, eth0, etc.)

IFACE=$(ip route | awk '/default/ {print $5}')

# Configure NAT

iptables -t nat -A POSTROUTING -o ${IFACE} -j MASQUERADE
iptables -A FORWARD -i ${IFACE} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -o ${IFACE} -j ACCEPT

# Save iptables rules

netfilter-persistent save
systemctl enable netfilter-persistent

# Hostname

hostnamectl set-hostname master

# /etc/hosts (replace with your actual private IPs)

cat <<EOF >> /etc/hosts
10.0.1.174 master
10.0.2.211 worker1
10.0.2.167 worker2
EOF

KUBERNETES_VERSION=v1.34
CRIO_VERSION=v1.34


apt-get update
apt-get install -y software-properties-common curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key |
    gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" |
    tee /etc/apt/sources.list.d/kubernetes.list

curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key |
    gpg --batch --yes --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" |
    tee /etc/apt/sources.list.d/cri-o.list

apt-get update
apt-get install -y cri-o kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable --now kubelet


mv /etc/cni/net.d/10-crio-bridge.conflist.disabled /etc/cni/net.d/10-crio-bridge.conflist

systemctl start crio.service
systemctl enable crio.service

#initialising Kubernetes cluster 

sudo kubeadm init --pod-network-cidr=192.168.0.0/16

#configuring user

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#installing calico 

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/calico.yaml

# Wait for the API server and Calico to settle

sleep 90

# Install unzip and curl if not already present
sudo apt install -y unzip curl

# Download AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Extract
unzip awscliv2.zip

# Install
sudo ./aws/install

# Generate join command
JOIN_CMD=$(kubeadm token create --print-join-command)

# Save to SSM Parameter Store
aws ssm put-parameter \
  --name "/k8s/join-command" \
  --value "$JOIN_CMD" \
  --type "String" \
  --overwrite \
  --region "us-east-2"
