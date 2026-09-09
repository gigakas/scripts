#!/bin/bash
# Prerrequisitos del sistema para Kubernetes (kubeadm).
# Aplica en todos los nodos del cluster (control plane y workers).
# Desactiva swap, carga modulos de kernel, configura sysctl.
# Soportado: Ubuntu 24.04.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

if ! grep -q -w -E '^ID=ubuntu' /etc/os-release; then
  echo "[-] Este script esta disenado para Ubuntu."
  echo "    Si estas en Debian, adaptalo manualmente (los modulos y sysctl son iguales,"
  echo "    pero los paquetes pueden variar)."
  exit 1
fi

echo "=========================================================="
echo " Prerrequisitos de Kubernetes (kubeadm)"
echo "=========================================================="

echo "[1/5] Desactivando swap (requerido por kubelet)..."
swapoff -a
sed -i '/\sswap\s/ s/^/# /' /etc/fstab
echo "    Swap desactivado y comentado en /etc/fstab."

echo "[2/5] Cargando modulos del kernel (overlay, br_netfilter)..."
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
echo "    Modulos cargados y configurados para persistir tras reboot."

echo "[3/5] Configurando parametros sysctl para trafico de red en puentes..."
cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null
echo "    Parametros sysctl aplicados."

echo "[4/5] Verificando hostname unico..."
echo "    Hostname actual: $(hostname)"
echo "    Asegurate de que cada nodo tenga un hostname distinto."
echo "    Si clonaste la VM, cambialo con: hostnamectl set-hostname <nuevo-nombre>"

echo "[5/5] Verificando product_uuid unico (importante si clonaste VMs)..."
if [ -f /sys/class/dmi/id/product_uuid ]; then
  echo "    product_uuid: $(cat /sys/class/dmi/id/product_uuid)"
else
  echo "    [!] No se encontro /sys/class/dmi/id/product_uuid (puede ser normal en algunos entornos)."
fi

echo "=========================================================="
echo " Prerrequisitos completados. Reiniciar no es necesario,"
echo " pero si queres verificar:"
echo "   sudo swapoff -v  (debe decir 'swapoff: /dev/...')"
echo "   lsmod | grep -E 'overlay|br_netfilter'"
echo "   sysctl net.bridge.bridge-nf-call-iptables"
echo "=========================================================="
