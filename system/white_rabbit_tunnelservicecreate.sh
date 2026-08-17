#!/bin/bash

# Reverse SSH tunnel installer
#
# Purpose:
#   Create a persistent reverse SSH tunnel from this machine to a relay server.
#   The tunnel exposes this machine's SSH port (22) on a selected relay port and
#   can optionally expose the Proxmox web interface (8006) on another relay port.
#
# Prerequisites:
#   - Run this script on the machine that will initiate the reverse tunnel.
#   - Run it with sudo; the generated key and service will belong to the user
#     who invoked sudo.
#   - The relay must run SSH on port 1981 and allow TCP forwarding.
#   - The relay user must initially accept password authentication so
#     ssh-copy-id can install the public key, unless that key is already present.
#   - openssh-client, ssh-copy-id, runuser, and systemd must be available locally.
#
# Usage:
#   chmod +x white_rabbit_tunnelservicecreate.sh
#   sudo ./white_rabbit_tunnelservicecreate.sh
#
# Interactive values:
#   1. Target domain: DNS name or IP address of the relay server.
#   2. Remote SSH user: account on the relay that owns authorized_keys.
#   3. SSH reverse port: relay port that forwards to local port 22.
#   4. Web reverse port: optional relay port that forwards to local port 8006.
#
# Installation flow:
#   1. Validate and normalize the interactive values.
#   2. Create or reuse keys/id_rsa_tunnel next to this script.
#   3. Copy only the public key to the relay user's authorized_keys file.
#   4. Verify non-interactive public-key authentication to the relay.
#   5. Create, enable, and start /etc/systemd/system/ssh-tunnel.service.
#
# Validation after installation:
#   Local machine:
#     systemctl status ssh-tunnel.service
#     journalctl -u ssh-tunnel.service -f
#   Relay server:
#     ss -lnt
#     ssh -p <SSH_REVERSE_PORT> <local-user>@localhost
#   If a web port was configured, open https://localhost:<WEB_REVERSE_PORT>
#   from the relay or through an additional secured forwarding/proxy layer.
#
# Security notes:
#   - Never copy keys/id_rsa_tunnel (the private key) to the relay.
#   - The script copies only keys/id_rsa_tunnel.pub.
#   - Reverse ports bind according to the relay's sshd GatewayPorts setting.
#     Keep the default loopback binding unless external access is required and
#     protected by appropriate firewall and authentication rules.
#
# Recreating the SSH keys:
#   The installer reuses an existing key pair. To generate a new pair, run these
#   commands from the directory containing this script, then run the installer:
#     sudo rm ./keys/id_rsa_tunnel ./keys/id_rsa_tunnel.pub
#     sudo ./white_rabbit_tunnelservicecreate.sh
#   ssh-copy-id will install the new public key, but it will not remove the old
#   one from the relay. Remove the old key manually from the relay user's
#   ~/.ssh/authorized_keys after confirming that the new key works.

# Instalador de tunel SSH inverso
#
# Proposito:
#   Crear un tunel SSH inverso persistente desde esta maquina hacia un servidor
#   relay. El tunel publica el puerto SSH local (22) en un puerto elegido del
#   relay y, opcionalmente, la interfaz web de Proxmox (8006) en otro puerto.
#
# Requisitos:
#   - Ejecutar este script en la maquina que iniciara el tunel inverso.
#   - Ejecutarlo con sudo; la clave y el servicio perteneceran al usuario que
#     invoco sudo.
#   - El relay debe ofrecer SSH en el puerto 1981 y permitir TCP forwarding.
#   - El usuario del relay debe aceptar inicialmente autenticacion por password
#     para que ssh-copy-id instale la clave, salvo que ya este instalada.
#   - openssh-client, ssh-copy-id, runuser y systemd deben estar disponibles.
#
# Uso:
#   chmod +x white_rabbit_tunnelservicecreate.sh
#   sudo ./white_rabbit_tunnelservicecreate.sh
#
# Valores interactivos:
#   1. Dominio destino: nombre DNS o direccion IP del relay.
#   2. Usuario SSH remoto: cuenta del relay propietaria de authorized_keys.
#   3. Puerto SSH inverso: puerto del relay que redirige al puerto local 22.
#   4. Puerto web inverso: puerto opcional que redirige al puerto local 8006.
#
# Flujo de instalacion:
#   1. Validar y normalizar los valores interactivos.
#   2. Crear o reutilizar keys/id_rsa_tunnel junto a este script.
#   3. Copiar solo la clave publica a authorized_keys del usuario del relay.
#   4. Verificar la autenticacion no interactiva mediante clave publica.
#   5. Crear, habilitar e iniciar /etc/systemd/system/ssh-tunnel.service.
#
# Validacion posterior:
#   Maquina local:
#     systemctl status ssh-tunnel.service
#     journalctl -u ssh-tunnel.service -f
#   Servidor relay:
#     ss -lnt
#     ssh -p <PUERTO_SSH_INVERSO> <usuario-local>@localhost
#   Si se configuro un puerto web, abrir https://localhost:<PUERTO_WEB_INVERSO>
#   desde el relay o mediante una capa adicional segura de proxy o forwarding.
#
# Notas de seguridad:
#   - Nunca copiar keys/id_rsa_tunnel (la clave privada) al relay.
#   - El script copia unicamente keys/id_rsa_tunnel.pub.
#   - Los puertos inversos se enlazan segun GatewayPorts de sshd en el relay.
#     Conservar el enlace local predeterminado salvo que el acceso externo sea
#     necesario y este protegido por firewall y autenticacion adecuados.
#
# Recreacion de las claves SSH:
#   El instalador reutiliza el par de claves existente. Para generar uno nuevo,
#   ejecutar estos comandos desde el directorio que contiene este script y luego
#   volver a ejecutar el instalador:
#     sudo rm ./keys/id_rsa_tunnel ./keys/id_rsa_tunnel.pub
#     sudo ./white_rabbit_tunnelservicecreate.sh
#   ssh-copy-id instalara la nueva clave publica, pero no eliminara la anterior
#   del relay. Eliminar manualmente la clave anterior de ~/.ssh/authorized_keys
#   del usuario del relay despues de confirmar que la nueva clave funciona.

