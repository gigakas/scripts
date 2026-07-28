#!/bin/bash

# Verificar si el script se ejecuta como root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (usa sudo)."
  exit 1
fi

# Rutas de los archivos modificados
RUTAS_LOGOS=(
    "/usr/share/plymouth/themes/spinner/watermark.png"
    "/usr/share/plymouth/themes/spinner/ubuntu-logo.svg"
    "/usr/share/pixmaps/ubuntu-logo-text-dark.svg"
)

quitar_logos() {
    echo ""
    echo "[+] Ocultando logotipos de Ubuntu..."

    # 1. Configurar Pantalla de Login (GDM)
    chown -R gdm:gdm /var/lib/gdm3/.cache 2>/dev/null
    sudo -u gdm dbus-launch gsettings set org.gnome.login-screen logo '/dev/null'

    GDM_DEFAULTS="/etc/gdm3/greeter.dconf-defaults"
    if [ -f "$GDM_DEFAULTS" ]; then
        sed -i '/\[org\/gnome\/login-screen\]/,/^$/{/logo=/d}' "$GDM_DEFAULTS"
        sed -i '/\[org\/gnome\/login-screen\]/a logo='\''\''' "$GDM_DEFAULTS"
    fi
    dconf update

    # 2. Configurar Boot (Plymouth) - Modo ultra limpio sin logos
    update-alternatives --set default.plymouth /usr/share/plymouth/themes/details/details.plymouth

    # Vaciar archivos de imagen de Ubuntu
    for ruta in "${RUTAS_LOGOS[@]}"; do
        if [ -f "$ruta" ] && [ ! -f "${ruta}.bak" ]; then
            mv "$ruta" "${ruta}.bak"
            touch "$ruta"
        fi
    done

    echo "[+] Regenerando el sistema de arranque..."
    update-initramfs -u
    echo "[+] ¡Hecho! Pantallas completamente limpias."
}

restaurar_marca() {
    echo ""
    echo "[+] Restaurando el logotipo del fabricante (OEM)..."

    # 1. Mantener el login limpio (el logo de la marca nunca sale aquí de forma nativa)
    chown -R gdm:gdm /var/lib/gdm3/.cache 2>/dev/null
    sudo -u gdm dbus-launch gsettings set org.gnome.login-screen logo '/dev/null'

    # 2. Activar el tema BGRT (Lee el logo de la BIOS/UEFI de la marca de tu laptop)
    if [ -f "/usr/share/plymouth/themes/bgrt/bgrt.plymouth" ]; then
        # Activar el uso del fondo del firmware (Logo de la marca)
        sed -i 's/UseFirmwareBackground=false/UseFirmwareBackground=true/g' /usr/share/plymouth/themes/bgrt/bgrt.plymouth
        
        # Seleccionar el tema BGRT como el predeterminado del sistema
        update-alternatives --set default.plymouth /usr/share/plymouth/themes/bgrt/bgrt.plymouth
        echo "[+] Tema BGRT (Logo del fabricante) activado."
    else
        echo "[-] Error: El tema BGRT no está instalado en este sistema."
    fi

    # 3. Asegurar que la palabra "ubuntu" de la parte inferior siga oculta en el arranque
    for ruta in "${RUTAS_LOGOS[@]}"; do
        if [ -f "$ruta" ] && [ ! -f "${ruta}.bak" ]; then
            mv "$ruta" "${ruta}.bak"
            touch "$ruta"
        fi
    done

    echo "[+] Regenerando el sistema de arranque..."
    update-initramfs -u
    echo "[+] ¡Hecho! Ahora verás el logo de tu laptop sin el logo de Ubuntu abajo."
}

# Menú interactivo
echo "================================================="
echo "   GESTOR DE LOGOS DE ARRANQUE Y LOGIN (UBUNTU)  "
echo "================================================="
echo "1) Quitar TODOS los logos (Pantalla 100% limpia)"
echo "2) Mostrar SOLO el logo de la marca de la laptop"
echo "3) Salir"
echo "================================================="
read -p "Selecciona una opción [1-3]: " opcion

case $opcion in
    1) quitar_logos ;;
    2) restaurar_marca ;;
    3) echo "[+] Saliendo sin aplicar cambios."; exit 0 ;;
    *) echo "[-] Opción no válida."; exit 1 ;;
esac

# Opción de reinicio al finalizar
echo ""
read -p "[?] ¿Deseas reiniciar el ordenador ahora para aplicar los cambios? (s/n): " respuesta
if [[ "$respuesta" =~ ^[Ss]$ ]]; then
    echo "[+] Reiniciando..."
    reboot
else
    echo "[+] Cambios guardados. Recuerda reiniciar más tarde."
fi
