#!/bin/bash
# Instala el cliente CLI de Velero (backup/restore de namespaces y volumenes
# de Kubernetes) descargando el binario oficial y verificando su checksum.
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

echo "=========================================================="
echo " Instalador de Velero CLI"
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

echo "[1/5] Detectando la ultima version de Velero..."
VELERO_VERSION="$(curl -fsSL -L https://api.github.com/repos/vmware-tanzu/velero/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)"
echo "    Version: $VELERO_VERSION"

TARBALL="velero-${VELERO_VERSION}-linux-${ARCH}.tar.gz"

echo "[2/5] Descargando ${TARBALL}..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL -o "$TMP_DIR/$TARBALL" "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/${TARBALL}"
curl -fsSL -o "$TMP_DIR/CHECKSUM" "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/CHECKSUM"

echo "[3/5] Verificando checksum..."
EXPECTED_HASH="$(grep "$TARBALL" "$TMP_DIR/CHECKSUM" | awk '{print $1}')"
(cd "$TMP_DIR" && echo "${EXPECTED_HASH}  ${TARBALL}" | sha256sum --check --status) || {
    echo "[-] El checksum de velero no coincide. Abortando."
    exit 1
}

echo "[4/5] Extrayendo..."
tar -xzf "$TMP_DIR/$TARBALL" -C "$TMP_DIR"
BINARY_PATH="$(find "$TMP_DIR" -maxdepth 2 -type f -name velero | head -1)"

echo "[5/5] Instalando en /usr/local/bin/velero..."
install -o root -g root -m 0755 "$BINARY_PATH" /usr/local/bin/velero

echo "=========================================================="
echo " 🎉 Velero CLI instalado correctamente"
velero version --client-only
echo "=========================================================="
echo ""
echo "Nota: esto instala solo el CLIENTE. El servidor de Velero se instala"
echo "dentro del cluster de Kubernetes con 'velero install' (Fase 9)."
