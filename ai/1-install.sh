#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo -e "\n${CYAN}=== $* ===${NC}\n"; }

ask_yes_no() {
    local prompt="$1"
    local default_value="${2:-y}"
    local suffix="[Y/n]"

    if [ "$default_value" = "n" ]; then
        suffix="[y/N]"
    fi

    read -r -p "$prompt $suffix " answer
    answer="${answer:-$default_value}"

    case "${answer,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

sudo_prompt() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    echo -e "${YELLOW}Este script necesita sudo para instalar paquetes.${NC}"
    sudo -v || { err "Se requiere sudo."; exit 1; }
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" 2>/dev/null || exit
    done 2>/dev/null &
}

# ── 1. Detectar SO ────────────────────────────
detect_os() {
    if ! command -v lsb_release >/dev/null 2>&1; then
        info "Instalando lsb-release..."
        sudo apt-get update -qq && sudo apt-get install -y -qq lsb-release
    fi

    local distro
    distro="$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    if [ "$distro" != "ubuntu" ]; then
        err "Este script solo funciona en Ubuntu. Detectado: $distro"
        err "Instala Docker y NVIDIA Container Toolkit manualmente, luego corre 3-deploy.sh"
        exit 1
    fi

    local codename
    codename="$(lsb_release -cs)"

    info "Ubuntu $(lsb_release -rs) ($codename) detectado."
}

# ── 2. Instalar Docker ────────────────────────
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            info "Docker ya esta instalado y corriendo."
            return 0
        fi
        if sudo docker info >/dev/null 2>&1; then
            info "Docker ya esta instalado y corriendo (requiere sudo)."
            return 0
        fi

        info "Docker instalado pero el daemon no corre. Iniciandolo..."
        sudo systemctl start docker || true
        if sudo docker info >/dev/null 2>&1; then
            info "Docker daemon iniciado."
            return 0
        fi

        warn "No se pudo iniciar el daemon de Docker. Reinstalando..."
    fi

    if ! ask_yes_no "Docker no esta instalado. ¿Instalarlo desde el repo oficial de Docker?" "y"; then
        err "Docker es necesario. Abortando."
        exit 1
    fi

    info "Preparando el repositorio oficial de Docker..."

    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl

    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    local codename
    codename="$(lsb_release -cs)"

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    info "Instalando Docker Engine y Docker Compose..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo systemctl enable docker --now >/dev/null 2>&1 || true

    if [ "$(id -u)" -ne 0 ]; then
        info "Agregando el usuario '$USER' al grupo docker..."
        sudo usermod -aG docker "$USER"
        warn "Se agrego '$USER' al grupo docker. Cierra sesion y vuelve a entrar para usar docker sin sudo."
        warn "Por ahora, los comandos docker se ejecutaran con sudo."
    fi

    if ! sudo docker info >/dev/null 2>&1; then
        err "Docker se instalo pero no responde. Revisa: sudo systemctl status docker"
        exit 1
    fi

    info "Docker Engine $(sudo docker --version | awk '{print $3}' | tr -d ',') instalado."
    info "Docker Compose $(sudo docker compose version | awk '{print $NF}') instalado."
}

# ── 3. Instalar NVIDIA Container Toolkit ──────
install_nvidia_ctk() {
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        info "No se detecto GPU NVIDIA en el sistema."
        return 1
    fi

    if command -v nvidia-ctk >/dev/null 2>&1; then
        if sudo docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
            info "NVIDIA Container Toolkit ya instalado y funcionando."
            return 0
        fi
        warn "NVIDIA Container Toolkit instalado pero la GPU no responde. Reconfigurando..."
    else
        if ! ask_yes_no "¿Instalar NVIDIA Container Toolkit para acceso GPU desde Docker?" "y"; then
            warn "Sin NVIDIA Container Toolkit, vLLM y Ollama-GPU no funcionaran."
            return 1
        fi
    fi

    info "Limpiando repositorios viejos..."
    sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    sudo rm -rf /etc/cdi/nvidia*.yaml

    info "Configurando repositorio oficial de NVIDIA Container Toolkit..."
    sudo apt-get update -qq && sudo apt-get install -y -qq ca-certificates curl gnupg2

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

    info "Instalando NVIDIA Container Toolkit..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq nvidia-container-toolkit

    info "Configurando runtime NVIDIA en Docker..."
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true

    info "Generando especificacion CDI..."
    sudo mkdir -p /etc/cdi
    sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

    sudo systemctl daemon-reload
    sudo systemctl restart nvidia-cdi-refresh.service || true
    sudo systemctl restart docker

    info "Verificando acceso GPU desde Docker..."
    if sudo docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        info "GPU NVIDIA accesible desde Docker."
        return 0
    else
        warn "No se pudo verificar el acceso GPU desde Docker. vLLM no funcionara."
        warn "Puede que necesites reiniciar el sistema y correr este script de nuevo."
        return 1
    fi
}

# ── Main ──────────────────────────────────────
main() {
    title "Chatbot AI Runtime — Instalador completo"

    if [ ! -f "$SCRIPT_DIR/3-deploy.sh" ]; then
        err "No se encontro 3-deploy.sh en $SCRIPT_DIR. Los scripts deben estar en la misma carpeta."
        exit 1
    fi

    if [ ! -d "$SCRIPT_DIR/ai-runtime" ]; then
        err "No se encontro la carpeta ai-runtime/ en $SCRIPT_DIR."
        exit 1
    fi

    sudo_prompt
    detect_os

    title "Paso 1: Instalar y configurar Docker"
    install_docker

    title "Paso 2: NVIDIA Container Toolkit"
    install_nvidia_ctk || true

    title "Paso 3: Despliegue del backend de IA"
    info "Pasando el control a 3-deploy.sh para el despliegue..."

    bash "$SCRIPT_DIR/3-deploy.sh"
}

main "$@"
