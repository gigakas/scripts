#!/bin/bash
# Integrador: corre en orden todos los scripts numerados "NN-install-*.sh"
# de este mismo directorio (00-docker, 01-kubectl, 02-helm, ...).
#
# Es puramente un orquestador: no instala nada por si mismo. Agregar un
# nuevo componente es tan simple como dejar un script "09-install-x.sh"
# junto a los demas - este integrador lo va a detectar y correr solo,
# sin necesidad de editarlo.
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo " Instalador del stack DevOps completo"
echo "=========================================================="

mapfile -t COMPONENT_SCRIPTS < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -regextype posix-extended -regex '.*/[0-9]{2}-install-.*\.sh' | sort)

if [ "${#COMPONENT_SCRIPTS[@]}" -eq 0 ]; then
    echo "[-] No se encontraron scripts NN-install-*.sh en $SCRIPT_DIR"
    exit 1
fi

echo "[+] Componentes a instalar (en orden):"
for script in "${COMPONENT_SCRIPTS[@]}"; do
    echo "    - $(basename "$script")"
done
echo ""

TOTAL="${#COMPONENT_SCRIPTS[@]}"
STEP=0
for script in "${COMPONENT_SCRIPTS[@]}"; do
    STEP=$((STEP + 1))
    echo "############################################################"
    echo "# [$STEP/$TOTAL] $(basename "$script")"
    echo "############################################################"
    bash "$script"
    echo ""
done

echo "=========================================================="
echo " 🎉 Stack DevOps instalado completo ($TOTAL componentes)"
echo "=========================================================="
