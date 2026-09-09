#!/bin/bash
# Orquestador: ejecuta en orden los scripts para levantar un cluster de
# Kubernetes con kubeadm en Ubuntu 24.04.
#
# Uso:
#   En el nodo control plane:
#     sudo bash setup-cluster.sh --control-plane
#
#   En cada nodo worker (pasa el join command):
#     sudo bash setup-cluster.sh --worker --join-args="192.168.1.1:6443 --token abc --discovery-token-ca-cert-hash sha256:xyz"
#
# O ejecuta los scripts individualmente en orden si preferis mas control.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_step() {
  local script="$1"
  local name="$2"
  echo ""
  echo "############################################################"
  echo "# ${name}"
  echo "############################################################"
  bash "${SCRIPT_DIR}/${script}"
}

MODE=""
JOIN_ARGS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --control-plane) MODE="cp" ;;
    --worker) MODE="worker" ;;
    --join-args=*) JOIN_ARGS="${1#*=}" ;;
    *)
      echo "[-] Argumento desconocido: $1"
      echo "  Uso:"
      echo "    sudo bash setup-cluster.sh --control-plane"
      echo "    sudo bash setup-cluster.sh --worker --join-args=\"...\""
      exit 1
      ;;
  esac
  shift
done

if [ -z "$MODE" ]; then
  echo "[-] Debes especificar --control-plane o --worker"
  exit 1
fi

echo "=========================================================="
echo " Setup de Cluster Kubernetes (kubeadm)"
echo "=========================================================="
echo "[+] Modo: ${MODE}"
echo ""

run_step "00-prerequisites.sh" "[1/4] Prerrequisitos del sistema"
run_step "01-install-containerd.sh" "[2/4] Instalar containerd"
run_step "02-install-kubeadm.sh" "[3/4] Instalar kubeadm, kubelet, kubectl"

if [ "$MODE" = "cp" ]; then
  run_step "03-init-control-plane.sh" "[4/4] Inicializar Control Plane"
  run_step "04-install-cni.sh" "[5/5] Instalar CNI (Calico)"
elif [ "$MODE" = "worker" ]; then
  if [ -z "$JOIN_ARGS" ]; then
    echo "[-] Modo worker requiere --join-args=\"...\""
    echo "    Copia el comando desde el control plane:"
    echo "    cat /root/kubeadm-join-command.sh"
    exit 1
  fi
  echo ""
  echo "############################################################"
  echo "# [4/4] Unir Worker al cluster"
  echo "############################################################"
  bash "${SCRIPT_DIR}/05-join-worker.sh" $JOIN_ARGS
fi

echo ""
echo "=========================================================="
echo " Setup completado"
echo "=========================================================="
