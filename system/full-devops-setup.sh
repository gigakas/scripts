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

echo "=== 6. Installing K9s Dashboard ==="
sudo snap install k9s

echo "=================================================="
echo "     BOOTSTRAPPING KUBERNETES CLUSTER            "
echo "=================================================="

# Forzamos la ejecución de Kind usando el grupo docker recién creado
sg docker -c "kind create cluster --name lab-devops"

echo "=== 7. Validating Deployment ==="
sg docker -c "kubectl get nodes"

echo ""
echo "=================================================="
echo "  SUCCESS! Environment Ready.                     "
echo "  Type 'newgrp docker' to enable your profile.    "
echo "  Then type 'k9s' to explore your cluster!        "
echo "=================================================="

