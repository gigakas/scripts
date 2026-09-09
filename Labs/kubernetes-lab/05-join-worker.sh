#!/bin/bash
# Une un nodo worker al cluster de Kubernetes.
# Ejecutar en cada nodo worker DESPUES de que el control plane tenga CNI.
# Necesita el comando kubeadm join generado por 03-init-control-plane.sh.
# Requiere que 00, 01 y 02 ya se hayan ejecutado en este nodo.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

echo "=========================================================="
echo " Union de nodo Worker al cluster"
echo "=========================================================="

if [ -z "${1:-}" ]; then
  echo "[-] ERROR: Necesitas pasar los argumentos de kubeadm join."
  echo ""
  echo "  Uso: sudo bash 05-join-worker.sh <API_SERVER_IP>:<PORT> --token <TOKEN> --discovery-token-ca-cert-hash <HASH>"
  echo ""
  echo "  Ejemplo:"
  echo "    sudo bash 05-join-worker.sh 192.168.171.101:6443 \\"
  echo "      --token abc123.def456 \\"
  echo "      --discovery-token-ca-cert-hash sha256:abcdef..."
  echo ""
  echo "  Copia el comando completo desde el nodo control plane:"
  echo "    cat /root/kubeadm-join-command.sh  (en el CP)"
  exit 1
fi

echo "[+] Ejecutando: kubeadm join $*"
echo ""

kubeadm join "$@"

echo ""
echo "=========================================================="
echo " Worker unido al cluster correctamente"
echo "=========================================================="
echo ""
echo " Verifica desde el control plane:"
echo "   kubectl get nodes"
echo "=========================================================="
