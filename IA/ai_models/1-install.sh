#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
LANGUAGE_CODE=""

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo -e "\n${CYAN}=== $* ===${NC}\n"; }

text() {
    if [ "$LANGUAGE_CODE" = "es" ]; then
        printf '%s' "$1"
    else
        printf '%s' "$2"
    fi
}

choose_language() {
    echo "=============================================="
    echo " Seleccione un idioma / Select a language"
    echo "=============================================="
    echo " 1) Español"
    echo " 2) English"

    while true; do
        read -r -p "Opción / Option [1-2]: " language_option
        case "$language_option" in
            1) LANGUAGE_CODE="es"; return ;;
            2) LANGUAGE_CODE="en"; return ;;
            *) echo "Opción no válida / Invalid option" ;;
        esac
    done
}

ask_yes_no() {
    local prompt="$1"
    local default_value="${2:-y}"
    local suffix="[Y/n]"

    if [ "$default_value" = "n" ]; then
        suffix="$(text "[s/N]" "[y/N]")"
    elif [ "$LANGUAGE_CODE" = "es" ]; then
        suffix="[S/n]"
    fi

    read -r -p "$prompt $suffix " answer
    answer="${answer:-$default_value}"

    case "${answer,,}" in
        y|yes|s|si|sí) return 0 ;;
        *)     return 1 ;;
    esac
}

sudo_prompt() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    echo -e "${YELLOW}$(text "Este script necesita sudo para instalar paquetes." "This script needs sudo to install packages.")${NC}"
    sudo -v || { err "$(text "Se requiere sudo." "sudo access is required.")"; exit 1; }
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" 2>/dev/null || exit
    done 2>/dev/null &
}

# ── 1. Detectar SO ────────────────────────────
detect_os() {
    if ! command -v lsb_release >/dev/null 2>&1; then
        info "$(text "Instalando lsb-release..." "Installing lsb-release...")"
        sudo apt-get update -qq && sudo apt-get install -y -qq lsb-release
    fi

    local distro
    distro="$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    if [ "$distro" != "ubuntu" ]; then
        err "$(text "Este script solo funciona en Ubuntu. Detectado: $distro" "This script only works on Ubuntu. Detected: $distro")"
        err "$(text "Instala Docker y NVIDIA Container Toolkit manualmente, luego ejecuta 3-deploy.sh." "Install Docker and NVIDIA Container Toolkit manually, then run 3-deploy.sh.")"
        exit 1
    fi

    local codename
    codename="$(lsb_release -cs)"

    info "$(text "Ubuntu $(lsb_release -rs) ($codename) detectado." "Ubuntu $(lsb_release -rs) ($codename) detected.")"
}

# ── 2. Instalar Docker ────────────────────────
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            info "$(text "Docker ya está instalado y funcionando." "Docker is already installed and running.")"
            return 0
        fi
        if sudo docker info >/dev/null 2>&1; then
            info "$(text "Docker ya está instalado y funcionando (requiere sudo)." "Docker is already installed and running (requires sudo).")"
            return 0
        fi

        info "$(text "Docker está instalado, pero el daemon no se está ejecutando. Iniciándolo..." "Docker is installed, but the daemon is not running. Starting it...")"
        sudo systemctl start docker || true
        if sudo docker info >/dev/null 2>&1; then
            info "$(text "Daemon de Docker iniciado." "Docker daemon started.")"
            return 0
        fi

        warn "$(text "No se pudo iniciar el daemon de Docker. Reinstalando..." "Could not start the Docker daemon. Reinstalling...")"
    fi

    if ! ask_yes_no "$(text "Docker no está instalado. ¿Instalarlo desde el repositorio oficial de Docker?" "Docker is not installed. Install it from the official Docker repository?")" "y"; then
        err "$(text "Docker es necesario. Abortando." "Docker is required. Aborting.")"
        exit 1
    fi

    info "$(text "Preparando el repositorio oficial de Docker..." "Preparing the official Docker repository...")"

    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl

    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    local codename
    codename="$(lsb_release -cs)"

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    info "$(text "Instalando Docker Engine y Docker Compose..." "Installing Docker Engine and Docker Compose...")"
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo systemctl enable docker --now >/dev/null 2>&1 || true

    if [ "$(id -u)" -ne 0 ]; then
        info "$(text "Agregando el usuario '$USER' al grupo docker..." "Adding user '$USER' to the docker group...")"
        sudo usermod -aG docker "$USER"
        warn "$(text "Se agregó '$USER' al grupo docker. Cierra sesión y vuelve a entrar para usar Docker sin sudo." "'$USER' was added to the docker group. Log out and back in to use Docker without sudo.")"
        warn "$(text "Por ahora, los comandos de Docker se ejecutarán con sudo." "For now, Docker commands will run with sudo.")"
    fi

    if ! sudo docker info >/dev/null 2>&1; then
        err "$(text "Docker se instaló, pero no responde. Revisa: sudo systemctl status docker" "Docker was installed but is not responding. Check: sudo systemctl status docker")"
        exit 1
    fi

    info "$(text "Docker Engine $(sudo docker --version | awk '{print $3}' | tr -d ',') instalado." "Docker Engine $(sudo docker --version | awk '{print $3}' | tr -d ',') installed.")"
    info "$(text "Docker Compose $(sudo docker compose version | awk '{print $NF}') instalado." "Docker Compose $(sudo docker compose version | awk '{print $NF}') installed.")"
}

