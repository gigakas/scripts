#!/bin/bash
# Instala Trivy (escaner de vulnerabilidades de imagenes de contenedores y
# manifests) desde el repo oficial de Aqua Security.
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
DISTRO_CODENAME="${VERSION_CODENAME:-}"

echo "=========================================================="
echo " Instalador de Trivy"
echo "=========================================================="
echo "[+] Distribucion detectada: $PRETTY_NAME"

if [ -z "$DISTRO_CODENAME" ]; then
    echo "[-] No se pudo determinar el codename de la distribucion (VERSION_CODENAME vacio)."
    exit 1
fi

echo "[1/4] Instalando dependencias (ca-certificates, curl, gnupg)..."
apt-get update
apt-get install -y ca-certificates curl gnupg

echo "[2/4] Agregando la llave GPG oficial de Trivy..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /etc/apt/keyrings/trivy.gpg
chmod a+r /etc/apt/keyrings/trivy.gpg

echo "[3/4] Agregando el repositorio de Trivy ($DISTRO_CODENAME)..."
echo \
  "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $DISTRO_CODENAME main" \
  > /etc/apt/sources.list.d/trivy.list

echo "[4/4] Instalando Trivy..."
apt-get update
apt-get install -y trivy

echo "=========================================================="
echo " 🎉 Trivy instalado correctamente"
trivy --version
echo "=========================================================="
echo ""
echo "Uso tipico: trivy image <imagen>   (escanea CVEs de una imagen)"
echo "            trivy config <path>    (escanea manifests/Dockerfiles)"
