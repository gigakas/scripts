#!/bin/bash
# Forzar la salida si ocurre un error intermedio
set -e

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
if [ -d "lan-mouse" ]; then
    echo "La carpeta lan-mouse ya existe. Actualizando repositorio..."
    cd lan-mouse
    git pull
else
    git clone https://github.com/feschber/lan-mouse.git
    cd lan-mouse
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