# ── 3. Instalar NVIDIA Container Toolkit ──────
install_nvidia_ctk() {
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        info "$(text "No se detectó una GPU NVIDIA en el sistema." "No NVIDIA GPU was detected in the system.")"
        return 1
    fi

    if command -v nvidia-ctk >/dev/null 2>&1; then
        if sudo docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
            info "$(text "NVIDIA Container Toolkit ya está instalado y funcionando." "NVIDIA Container Toolkit is already installed and working.")"
            return 0
        fi
        warn "$(text "NVIDIA Container Toolkit está instalado, pero la GPU no responde. Reconfigurando..." "NVIDIA Container Toolkit is installed, but the GPU is not responding. Reconfiguring...")"
    else
        if ! ask_yes_no "$(text "¿Instalar NVIDIA Container Toolkit para acceder a la GPU desde Docker?" "Install NVIDIA Container Toolkit to access the GPU from Docker?")" "y"; then
            warn "$(text "Sin NVIDIA Container Toolkit, vLLM y Ollama-GPU no funcionarán." "Without NVIDIA Container Toolkit, vLLM and Ollama-GPU will not work.")"
            return 1
        fi
    fi

    info "$(text "Limpiando repositorios antiguos..." "Removing old repositories...")"
    sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    sudo rm -rf /etc/cdi/nvidia*.yaml

    info "$(text "Configurando el repositorio oficial de NVIDIA Container Toolkit..." "Configuring the official NVIDIA Container Toolkit repository...")"
    sudo apt-get update -qq && sudo apt-get install -y -qq ca-certificates curl gnupg2

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

    info "$(text "Instalando NVIDIA Container Toolkit..." "Installing NVIDIA Container Toolkit...")"
    sudo apt-get update -qq
    sudo apt-get install -y -qq nvidia-container-toolkit

    info "$(text "Configurando el runtime de NVIDIA en Docker..." "Configuring the NVIDIA runtime in Docker...")"
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true

    info "$(text "Generando la especificación CDI..." "Generating the CDI specification...")"
    sudo mkdir -p /etc/cdi
    sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

    sudo systemctl daemon-reload
    sudo systemctl restart nvidia-cdi-refresh.service || true
    sudo systemctl restart docker

    info "$(text "Verificando el acceso a la GPU desde Docker..." "Verifying GPU access from Docker...")"
    if sudo docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        info "$(text "La GPU NVIDIA es accesible desde Docker." "The NVIDIA GPU is accessible from Docker.")"
        return 0
    else
        warn "$(text "No se pudo verificar el acceso a la GPU desde Docker. vLLM no funcionará." "Could not verify GPU access from Docker. vLLM will not work.")"
        warn "$(text "Es posible que necesites reiniciar el sistema y ejecutar este script nuevamente." "You may need to restart the system and run this script again.")"
        return 1
    fi
}

# ── Main ──────────────────────────────────────
main() {
    choose_language
    title "$(text "Chatbot AI Runtime — Instalador completo" "Chatbot AI Runtime — Full installer")"

    if [ ! -f "$SCRIPT_DIR/3-deploy.sh" ]; then
        err "$(text "No se encontró 3-deploy.sh en $SCRIPT_DIR. Los scripts deben estar en la misma carpeta." "3-deploy.sh was not found in $SCRIPT_DIR. The scripts must be in the same directory.")"
        exit 1
    fi

    if [ ! -d "$SCRIPT_DIR/ai-runtime" ]; then
        err "$(text "No se encontró el directorio ai-runtime/ en $SCRIPT_DIR." "The ai-runtime/ directory was not found in $SCRIPT_DIR.")"
        exit 1
    fi

    sudo_prompt
    detect_os

    title "$(text "Paso 1: Instalar y configurar Docker" "Step 1: Install and configure Docker")"
    install_docker

    title "$(text "Paso 2: NVIDIA Container Toolkit" "Step 2: NVIDIA Container Toolkit")"
    install_nvidia_ctk || true

    title "$(text "Paso 3: Despliegue del backend de IA" "Step 3: Deploy the AI backend")"
    info "$(text "Pasando el control a 3-deploy.sh para el despliegue..." "Passing control to 3-deploy.sh for deployment...")"

    export INSTALLER_LANGUAGE="$LANGUAGE_CODE"
    bash "$SCRIPT_DIR/3-deploy.sh"
}

main "$@"
