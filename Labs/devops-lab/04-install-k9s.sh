#!/bin/bash
# Instala k9s (TUI para navegar/operar un cluster de Kubernetes sin pelear
# con "kubectl get" todo el tiempo). Usa el paquete .deb oficial.
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

echo "=========================================================="
echo " Instalador de k9s"
echo "=========================================================="

ARCH="$(dpkg --print-architecture 2>/dev/null)"
case "$ARCH" in
    amd64|arm64|armhf) ;;
    *)
        echo "[-] Arquitectura no soportada: $ARCH"
        exit 1
        ;;
esac
[ "$ARCH" = "armhf" ] && ARCH="arm"

echo "[1/4] Detectando la ultima version de k9s..."
K9S_VERSION="$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)"
echo "    Version: $K9S_VERSION"

echo "[2/4] Descargando k9s_linux_${ARCH}.deb..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL -o "$TMP_DIR/k9s.deb" "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_linux_${ARCH}.deb"
curl -fsSL -o "$TMP_DIR/checksums.sha256" "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/checksums.sha256"

echo "[3/4] Verificando checksum..."
EXPECTED_HASH="$(grep "k9s_linux_${ARCH}.deb" "$TMP_DIR/checksums.sha256" | awk '{print $1}')"
(cd "$TMP_DIR" && echo "${EXPECTED_HASH}  k9s.deb" | sha256sum --check --status) || {
    echo "[-] El checksum de k9s no coincide. Abortando."
    exit 1
}

echo "[4/4] Instalando el paquete..."
apt-get install -y "$TMP_DIR/k9s.deb"

echo "=========================================================="
echo " 🎉 k9s instalado correctamente"
k9s version
echo "=========================================================="
echo ""
echo "Uso: corre 'k9s' con un kubeconfig valido (ej. despues de crear un"
echo "cluster con kind) para navegar el cluster de forma interactiva."