# Language selection / Seleccion de idioma
while true; do
  echo "Select language / Seleccione el idioma:"
  echo "  1) English"
  echo "  2) Espanol"
  read -r -p "> " LANGUAGE_OPTION

  case "$LANGUAGE_OPTION" in
    1)
      LANGUAGE="en"
      break
      ;;
    2)
      LANGUAGE="es"
      break
      ;;
    *)
      echo "Invalid option. Enter 1 or 2. / Opcion invalida. Ingrese 1 o 2."
      ;;
  esac
done

text() {
  if [ "$LANGUAGE" = "es" ]; then
    printf '%s' "$2"
  else
    printf '%s' "$1"
  fi
}

say() {
  text "$1" "$2"
  printf '\n'
}

# Ensure root privileges / Comprobar privilegios de root
if [ "$EUID" -ne 0 ]; then
  say \
    "❌ Error: This script must be run with administrative privileges (root)." \
    "❌ Error: Este script debe ejecutarse con privilegios administrativos (root)."
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_USER="${SUDO_USER:-$(stat -c '%U' "$SCRIPT_DIR")}"
LOCAL_GROUP="$(id -gn "$LOCAL_USER")"
KEY_DIR="$SCRIPT_DIR/keys"
KEY_PATH="$KEY_DIR/id_rsa_tunnel"

echo "=================================================="
say \
  "    FULLY DYNAMIC REVERSE TUNNEL CONFIGURATOR     " \
  " CONFIGURADOR DINAMICO DE TUNEL INVERSO "
echo "=================================================="
echo ""

# 1. Interactive input / Entrada interactiva
read -r -p "$(text \
  "🌐 Enter the exact target domain (e.g., www.albanss.com): " \
  "🌐 Ingrese el dominio exacto del relay (ej.: www.albanss.com): ")" TARGET_DOMAIN
read -r -p "$(text \
  "👤 Enter the remote SSH user on the VPS (e.g., proxmox): " \
  "👤 Ingrese el usuario SSH remoto del VPS (ej.: proxmox): ")" REMOTE_USER
read -r -p "$(text \
  "🔌 Enter your custom SSH reverse port (e.g., 2230): " \
  "🔌 Ingrese el puerto SSH inverso personalizado (ej.: 2230): ")" CUSTOM_SSH_PORT
read -r -p "$(text \
  "🖥️  Enter your custom Web reverse port (OPTIONAL - Press ENTER to skip): " \
  "🖥️  Ingrese el puerto web inverso (OPCIONAL; ENTER para omitir): ")" CUSTOM_WEB_PORT

# Remove Windows carriage-return characters (\r)
TARGET_DOMAIN=$(echo "$TARGET_DOMAIN" | tr -d '\r')
REMOTE_USER=$(echo "$REMOTE_USER" | tr -d '\r')
CUSTOM_SSH_PORT=$(echo "$CUSTOM_SSH_PORT" | tr -d '\r')
CUSTOM_WEB_PORT=$(echo "$CUSTOM_WEB_PORT" | tr -d '\r')

# Use '#' as the sed delimiter so URL slashes do not need escaping
TARGET_DOMAIN=$(echo "$TARGET_DOMAIN" | sed -E 's#^(https?://|://|//)##g')

# Mandatory validation / Validacion obligatoria
if [ -z "$TARGET_DOMAIN" ] || [ -z "$REMOTE_USER" ] || ! [[ "$CUSTOM_SSH_PORT" =~ ^[0-9]+$ ]]; then
  say \
    "❌ Error: Invalid input. The SSH port must be numeric and required text values cannot be empty." \
    "❌ Error: Datos invalidos. El puerto SSH debe ser numerico y los textos obligatorios no pueden estar vacios."
  exit 1
