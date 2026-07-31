#!/bin/bash
# Instala kind (Kubernetes IN Docker): crea clusters de Kubernetes usando
# contenedores Docker como nodos. Requiere Docker ya instalado
# (ver 00-install-docker.sh).
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "[-] Docker no esta instalado. Corre primero 00-install-docker.sh"
    exit 1
fi

echo "=========================================================="
echo " Instalador de kind"
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

echo "[1/4] Detectando la ultima version de kind..."
KIND_VERSION="$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)"
echo "    Version: $KIND_VERSION"

echo "[2/4] Descargando kind ($ARCH)..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL -o "$TMP_DIR/kind" "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${ARCH}"
curl -fsSL -o "$TMP_DIR/kind.sha256sum" "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${ARCH}.sha256sum"

echo "[3/4] Verificando checksum..."
(cd "$TMP_DIR" && sha256sum -c <(awk '{print $1, "kind"}' kind.sha256sum) --status) || {
    echo "[-] El checksum de kind no coincide. Abortando."
    exit 1
}

echo "[4/4] Instalando en /usr/local/bin/kind..."
install -o root -g root -m 0755 "$TMP_DIR/kind" /usr/local/bin/kind

echo "=========================================================="
echo " 🎉 kind instalado correctamente"
kind version
echo "=========================================================="
echo ""
echo "Nota: 'kind' crea los nodos del cluster como contenedores Docker."
echo "El usuario que lo use debe poder correr 'docker ps' sin sudo"
echo "(ya configurado por 00-install-docker.sh)."
