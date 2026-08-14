#!/bin/bash
#
# Instalador de Lan Mouse para Linux (Wayland y X11).
#
# Este script descarga el código fuente oficial, compila la aplicación con
# Cargo e instala el binario, el icono y el acceso directo del menú.
#
# Distribuciones compatibles:
#   - Debian, Ubuntu y derivadas.
#   - Fedora.
#
# Requisitos:
#   - Conexión a Internet.
#   - Un usuario con permisos de sudo.
#   - Ejecutar el script desde una sesión de usuario normal, no como root,
#     para que el acceso directo se cree en el directorio personal correcto.
#
# Uso:
#   chmod +x install.sh
#   ./install.sh
#
# Archivos creados o modificados:
#   - ./src: clon local del repositorio; si ya existe, se actualiza con git pull.
#   - /usr/local/bin/lan-mouse: ejecutable instalado globalmente.
#   - /usr/local/share/icons/hicolor/scalable/apps/lan-mouse.svg: icono.
#   - ~/.local/share/applications/lan-mouse.desktop: acceso directo del usuario.
#
# El proceso se detiene ante el primer error, salvo en operaciones cuyo fallo
# no impide continuar, como la comprobación de actualizaciones de Fedora o la
# regeneración de la caché de iconos.

# Detener la ejecución si falla cualquier comando no controlado explícitamente.
set -e

# Resolver la ubicación real del script para usar siempre rutas relativas a él,
# independientemente del directorio desde el que se invoque.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================================="
echo " Instala Lan Mouse de forma Nativa (Wayland / X11)"
echo "=========================================================="

# 1. Instalar dependencias base, compiladores y paquetes gráficos requeridos
echo "[1/4] Instalando dependencias del sistema y librerías de desarrollo..."
if [ -f /etc/debian_version ]; then
    sudo apt update
    sudo apt install -y git build-essential cargo pkg-config \
        libgtk-4-dev libadwaita-1-dev libei-dev libportal-dev \
        libgdk-pixbuf-2.0-dev libcairo2-dev libpango1.0-dev libgraphene-1.0-dev \
        libx11-dev libxtst-dev
elif [ -f /etc/fedora-release ]; then
    # dnf devuelve un código distinto de cero cuando hay actualizaciones;
    # esa situación es informativa y no debe detener la instalación.
    sudo dnf check-update || true
    sudo dnf install -y git gcc-c++ cargo pkgconf-pkg-config \
        gtk4-devel libadwaita-devel libei-devel libportal-devel \
        gdk-pixbuf2-devel cairo-devel pango-devel graphene-devel \
        libX11-devel libXtst-devel
else
    echo "❌ Error: Este instalador solo soporta distribuciones basadas en Ubuntu/Debian o Fedora."
    exit 1
fi

# 2. Clonar el repositorio oficial de GitHub
echo "[2/4] Descargando el código fuente desde GitHub..."
if [ -d "src" ]; then
    echo "La carpeta src ya existe. Actualizando repositorio..."
    cd src
    git pull
else
    git clone https://github.com/feschber/lan-mouse.git src
    cd src
fi

# 3. Compilar el binario usando Rust
echo "[3/4] Compilando la aplicación con Cargo (Modo Release)..."
cargo build --release

# 4. Instalar globalmente el binario, el icono y el acceso directo
echo "[4/4] Instalando archivos en el sistema y accesos directos..."

# Copiar ejecutable
sudo cp target/release/lan-mouse /usr/local/bin/

# Instalar icono oficial del sistema
sudo mkdir -p /usr/local/share/icons/hicolor/scalable/apps
sudo cp lan-mouse-gtk/resources/de.feschber.LanMouse.svg /usr/local/share/icons/hicolor/scalable/apps/lan-mouse.svg
# Algunos entornos actualizan la caché automáticamente, por lo que un fallo
# aquí no invalida la instalación del icono.
sudo gtk-update-icon-cache /usr/local/share/icons/hicolor/ || true

# Crear archivo de acceso directo para el menú de aplicaciones
mkdir -p ~/.local/share/applications
cat <<EOF > ~/.local/share/applications/lan-mouse.desktop
[Desktop Entry]
Type=Application
Name=Lan Mouse
Comment=Compartir teclado y ratón en Wayland de forma segura
Exec=/usr/local/bin/lan-mouse
Icon=lan-mouse
Terminal=false
Categories=Utility;Settings;
StartupWMClass=lan-mouse
EOF

echo "=========================================================="
echo " 🎉 ¡Instalación Completada Exitosamente!"
echo " Puedes abrir 'Lan Mouse' directo desde tu lista de apps."
echo "=========================================================="