fi

# Optional web port validation / Validacion del puerto web opcional
if [ -n "$CUSTOM_WEB_PORT" ] && ! [[ "$CUSTOM_WEB_PORT" =~ ^[0-9]+$ ]]; then
  say \
    "❌ Error: The optional web port must be numeric when provided." \
    "❌ Error: El puerto web opcional debe ser numerico cuando se proporciona."
  exit 1
fi

# 2. Dynamically build the SSH tunnel arguments
TUNNEL_ARGS="-R ${CUSTOM_SSH_PORT}:localhost:22"
DESCRIPTION_TEXT="SSH ${CUSTOM_SSH_PORT}"

if [ -n "$CUSTOM_WEB_PORT" ]; then
  TUNNEL_ARGS="$TUNNEL_ARGS -R ${CUSTOM_WEB_PORT}:localhost:8006"
  DESCRIPTION_TEXT="$(text \
    "Web ${CUSTOM_WEB_PORT} and ${DESCRIPTION_TEXT}" \
    "Web ${CUSTOM_WEB_PORT} y ${DESCRIPTION_TEXT}")"
fi

# 3. Create the key directory / Crear el directorio de claves
say \
  "🔑 Generating a high-security SSH key pair..." \
  "🔑 Generando un par de claves SSH de alta seguridad..."
mkdir -p "$KEY_DIR"

if [ ! -f "$KEY_PATH" ]; then
  ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N "" -q
else
  say \
    "🔑 The SSH key already exists. Reusing it..." \
    "🔑 La clave SSH ya existe. Se reutilizara..."
fi

chown -R "$LOCAL_USER:$LOCAL_GROUP" "$KEY_DIR"
chmod 700 "$KEY_DIR"
chmod 600 "$KEY_PATH"
chmod 644 "$KEY_PATH.pub"

# 4. Copy and verify the key / Copiar y verificar la clave
echo ""
say \
  "🔑 Copying the public key to $REMOTE_USER@$TARGET_DOMAIN..." \
  "🔑 Copiando la clave publica a $REMOTE_USER@$TARGET_DOMAIN..."
say \
  "You may be asked for the remote user's password." \
  "Es posible que se solicite la contrasena del usuario remoto."

if ! command -v ssh-copy-id &>/dev/null; then
  say \
    "❌ Error: ssh-copy-id is not installed. Install the openssh-client package." \
    "❌ Error: ssh-copy-id no esta instalado. Instale el paquete openssh-client."
  exit 1
fi

if ! runuser -u "$LOCAL_USER" -- ssh-copy-id \
  -i "$KEY_PATH.pub" \
  -o "StrictHostKeyChecking=accept-new" \
  -p 1981 \
  "$REMOTE_USER@$TARGET_DOMAIN"; then
  say \
    "❌ Error: Could not copy the public key to the relay." \
    "❌ Error: No se pudo copiar la clave publica al relay."
  exit 1
fi

say \
  "🔄 Verifying SSH key access..." \
  "🔄 Verificando el acceso mediante la clave SSH..."
if ! runuser -u "$LOCAL_USER" -- /usr/bin/ssh \
  -o "BatchMode=yes" \
  -o "ConnectTimeout=10" \
  -o "StrictHostKeyChecking=accept-new" \
  -i "$KEY_PATH" \
  -p 1981 \
  "$REMOTE_USER@$TARGET_DOMAIN" true; then
  say \
    "❌ Error: SSH key authentication failed. The service was not created." \
    "❌ Error: La autenticacion por clave SSH fallo. El servicio no fue creado."
  exit 1
fi

# 5. Create the systemd service / Crear el servicio systemd
say \
  "⚙️  Creating the systemd service file..." \
  "⚙️  Creando el archivo del servicio systemd..."
SERVICE_PATH="/etc/systemd/system/ssh-tunnel.service"

cat << EOF > $SERVICE_PATH
[Unit]
Description=SSH Reverse Tunnel Multi-Service ($DESCRIPTION_TEXT)
After=network.target

[Service]
Type=simple
User=$LOCAL_USER
ExecStart=/usr/bin/ssh -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -o "StrictHostKeyChecking=accept-new" -i "$KEY_PATH" -N $TUNNEL_ARGS $REMOTE_USER@$TARGET_DOMAIN -p 1981
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 6. Enable and start the service / Habilitar e iniciar el servicio
say \
  "🚀 Enabling and starting the background service..." \
  "🚀 Habilitando e iniciando el servicio en segundo plano..."
systemctl daemon-reload
systemctl enable ssh-tunnel.service
systemctl restart ssh-tunnel.service

echo ""
echo "=================================================="
say \
  "🎉 Setup completed successfully on Debian!" \
  "🎉 Instalacion completada correctamente en Debian!"
echo "=================================================="
systemctl status ssh-tunnel.service --no-pager
