#!/bin/bash
# Instala y configura containerd como runtime de contenedores para Kubernetes.
# containerd es el runtime recomendado por kubeadm desde k8s 1.24+.
# Aplica en todos los nodos del cluster (control plane y workers).
# Requiere que 00-prerequisites.sh ya se haya ejecutado.
# Soportado: Ubuntu 24.04.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

echo "=========================================================="
echo " Instalador de containerd (runtime de k8s)"
echo "=========================================================="

echo "[1/6] Instalando containerd desde repos oficial de Docker..."
apt-get update
apt-get install -y containerd.io

echo "[2/6] Generando configuracion por defecto de containerd..."
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

echo "[3/6] Activando SystemdCgroup (requerido por kubeadm)..."
if grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
  echo "    SystemdCgroup ya esta en true. Omitiendo."
else
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  echo "    SystemdCgroup cambiado a true."
fi

echo "[4/6] Ajustando sandbox_image a registry.k8s.io/pause:3.10..."
PAUSE_VERSION="3.10"
if grep -q "sandbox_image" /etc/containerd/config.toml; then
  sed -i "s|sandbox_image = .*|sandbox_image = \"registry.k8s.io/pause:${PAUSE_VERSION}\"|" /etc/containerd/config.toml
else
  echo "    [!] No se encontro la linea sandbox_image. Agregandola manualmente."
  sed -i "/\[plugins.\"io.containerd.grpc.v1.cri\"\]/a \ \ sandbox_image = \"registry.k8s.io/pause:${PAUSE_VERSION}\"" /etc/containerd/config.toml
fi
echo "    sandbox_image configurada a registry.k8s.io/pause:${PAUSE_VERSION}"

echo "[5/6] Reiniciando containerd..."
systemctl restart containerd
systemctl enable containerd

echo "[6/6] Verificando que containerd esta corriendo..."
if systemctl is-active --quiet containerd; then
  echo "    containerd activo y corriendo."
else
  echo "[-] containerd no se inicio correctamente. Revisa: journalctl -xeu containerd"
  exit 1
fi

echo "=========================================================="
echo " containerd instalado correctamente"
echo "=========================================================="
