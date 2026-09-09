#!/bin/bash
# Inicializa el control plane de Kubernetes con kubeadm init.
# Ejecutar SOLO en el nodo que sera el control plane (k8s-cp).
# Requiere que 00, 01 y 02 ya se hayan ejecutado.
# Al finalizar, imprime el comando kubeadm join para los workers.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

if systemctl is-active --quiet kubelet 2>/dev/null; then
  echo "[-] kubelet ya esta activo. Parece que kubeadm init ya se ejecuto."
  echo "    Si queres reiniciar el cluster, usa 'kubeadm reset' primero."
  exit 1
fi

echo "=========================================================="
echo " Inicializando el Control Plane (kubeadm init)"
echo "=========================================================="

CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"

echo "[+] POD CIDR: ${POD_CIDR}"

if [ -z "$CONTROL_PLANE_IP" ]; then
  CONTROL_PLANE_IP=$(ip -4 addr show scope global | grep inet | head -1 | awk '{print $2}' | cut -d/ -f1)
  echo "[+] IP del control plane detectada: ${CONTROL_PLANE_IP}"
  echo "    Si no es correcta, setea la variable: export CONTROL_PLANE_IP=192.168.x.y"
fi

if [ -z "$CONTROL_PLANE_IP" ]; then
  echo "[-] No se pudo detectar la IP. Seteala manualmente:"
  echo "    export CONTROL_PLANE_IP=192.168.171.101"
  exit 1
fi

echo ""
echo "[1/3] Ejecutando kubeadm init..."
echo "    --apiserver-advertise-address=${CONTROL_PLANE_IP}"
echo "    --pod-network-cidr=${POD_CIDR}"
echo ""
kubeadm init \
  --apiserver-advertise-address="${CONTROL_PLANE_IP}" \
  --pod-network-cidr="${POD_CIDR}" \
  --upload-certs 2>&1 | tee /tmp/kubeadm-init.log

echo ""
echo "[2/3] Configurando kubeconfig para el usuario no-root..."
REAL_USER="${SUDO_USER:-}"
if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
  REAL_USER=$(logname 2>/dev/null || echo "")
fi

if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
  USER_HOME=$(eval echo "~${REAL_USER}")
  mkdir -p "${USER_HOME}/.kube"
  cp -f /etc/kubernetes/admin.conf "${USER_HOME}/.kube/config"
  chown -R "${REAL_USER}:${REAL_USER}" "${USER_HOME}/.kube"
  echo "    kubeconfig copiado a ${USER_HOME}/.kube/config"
  echo "    El usuario '${REAL_USER}' ya puede usar kubectl sin sudo."
else
  echo "    [!] No se detecto usuario no-root. Para usar kubectl sin root:"
  echo "        mkdir -p \$HOME/.kube"
  echo "        sudo cp -f /etc/kubernetes/admin.conf \$HOME/.kube/config"
  echo "        sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
fi

# Tambien para el usuario root local
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config

echo ""
echo "[3/3] Guardando comando de join para los workers..."
JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null) || {
  # Si el token no funciona, extraer del log
  JOIN_CMD=$(grep -A1 "kubeadm join" /tmp/kubeadm-init.log | tr -d '\\\t' | head -1)
}
echo "$JOIN_CMD" > /root/kubeadm-join-command.sh
chmod 600 /root/kubeadm-join-command.sh

echo "=========================================================="
echo " Control Plane inicializado correctamente"
echo "=========================================================="
echo ""
echo " Proximo paso: ejecuta 04-install-cni.sh en este mismo nodo"
echo " para instalar el CNI (Calico)."
echo ""
echo " Comando para unir workers (copia esto y pegalo en cada worker):"
echo ""
echo "   ${JOIN_CMD}"
echo ""
echo " Este comando tambien se guardo en: /root/kubeadm-join-command.sh"
echo ""
echo " Para ver los nodos (despues del CNI):"
echo "   kubectl get nodes"
echo "=========================================================="
