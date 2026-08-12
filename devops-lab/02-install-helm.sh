#!/bin/bash
# Instala Helm (gestor de paquetes de Kubernetes) usando el instalador oficial.
# El script oficial ya verifica checksums y detecta distro/arquitectura solo.
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

echo "=========================================================="
echo " Instalador de Helm"
echo "=========================================================="

echo "[1/2] Descargando y corriendo el instalador oficial de Helm..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL -o "$TMP_DIR/get_helm.sh" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 "$TMP_DIR/get_helm.sh"
bash "$TMP_DIR/get_helm.sh"

echo "[2/2] Verificando instalacion..."
echo "=========================================================="
echo " 🎉 Helm instalado correctamente"
helm version
echo "=========================================================="
