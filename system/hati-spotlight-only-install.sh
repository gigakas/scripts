#!/usr/bin/env bash
#
# Aplica el parche "spotlight-only" a Hati Cursor Highlighter.
# Comportamiento resultante:
#   - El circulo/anillo normal de Hati queda INVISIBLE (no aparece al mover el mouse).
#   - Pulsar Ctrl dos veces seguidas (ventana de 500 ms) activa/desactiva el
#     spotlight (pantalla oscurecida + circulo alrededor del puntero).
#   - Un Ctrl simple (p.ej. copiar/pegar) NO activa el spotlight.
#
# Uso:  ./hati-spotlight-only-install.sh
#
# El script detecta si la extension esta instalada. Si no lo esta, muestra
# instrucciones para instalarla antes de continuar.
#
# Requiere: extension id: hati@szymonwilczek.github.io
#           y la herramienta "patch".

set -euo pipefail

UUID="hati@szymonwilczek.github.io"
USER_EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"
SYSTEM_EXT_DIR="/usr/share/gnome-shell/extensions/$UUID"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/hati-spotlight-only.patch"
SCHEMA="org.gnome.shell.extensions.hati"
EXT_URL="https://extensions.gnome.org/extension/9209/hati-cursor-highlighter/"

# --- Deteccion de la extension -------------------------------------------
if [[ -d "$USER_EXT_DIR" ]]; then
  EXT_DIR="$USER_EXT_DIR"
elif [[ -d "$SYSTEM_EXT_DIR" ]]; then
  EXT_DIR="$SYSTEM_EXT_DIR"
else
  echo "AVISO: Hati Cursor Highlighter NO esta instalado." >&2
  echo "Ubicaciones revisadas:" >&2
  echo "  - $USER_EXT_DIR" >&2
  echo "  - $SYSTEM_EXT_DIR" >&2
  echo >&2
  echo "Instalalo antes de aplicar el parche. Opciones:" >&2
  echo "  1) Desde el navegador:  $EXT_URL" >&2
  echo "     (con la extension de navegador de GNOME instalada)" >&2
  echo "  2) Por terminal (descargar el .zip de la pagina y luego):" >&2
  echo "       gnome-extensions install <archivo.zip>" >&2
  echo "       gnome-extensions enable $UUID" >&2
  echo "     Despues cierra sesion y vuelve a entrar." >&2
  exit 1
fi

# --- Comprobar que este habilitada ---------------------------------------
if command -v gnome-extensions >/dev/null 2>&1; then
  if ! gnome-extensions show "$UUID" 2>/dev/null | grep -q "State: ENABLED"; then
    echo "AVISO: la extension $UUID esta instalada pero NO habilitada." >&2
    echo "Habilitala con: gnome-extensions enable $UUID" >&2
    echo "o desde la aplicacion 'Extensiones'." >&2
  fi
fi

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "ERROR: no se encontro el archivo de parche en $PATCH_FILE" >&2
  exit 1
fi

if ! command -v patch >/dev/null 2>&1; then
  echo "ERROR: falta la herramienta 'patch'. Instalala con: sudo apt install patch" >&2
  exit 1
fi

echo "Aplicando parche en $EXT_DIR ..."
pushd "$EXT_DIR" >/dev/null

# Comprobar si ya esta aplicado (marcador: llamada a isActive en extension.js)
if grep -q "this._spotlight.isActive()" extension.js 2>/dev/null; then
  echo "El parche ya parece estar aplicado. Nada que hacer."
else
  # Aplicar contra la raiz del repo (paths 'a/...' 'b/...')
  patch -p1 < "$PATCH_FILE"
  echo "Parche aplicado."
fi

popd >/dev/null

echo "Configurando teclas del spotlight (Ctrl)..."
# Registrar el esquema de Hati en glib para que gsettings lo reconozca
GLIB_SCHEMAS_DIR="$HOME/.local/share/glib-2.0/schemas"
if [[ -f "$EXT_DIR/schemas/org.gnome.shell.extensions.hati.gschema.xml" ]]; then
  mkdir -p "$GLIB_SCHEMAS_DIR"
  cp "$EXT_DIR/schemas/org.gnome.shell.extensions.hati.gschema.xml" "$GLIB_SCHEMAS_DIR/"
  if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas "$GLIB_SCHEMAS_DIR" 2>/dev/null || true
  fi
fi

if gsettings list-schemas 2>/dev/null | grep -q "$SCHEMA"; then
  gsettings set "$SCHEMA" spotlight-key 'Control_L'
  gsettings set "$SCHEMA" magnifier-key 'Alt_L'
  echo "Teclas configuradas: spotlight=Ctrl, magnifier=Alt."
else
  echo "AVISO: el esquema $SCHEMA no esta registrado en esta sesion."
  echo "       Configura manualmente: spotlight-key=Control_L y magnifier-key=Alt_L"
  echo "       (o la aplicacion Extensiones -> Hati -> Utilities)."
fi

echo
echo "LISTO. Cierra sesion y vuelve a entrar (o reinicia) para que GNOME Shell cargue el parche."
