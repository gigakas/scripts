#!/bin/bash
# Instala el CNI (Calico) en el cluster.
# Ejecutar en el nodo control plane despues de kubeadm init.
# Calico usa el pod CIDR 10.244.0.0/16 configurado en kubeadm init.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[-] No se puede conectar al cluster."
  echo "    Ejecuta primero 03-init-control-plane.sh en este nodo."
  exit 1
fi

echo "=========================================================="
echo " Instalador de Calico (CNI)"
echo "=========================================================="

CALICO_VERSION="${CALICO_VERSION:-v3.30}"
echo "[+] Version de Calico: ${CALICO_VERSION}"

echo "[1/2] Aplicando el manifiesto de Calico (Tigera operator)..."
kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"
kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml"
echo "    Manifiestos de Calico aplicados."

echo "[2/2] Esperando a que los pods de Calico esten listos..."
echo "    Esto puede tomar 1-2 minutos la primera vez (descargando imagenes)..."
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=300s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l k8s-app=calico-kube-controllers -n calico-system --timeout=300s 2>/dev/null || true

echo ""
echo "=========================================================="
echo " Calico instalado"
echo "=========================================================="
echo ""
echo " Verifica con:"
echo "   kubectl get nodes"
echo "   kubectl get pods -n calico-system"
echo ""
echo " Cuando el control plane aparezca como 'Ready', ya podes"
echo " unir los workers con el comando de /root/kubeadm-join-command.sh"
echo "=========================================================="
