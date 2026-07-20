#!/bin/bash
#
# promiscusModevmware.sh
#
# Habilita de forma PERMANENTE el modo promiscuo en las redes de
# VMware Workstation (host Linux) asignando permisos 0666 a los
# dispositivos /dev/vmnet*.
#
# ¿Por qué un servicio systemd y no una regla udev?
# Los nodos /dev/vmnet* los crea el módulo de kernel 'vmnet' sin pasar
# por sysfs, por lo que NUNCA generan eventos udev y cualquier regla
# udev sobre ellos se ignora. Por eso este script crea el servicio
# vmware-promiscuous.service, que aplica los permisos cada vez que
# vmware.service arranca o se reinicia: los permisos sobreviven a
# reinicios del equipo y del servicio de VMware.
#
# USO:
#   sudo ./promiscusModevmware.sh      Aplica la configuración
#   ./promiscusModevmware.sh -h        Muestra las instrucciones de uso
#
# VERIFICACIÓN (después de ejecutarlo):
#   systemctl status vmware-promiscuous.service
#   ls -l /dev/vmnet*                  Debe mostrar crw-rw-rw-
#
# IMPORTANTE: las máquinas virtuales que ya estuvieran encendidas deben
# apagarse por completo y volverse a encender para heredar los permisos.

SERVICE_NAME="vmware-promiscuous.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
OLD_UDEV_RULE="/etc/udev/rules.d/99-vmnet.rules"

mostrar_ayuda() {
  echo "Uso: sudo $0"
  echo ""
  echo "Configura de forma permanente el modo promiscuo para VMware Workstation:"
  echo "  1. Crea e instala el servicio systemd '$SERVICE_NAME'."
  echo "  2. Lo habilita para que se ejecute en cada arranque del equipo y"
  echo "     cada vez que se reinicie vmware.service."
  echo "  3. Aplica los permisos 0666 a /dev/vmnet* de inmediato."
  echo ""
  echo "Verificación posterior:"
  echo "  systemctl status $SERVICE_NAME"
  echo "  ls -l /dev/vmnet*   (debe mostrar crw-rw-rw-)"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  mostrar_ayuda
  exit 0
fi

# Verificar si el script se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Por favor, ejecuta este script utilizando sudo o como usuario root."
  echo "   Ejecuta '$0 -h' para ver las instrucciones de uso."
  exit 1
fi

# Este método requiere systemd
if ! command -v systemctl &> /dev/null; then
  echo "❌ Este script requiere systemd (systemctl no encontrado)."
  exit 1
fi

echo "🚀 Iniciando configuración permanente del modo promiscuo para VMware Workstation..."

# 1. Crear el servicio systemd
echo "📝 Creando servicio systemd en: $SERVICE_FILE"
cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Aplicar permisos de modo promiscuo a /dev/vmnet* (VMware)
After=vmware.service
PartOf=vmware.service

[Service]
Type=oneshot
RemainAfterExit=yes
# Espera hasta 10s a que el módulo vmnet cree los nodos y aplica los permisos
ExecStart=/bin/sh -c 'for i in $(seq 1 10); do if ls /dev/vmnet* >/dev/null 2>&1; then chmod a+rw /dev/vmnet*; exit 0; fi; sleep 1; done'

[Install]
WantedBy=vmware.service
EOF
echo "✅ Servicio creado."

# 2. Eliminar la regla udev obsoleta (creada por versiones anteriores del script)
if [ -f "$OLD_UDEV_RULE" ]; then
  rm -f "$OLD_UDEV_RULE"
  udevadm control --reload-rules 2>/dev/null
  echo "ℹ️  Regla udev obsoleta eliminada ($OLD_UDEV_RULE): los dispositivos"
  echo "   /dev/vmnet* no generan eventos udev, la regla nunca se aplicaba."
fi

# 3. Habilitar e iniciar el servicio
echo "🔄 Habilitando e iniciando $SERVICE_NAME..."
systemctl daemon-reload
if systemctl enable --now "$SERVICE_NAME"; then
  echo "✅ Servicio habilitado: se ejecutará en cada arranque y en cada"
  echo "   reinicio de vmware.service."
else
  echo "❌ No se pudo habilitar el servicio. Revisa: systemctl status $SERVICE_NAME"
  exit 1
fi

# 4. Aplicar permisos inmediatos (respaldo por si el servicio aún no vio los nodos)
if ls /dev/vmnet* 1> /dev/null 2>&1; then
  chmod a+rw /dev/vmnet*
  echo "✅ Permisos de lectura/escritura aplicados a las interfaces actuales:"
  ls -l /dev/vmnet*
else
  echo "⚠️  No se detectaron interfaces /dev/vmnet* en este momento."
  echo "   Los permisos se aplicarán automáticamente la próxima vez que arranque VMware."
fi

echo -e "\n🎉 ¡Configuración completada con éxito!"
echo "👉 REQUISITO FINAL: si hay máquinas virtuales encendidas, apágalas por"
echo "   completo y vuélvelas a encender para que hereden los nuevos permisos."
echo ""
echo "🔍 Verificación:"
echo "   systemctl status $SERVICE_NAME"
echo "   ls -l /dev/vmnet*   (debe mostrar crw-rw-rw-)"
