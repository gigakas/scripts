#!/bin/bash
# Instala el cliente CLI de ArgoCD (GitOps para Kubernetes) descargando el
# binario oficial y verificando su checksum.
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

echo "=========================================================="
echo " Instalador de ArgoCD CLI"
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

echo "[1/4] Detectando la ultima version de ArgoCD..."
ARGOCD_VERSION="$(curl -fsSL https://api.github.com/repos/argoproj/argo-cd/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)"
echo "    Version: $ARGOCD_VERSION"

echo "[2/4] Descargando argocd-linux-${ARCH}..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL -o "$TMP_DIR/argocd" "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${ARCH}"
curl -fsSL -o "$TMP_DIR/cli_checksums.txt" "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/cli_checksums.txt"

echo "[3/4] Verificando checksum..."
EXPECTED_HASH="$(grep "argocd-linux-${ARCH}$" "$TMP_DIR/cli_checksums.txt" | awk '{print $1}')"
(cd "$TMP_DIR" && echo "${EXPECTED_HASH}  argocd" | sha256sum --check --status) || {
    echo "[-] El checksum de argocd no coincide. Abortando."
    exit 1
}

echo "[4/4] Instalando en /usr/local/bin/argocd..."
install -o root -g root -m 0755 "$TMP_DIR/argocd" /usr/local/bin/argocd

echo "=========================================================="
echo " 🎉 ArgoCD CLI instalado correctamente"
argocd version --client
echo "=========================================================="
echo ""
echo "Nota: esto instala solo el CLIENTE. El servidor de ArgoCD se instala"
echo "dentro del cluster de Kubernetes via Helm (Fase 5 del ejercicio)."
