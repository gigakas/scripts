#!/bin/bash

# Verificar si el script se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Por favor, ejecuta este script utilizando sudo o como usuario root."
  exit 1
fi

echo "🚀 Iniciando configuración del modo promiscuo para VMware Workstation..."

# 1. Crear la regla udev permanente
RULE_FILE="/etc/udev/rules.d/99-vmnet.rules"
echo 'KERNEL=="vmnet*", MODE="0666"' > "$RULE_FILE"
echo "✅ Regla udev permanente creada en: $RULE_FILE"

# 2. Recargar las reglas del sistema udev
echo "🔄 Recargando reglas de dispositivos (udev)..."
udevadm control --reload-rules
udevadm trigger

# 3. Aplicar permisos inmediatos a los módulos activos de vmnet
if ls /dev/vmnet* 1> /dev/null 2>&1; then
  chmod a+rw /dev/vmnet*
  echo "✅ Permisos de lectura/escritura aplicados a las interfaces /dev/vmnet* actuales."
else
  echo "⚠️ No se detectaron interfaces /dev/vmnet* activas en este momento (asegúrate de que VMware esté abierto)."
fi

# 4. Intentar reiniciar los servicios de red de VMware
echo "🔄 Reiniciando servicios de red de VMware..."
if [ -f /etc/init.d/vmware ]; then
  /etc/init.d/vmware restart
  echo "✅ Servicios de VMware reiniciados."
elif command -v systemctl &> /dev/null; then
  # Intentar vía systemctl si no existe el init.d clásico
  systemctl restart vmware-USBArbitrator.service 2>/dev/null
  echo "✅ Servicios base de VMware actualizados."
else
  echo "ℹ️ No se pudo reiniciar el servicio automáticamente. Se recomienda cerrar y reabrir VMware Workstation."
fi

echo -e "\n🎉 ¡Configuración completada con éxito!"
echo "👉 REQUISITO FINAL: Apaga por completo la máquina virtual de Proxmox en VMware y vuélvela a encender para que herede los nuevos permisos."
