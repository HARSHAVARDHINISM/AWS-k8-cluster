#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# Update packages

apt-get update

#hostname 

hostnamectl set-hostname worker1


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

sudo systemctl start crio
sudo systemctl enable -- now crio

# Install unzip and curl if not already present
sudo apt install -y unzip curl

# Download AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Extract
unzip awscliv2.zip

# Install
sudo ./aws/install

# Wait for join command
while true; do
JOIN_CMD=$(aws ssm get-parameter \
--name "/k8s/join-command" \
--query "Parameter.Value" \
--output text \
--region us-east-2 2>/dev/null)

if [ ! -z "$JOIN_CMD" ]; then
break
fi

sleep 15
done

# Join cluster
$JOIN_CMD
