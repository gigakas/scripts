#!/bin/bash
set -e

echo "=================================================="
echo "    STARTING FIXED DOCKER & K8S FULL SETUP        "
echo "=================================================="

echo "=== 1. Updating System Packages ==="
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release

echo "=== 2. Cleaning Residual Artifacts ==="
sudo rm -f /usr/local/bin/kind
rm -f ./kind
sudo rm -f /etc/apt/sources.list.d/docker.list

echo "=== 3. Installing Official Docker Engine ==="
# Descarga e instala la clave GPG oficial en /etc/apt/keyrings
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Añade el repositorio oficial apuntando a la clave instalada
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Actualiza los repositorios con la firma ya validada e instala Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== 4. Setting up Docker User Permissions ==="
sudo usermod -aG docker $USER

echo "=== 5. Downloading Kind Binary (Kubernetes in Docker) ==="
URL_KIND="https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-linux-amd64"
wget -q --show-progress "$URL_KIND" -O ./kind
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

echo "=== 6. Installing Kubectl (Kubernetes CLI) ==="
URL_KUBECTL="https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
wget -q --show-progress "$URL_KUBECTL" -O ./kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

echo "=== 7. Installing K9s Dashboard ==="
K9S_VERSION=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | grep -o '"tag_name": *"[^"]*"' | sed 's/.*"v\(.*\)".*/\1/')
wget -q --show-progress "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_amd64.tar.gz" -O ./k9s.tar.gz
tar -xzf ./k9s.tar.gz k9s
chmod +x ./k9s
sudo mv ./k9s /usr/local/bin/k9s
rm -f ./k9s.tar.gz

echo "=================================================="
echo "     BOOTSTRAPPING KUBERNETES CLUSTER            "
echo "=================================================="

# Forzamos la ejecución de Kind usando el grupo docker recién creado
sg docker -c "kind create cluster --name lab-devops"

echo "=== 8. Validating Deployment ==="
sg docker -c "kubectl get nodes"

echo ""
echo "=================================================="
echo "  SUCCESS! Environment Ready.                     "
echo "  Type 'newgrp docker' to enable your profile.    "
echo "  Then type 'k9s' to explore your cluster!        "
echo "=================================================="

