#!/bin/bash
# Instala kubectl (CLI de Kubernetes) descargando el binario oficial estable.
# No depende de apt/distro ni de una version fija: siempre toma la ultima
# estable publicada. Sirve para cualquier Linux amd64/arm64.
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

echo "=========================================================="
echo " Instalador de kubectl"
echo "=========================================================="

ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
    amd64|x86_64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *)
        echo "[-] Arquitectura no soportada: $ARCH"
        exit 1
        ;;
esac

echo "[1/4] Detectando la ultima version estable..."
KUBECTL_VERSION="$(curl -L -fsS https://dl.k8s.io/release/stable.txt)"
echo "    Version: $KUBECTL_VERSION"

echo "[2/4] Descargando kubectl ($ARCH)..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL -o "$TMP_DIR/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
curl -fsSL -o "$TMP_DIR/kubectl.sha256" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl.sha256"

echo "[3/4] Verificando checksum..."
(cd "$TMP_DIR" && echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check --status) || {
    echo "[-] El checksum de kubectl no coincide. Abortando."
    exit 1
}

echo "[4/4] Instalando en /usr/local/bin/kubectl..."
install -o root -g root -m 0755 "$TMP_DIR/kubectl" /usr/local/bin/kubectl

echo "=========================================================="
echo " 🎉 kubectl instalado correctamente"
kubectl version --client
echo "=========================================================="
