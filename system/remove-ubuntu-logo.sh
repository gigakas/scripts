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

# Escribe un archivo VALIDO pero invisible.
# IMPORTANTE: NO vaciar a 0 bytes. El login de GDM carga
# /usr/share/pixmaps/ubuntu-logo-text-dark.svg por defecto; si esta vacio,
# la textura es null y el dialogo de login desaparece con el error
# "Argument child may not be null".
hacer_invisible() {
    local ruta="$1"
    case "$ruta" in
        *.png)
            # PNG 1x1 transparente valido
            printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=' | base64 -d > "$ruta"
            ;;
        *.svg)
            # SVG valido sin contenido visible
            printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="187" height="72"></svg>' > "$ruta"
            ;;
    esac
}

quitar_logos() {
    echo ""
    echo "[+] Ocultando logotipos de Ubuntu..."

    # 1. Configurar Boot (Plymouth) - Modo ultra limpio sin logos
    update-alternatives --set default.plymouth /usr/share/plymouth/themes/details/details.plymouth

    # 2. Reemplazar las imagenes de Ubuntu por versiones validas e invisibles
    for ruta in "${RUTAS_LOGOS[@]}"; do
        if [ -f "$ruta" ]; then
            if [ ! -f "${ruta}.bak" ]; then
                mv "$ruta" "${ruta}.bak"
            fi
            hacer_invisible "$ruta"
        fi
    done

    echo "[+] Regenerando el sistema de arranque..."
    update-initramfs -u
    echo "[+] !Hecho! Pantallas completamente limpias."
}

restaurar_marca() {
    echo ""
    echo "[+] Restaurando el logotipo del fabricante (OEM)..."

    # 1. Activar el tema BGRT (Lee el logo de la BIOS/UEFI de la marca de tu laptop)
    if [ -f "/usr/share/plymouth/themes/bgrt/bgrt.plymouth" ]; then
        # Activar el uso del fondo del firmware (Logo de la marca)
        sed -i 's/UseFirmwareBackground=false/UseFirmwareBackground=true/g' /usr/share/plymouth/themes/bgrt/bgrt.plymouth

        # Seleccionar el tema BGRT como el predeterminado del sistema
        update-alternatives --set default.plymouth /usr/share/plymouth/themes/bgrt/bgrt.plymouth
        echo "[+] Tema BGRT (Logo del fabricante) activado."
    else
        echo "[-] Error: El tema BGRT no está instalado en este sistema."
    fi

    # 2. Asegurar que la palabra "ubuntu" de la parte inferior siga oculta en el arranque
    for ruta in "${RUTAS_LOGOS[@]}"; do
        if [ -f "$ruta" ]; then
            if [ ! -f "${ruta}.bak" ]; then
                mv "$ruta" "${ruta}.bak"
            fi
            hacer_invisible "$ruta"
        fi
    done

    echo "[+] Regenerando el sistema de arranque..."
    update-initramfs -u
    echo "[+] !Hecho! Ahora veras el logo de tu laptop sin el logo de Ubuntu abajo."
}

restaurar_todo() {
    echo ""
    echo "[+] Restaurando TODO a los valores originales de Ubuntu..."

    # 1. Restaurar los archivos de imagen originales desde los respaldos .bak
    for ruta in "${RUTAS_LOGOS[@]}"; do
        if [ -f "${ruta}.bak" ] || [ -L "${ruta}.bak" ]; then
            mv "${ruta}.bak" "$ruta"
            echo "[+] Restaurado: $ruta"
        else
            echo "[-] Sin respaldo para: $ruta"
        fi
    done

    # 2. Revertir el cambio en el tema BGRT (activar fondo del firmware)
    if [ -f "/usr/share/plymouth/themes/bgrt/bgrt.plymouth" ]; then
        sed -i 's/UseFirmwareBackground=true/UseFirmwareBackground=false/g' /usr/share/plymouth/themes/bgrt/bgrt.plymouth
        echo "[+] Cambio revertido: /usr/share/plymouth/themes/bgrt/bgrt.plymouth"
    fi

    # 3. Restaurar el tema de Plymouth por defecto de Ubuntu (spinner)
    if [ -f "/usr/share/plymouth/themes/spinner/spinner.plymouth" ]; then
        update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth \
            /usr/share/plymouth/themes/spinner/spinner.plymouth 150 >/dev/null 2>&1
        update-alternatives --set default.plymouth /usr/share/plymouth/themes/spinner/spinner.plymouth >/dev/null 2>&1 \
            || ln -sf /usr/share/plymouth/themes/spinner/spinner.plymouth /etc/alternatives/default.plymouth
        echo "[+] Tema de Plymouth restaurado (spinner)."
    fi

    echo "[+] Regenerando el sistema de arranque..."
    update-initramfs -u
    echo "[+] !Todo restaurado!"
}

# Menu interactivo
echo "================================================="
echo "   GESTOR DE LOGOS DE ARRANQUE Y LOGIN (UBUNTU)  "
echo "================================================="
echo "1) Quitar TODOS los logos (Pantalla 100% limpia)"
echo "2) Mostrar SOLO el logo de la marca de la laptop"
echo "3) RESTAURAR TODO (logos y temas originales de Ubuntu)"
echo "4) Salir"
echo "================================================="
read -p "Selecciona una opcion [1-4]: " opcion

case $opcion in
    1) quitar_logos ;;
    2) restaurar_marca ;;
    3) restaurar_todo ;;
    4) echo "[+] Saliendo sin aplicar cambios."; exit 0 ;;
    *) echo "[-] Opcion no valida."; exit 1 ;;
esac

# Opcion de reinicio al finalizar
echo ""
read -p "[?] ¿Deseas reiniciar el ordenador ahora para aplicar los cambios? (s/n): " respuesta
if [[ "$respuesta" =~ ^[Ss]$ ]]; then
    echo "[+] Reiniciando..."
    reboot
else
    echo "[+] Cambios guardados. Recuerda reiniciar mas tarde."
fi
