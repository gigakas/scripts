#!/bin/bash
# Instala k6 (generador de carga/load testing) desde el repo oficial.
# Nota: el repo apt de k6 solo publica paquetes amd64/i386.
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

ARCH="$(dpkg --print-architecture 2>/dev/null)"
if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "i386" ]; then
    echo "[-] El repo apt oficial de k6 solo soporta amd64/i386 (detectado: $ARCH)."
    echo "    Para otras arquitecturas, instala el binario manualmente desde:"
    echo "    https://github.com/grafana/k6/releases"
    exit 1
fi

echo "=========================================================="
echo " Instalador de k6"
echo "=========================================================="

echo "[1/4] Instalando dependencias (ca-certificates, curl, gnupg)..."
apt-get update
apt-get install -y ca-certificates curl gnupg

echo "[2/4] Agregando la llave GPG oficial de k6..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://dl.k6.io/key.gpg | gpg --dearmor -o /etc/apt/keyrings/k6.gpg
chmod a+r /etc/apt/keyrings/k6.gpg

echo "[3/4] Agregando el repositorio de k6..."
echo \
  "deb [signed-by=/etc/apt/keyrings/k6.gpg] https://dl.k6.io/deb stable main" \
  > /etc/apt/sources.list.d/k6.list

echo "[4/4] Instalando k6..."
apt-get update
apt-get install -y k6

echo "=========================================================="
echo " 🎉 k6 instalado correctamente"
k6 version
echo "=========================================================="
echo ""
echo "Uso tipico: k6 run script.js   (corre un test de carga)"
