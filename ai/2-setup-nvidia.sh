#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

if [ "$(id -u)" -ne 0 ]; then
    err "Este script debe ejecutarse con sudo: sudo ./2-setup-nvidia.sh"
    exit 1
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
    err "No se detecto GPU NVIDIA (nvidia-smi no encontrado). Instala los drivers NVIDIA primero."
    exit 1
fi

info "GPU detectada:"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null \
    | awk -F', ' '{printf "  - %s (%s VRAM)\n", $1, $2}'

# ---- Verificar si ya esta configurado ----
if command -v nvidia-ctk >/dev/null 2>&1; then
    if docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        info "NVIDIA Container Toolkit ya esta instalado y funcionando. No hay nada que hacer."
        exit 0
    fi
    warn "NVIDIA Container Toolkit instalado pero no funciona. Reconfigurando..."
fi

# ---- Paso 1: limpiar repos viejos ----
echo "=== 1. Limpiando repositorios viejos o corruptos ==="
rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
rm -rf /etc/cdi/nvidia*.yaml

# ---- Paso 2: agregar repo oficial ----
echo "=== 2. Configurando repositorio oficial de NVIDIA Container Toolkit ==="
apt-get update -qq && apt-get install -y -qq ca-certificates curl gnupg2

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

# ---- Paso 3: instalar ----
echo "=== 3. Instalando NVIDIA Container Toolkit ==="
apt-get update -qq
apt-get install -y -qq nvidia-container-toolkit

# ---- Paso 4: configurar runtime Docker ----
echo "=== 4. Configurando runtime NVIDIA en Docker ==="
nvidia-ctk runtime configure --runtime=docker
nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true

# ---- Paso 5: CDI ----
echo "=== 5. Generando especificacion CDI ==="
mkdir -p /etc/cdi
nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# ---- Paso 6: reiniciar Docker ----
echo "=== 6. Reiniciando Docker ==="
systemctl daemon-reload
systemctl restart nvidia-cdi-refresh.service || true
systemctl restart docker

# ---- Verificar ----
echo "=== 7. Verificando acceso GPU desde Docker ==="
if docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
    info "Configuracion completada con exito. GPU NVIDIA accesible desde Docker."
else
    warn "No se pudo verificar el acceso GPU desde Docker."
    warn "Puede que necesites reiniciar el sistema y correr este script de nuevo."
    exit 1
fi
