#!/bin/bash
# Instala kubeadm, kubelet y kubectl desde el repositorio oficial de Kubernetes.
# Aplica en todos los nodos del cluster (control plane y workers).
# Requiere que 00-prerequisites.sh y 01-install-containerd.sh ya se hayan ejecutado.
# Soportado: Ubuntu 24.04.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

echo "=========================================================="
echo " Instalador de kubeadm, kubelet y kubectl"
echo "=========================================================="

KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.33}"
echo "[+] Version de Kubernetes a instalar: ${KUBERNETES_VERSION}.x"
echo "    Para cambiar la version: export KUBERNETES_VERSION=1.32 y re-ejecuta."

echo "[1/5] Agregando la llave GPG de Kubernetes..."
mkdir -p /etc/apt/keyrings
if [ -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
  rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
fi
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "[2/5] Agregando el repositorio de Kubernetes..."
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

echo "[3/5] Instalando kubelet, kubeadm y kubectl..."
apt-get update
apt-get install -y kubelet kubeadm kubectl

echo "[4/5] Congelando versiones (apt-mark hold) para evitar actualizaciones accidentales..."
apt-mark hold kubelet kubeadm kubectl

echo "[5/5] Verificando instalacion..."
echo "    kubeadm: $(kubeadm version --output short 2>/dev/null || echo 'version no detectada')"
echo "    kubelet: $(kubelet --version 2>/dev/null || echo 'version no detectada')"
echo "    kubectl: $(kubectl version --client --output short 2>/dev/null || echo 'version no detectada')"

echo "=========================================================="
echo " kubeadm, kubelet y kubectl instalados"
echo " Nota: kubelet queda en estado 'activating' hasta que"
echo "       se haga 'kubeadm init' (CP) o 'kubeadm join' (worker)."
echo "       Esto es normal y esperado."
echo "=========================================================="
