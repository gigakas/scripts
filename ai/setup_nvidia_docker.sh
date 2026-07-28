#!/bin/bash
set -e

echo "=== 1. Limpiando repositorios viejos o corruptos ==="
sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
sudo rm -rf /etc/cdi/nvidia*.yaml

echo "=== 2. Configurando repositorio oficial de NVIDIA Container Toolkit ==="
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg2

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

echo "=== 3. Instalando NVIDIA Container Toolkit ==="
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

echo "=== 4. Configurando el Runtime clásico de Docker ==="
sudo nvidia-ctk runtime configure --runtime=docker

echo "=== 5. Forzando el Modo CDI (Requerido para Ubuntu modernos) ==="
# Esto configura nvidia-ctk para operar en modo CDI nativo
sudo nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true

echo "=== 6. Generando especificación CDI limpia ==="
sudo mkdir -p /etc/cdi
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

echo "=== 7. Reiniciando servicios del sistema ==="
sudo systemctl daemon-reload
sudo systemctl restart nvidia-cdi-refresh.service || true
sudo systemctl restart docker

echo "========================================================="
echo " ¡Configuración completada con éxito!"
echo "========================================================="
