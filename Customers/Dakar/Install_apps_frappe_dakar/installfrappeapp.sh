#!/bin/bash
set -euo pipefail

# --- CONFIGURACIÓN ---
DEFAULT_SITE="local.frappe.lan"
DEFAULT_BENCH_DIR="$HOME/frappe-bench"

APPS=(
    "helpdesk|https://dakarsoftware@dev.azure.com/dakarsoftware/frappe-helpdesk/_git/Frappe%20Helpdesk"
    "dakarprojects|https://dakarsoftware@dev.azure.com/dakarsoftware/frappe-helpdesk/_git/Frappe%20Projects"
    "dakartimesheets|https://dakarsoftware@dev.azure.com/dakarsoftware/frappe-helpdesk/_git/Frappe%20Timesheets"
    "calltrack|https://dakarsoftware@dev.azure.com/dakarsoftware/frappe-helpdesk/_git/calltrack"
    "hs_manager|https://dakarsoftware@dev.azure.com/dakarsoftware/frappe-helpdesk/_git/hs_manager"
    "chatbot|https://dakarsoftware@dev.azure.com/dakarsoftware/frappe-helpdesk/_git/chatbot"
    "customers|https://dakarsoftware@dev.azure.com/dakarsoftware/frappe-helpdesk/_git/customers"
    "applauncher|https://dakarsoftware@dev.azure.com/dakarsoftware/frappe-helpdesk/_git/Frappe%20Launcher.git"
)
# ---------------------

echo "Apps configuradas:"
for APP in "${APPS[@]}"; do
    APP_NAME="${APP%%|*}"
    URL="${APP#*|}"
    echo "- $APP_NAME -> $URL"
done
echo ""

echo "Selecciona una opción:"
echo "1) Instalar apps"
echo "2) Desinstalar apps"
read -rp "Opción [1]: " ACTION
ACTION="${ACTION:-1}"

if [ "$ACTION" != "1" ] && [ "$ACTION" != "2" ]; then
    echo "Error: opción inválida. Usa 1 para instalar o 2 para desinstalar."
    exit 1
fi

read -rp "Introduce el dominio/sitio [$DEFAULT_SITE]: " SITE
SITE="${SITE:-$DEFAULT_SITE}"

read -rp "Introduce la carpeta bench [$DEFAULT_BENCH_DIR]: " BENCH_DIR
BENCH_DIR="${BENCH_DIR:-$DEFAULT_BENCH_DIR}"

if [ ! -d "$BENCH_DIR" ]; then
    echo "Error: no existe la carpeta bench: $BENCH_DIR"
    exit 1
fi

cd "$BENCH_DIR"

if [ ! -d "apps/frappe" ]; then
    echo "Error: $BENCH_DIR no parece ser un bench válido. No existe apps/frappe."
    exit 1
fi

if [ "$ACTION" = "1" ]; then
    read -sp "Introduce tu Azure DevOps Personal Access Token PAT: " GIT_TOKEN
    echo ""

    if [ -z "$GIT_TOKEN" ]; then
        echo "Error: el token no puede estar vacío."
        exit 1
    fi

    read -rp "¿Compilar assets al final? Puede consumir mucha memoria [s/N]: " BUILD_ASSETS
    BUILD_ASSETS="${BUILD_ASSETS:-N}"
fi

is_app_installed() {
    local app_name="$1"
    bench --site "$SITE" list-apps | awk '{print $1}' | grep -qx "$app_name"
}

if [ "$ACTION" = "2" ]; then
    echo "--- Iniciando desinstalación de aplicaciones en el sitio $SITE ---"

    for ((i=${#APPS[@]}-1; i>=0; i--)); do
        APP="${APPS[$i]}"
        APP_NAME="${APP%%|*}"

        if is_app_installed "$APP_NAME"; then
            echo ">> Desinstalando $APP_NAME del sitio $SITE..."
            bench --site "$SITE" uninstall-app "$APP_NAME" --yes --no-backup
        else
            echo ">> $APP_NAME no está instalada en $SITE. Saltando..."
        fi
    done

    echo ">> Ejecutando migraciones finales del sistema..."
    bench --site "$SITE" migrate

    echo "--- Proceso de desinstalación completado ---"
    exit 0
fi

echo "--- Iniciando descarga/actualización de aplicaciones ---"

for APP in "${APPS[@]}"; do
    APP_NAME="${APP%%|*}"
    URL="${APP#*|}"

    CLEAN_URL="$(echo "$URL" | sed 's|https://[^@]*@|https://|')"
    AUTH_URL="$(echo "$CLEAN_URL" | sed "s|https://|https://dakarsoftware:${GIT_TOKEN}@|")"

    echo ">> Procesando app: $APP_NAME"

    if [ -d "apps/$APP_NAME" ]; then
        echo ">> La carpeta apps/$APP_NAME ya existe. Actualizando repo..."
        git -C "apps/$APP_NAME" pull
    else
        echo ">> Descargando $APP_NAME desde Azure DevOps..."
        bench get-app "$APP_NAME" "$AUTH_URL"
    fi

    if [ ! -d "apps/$APP_NAME" ]; then
        echo "Error: bench get-app no creó apps/$APP_NAME"
        exit 1
    fi

    if [ ! -f "apps/$APP_NAME/$APP_NAME/hooks.py" ]; then
        echo "Advertencia: no existe apps/$APP_NAME/$APP_NAME/hooks.py"
        echo "Revisa que el paquete Python interno también se llame: $APP_NAME"
    else
        echo ">> Validando app_name en hooks.py..."
        grep -q "app_name.*=.*[\"']$APP_NAME[\"']" "apps/$APP_NAME/$APP_NAME/hooks.py" || {
            echo "Advertencia: hooks.py no parece tener app_name = \"$APP_NAME\""
            echo "Archivo: apps/$APP_NAME/$APP_NAME/hooks.py"
        }
    fi
done

echo "--- Descargas completadas. Iniciando instalación en el sitio $SITE ---"

for APP in "${APPS[@]}"; do
    APP_NAME="${APP%%|*}"

    if is_app_installed "$APP_NAME"; then
        echo ">> $APP_NAME ya está instalada en $SITE. Saltando install-app..."
    else
        echo ">> Instalando $APP_NAME en el sitio $SITE..."
        bench --site "$SITE" install-app "$APP_NAME"
    fi
done

echo ">> Ejecutando migraciones finales del sistema..."
#bench --site "$SITE" migrate

if [[ "$BUILD_ASSETS" =~ ^[sS]$ ]]; then
    echo ">> Compilando assets..."

    NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=2048}" bench build
else
    echo ">> Assets no compilados."
    echo ">> Puedes ejecutar manualmente:"
    echo "   bench build"
fi

echo "--- Proceso de instalación completado con éxito ---"