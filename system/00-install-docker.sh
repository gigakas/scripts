#!/bin/bash
# Instala Docker Engine (docker-ce) desde el repositorio oficial de Docker.
# Soportado: Ubuntu 24.04 / 26.04, Debian 12 / 13.
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

if [ ! -f /etc/os-release ]; then
    echo "[-] No se pudo detectar la distribucion (falta /etc/os-release)."
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID="$ID"
DISTRO_VERSION="$VERSION_ID"
DISTRO_CODENAME="${VERSION_CODENAME:-}"

echo "=========================================================="
echo " Instalador de Docker Engine"
echo "=========================================================="
echo "[+] Distribucion detectada: $PRETTY_NAME"

case "$DISTRO_ID" in
    ubuntu)
        case "$DISTRO_VERSION" in
            24.04|26.04) ;;
            *)
                echo "[-] Version de Ubuntu no verificada por este script (soportadas: 24.04, 26.04)."
                read -r -p "    ¿Continuar de todas formas? [y/N] " resp
                [[ "${resp,,}" == "y" || "${resp,,}" == "yes" ]] || exit 1
                ;;
        esac
        ;;
    debian)
        case "$DISTRO_VERSION" in
            12|13) ;;
            *)
                echo "[-] Version de Debian no verificada por este script (soportadas: 12, 13)."
                read -r -p "    ¿Continuar de todas formas? [y/N] " resp
                [[ "${resp,,}" == "y" || "${resp,,}" == "yes" ]] || exit 1
                ;;
        esac
        ;;
    *)
        echo "[-] Error: Este instalador solo soporta Ubuntu y Debian (detectado: $DISTRO_ID)."
        exit 1
        ;;
esac

if [ -z "$DISTRO_CODENAME" ]; then
    echo "[-] No se pudo determinar el codename de la distribucion (VERSION_CODENAME vacio)."
    exit 1
fi

echo "[1/6] Quitando paquetes de Docker antiguos/en conflicto (si existen)..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y "$pkg" >/dev/null 2>&1 || true
done

echo "[2/6] Instalando dependencias (ca-certificates, curl)..."
apt-get update
apt-get install -y ca-certificates curl

echo "[3/6] Agregando la llave GPG oficial de Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/$DISTRO_ID/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "[4/6] Agregando el repositorio de Docker ($DISTRO_ID/$DISTRO_CODENAME)..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$DISTRO_ID $DISTRO_CODENAME stable" \
  > /etc/apt/sources.list.d/docker.list

echo "[5/6] Instalando Docker Engine, CLI, containerd y plugins (buildx, compose)..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[6/6] Habilitando e iniciando el servicio Docker..."
systemctl enable --now docker

REAL_USER="${SUDO_USER:-}"
if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ] && ! id -nG "$REAL_USER" | grep -qw docker; then
    if [ -t 0 ]; then
        read -r -p "¿Agregar el usuario '$REAL_USER' al grupo 'docker' (usar docker sin sudo)? [Y/n] " add_group
        add_group="${add_group:-y}"
    else
        # Sin terminal interactiva (ej. corriendo desde el integrador o por
        # SSH no interactivo): agregar al grupo es el default seguro, no hace
        # falta preguntar.
        add_group="y"
    fi
    if [[ "${add_group,,}" == "y" || "${add_group,,}" == "yes" ]]; then
        usermod -aG docker "$REAL_USER"
        echo "[+] Usuario agregado. Cierra sesion y vuelve a entrar (o corre 'newgrp docker') para que tome efecto."
    fi
fi

echo "=========================================================="
echo " 🎉 Docker instalado correctamente"
docker --version
docker compose version
echo "=========================================================="
