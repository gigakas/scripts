#!/bin/bash
################################################################################
# Script CORREGIDO - RustDesk Server NATIVO Ubuntu 24.04
# Fix: Los binarios están dentro de carpeta amd64/
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║       RustDesk Server - Instalación Nativa FIXED         ║
║                   Ubuntu 24.04 LTS                        ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Ejecutar como root${NC}" 
   exit 1
fi

# Solicitar dominio
read -p "Dominio o IP pública: " DOMAIN
[ -z "$DOMAIN" ] && { echo -e "${RED}Error: Ingresa dominio/IP${NC}"; exit 1; }

echo ""
read -p "¿Continuar? (y/n): " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

echo ""
echo -e "${GREEN}[1/9] Actualizando sistema...${NC}"
apt update && apt upgrade -y

echo ""
echo -e "${GREEN}[2/9] Instalando dependencias...${NC}"
apt install -y wget unzip jq net-tools curl

echo ""
echo -e "${GREEN}[3/9] Detectando última versión...${NC}"
LATEST_RELEASE=$(curl -s https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest | jq -r '.tag_name')

if [ -z "$LATEST_RELEASE" ] || [ "$LATEST_RELEASE" = "null" ]; then
    echo -e "${YELLOW}Usando latest...${NC}"
    DOWNLOAD_URL="https://github.com/rustdesk/rustdesk-server/releases/latest/download/rustdesk-server-linux-amd64.zip"
else
    echo -e "${GREEN}Versión: ${LATEST_RELEASE}${NC}"
    DOWNLOAD_URL="https://github.com/rustdesk/rustdesk-server/releases/download/${LATEST_RELEASE}/rustdesk-server-linux-amd64.zip"
fi

echo ""
echo -e "${GREEN}[4/9] Descargando RustDesk Server...${NC}"
cd /tmp
rm -f rustdesk-server-linux-amd64.zip
rm -rf rustdesk-extract

if ! wget -q --show-progress "$DOWNLOAD_URL"; then
    echo -e "${RED}Error al descargar${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}[5/9] Extrayendo archivos...${NC}"
mkdir -p rustdesk-extract
unzip -q rustdesk-server-linux-amd64.zip -d rustdesk-extract

# FIX: Los binarios están en amd64/
cd rustdesk-extract

# Buscar donde están realmente los binarios
if [ -d "amd64" ]; then
    echo -e "${GREEN}✓ Encontrados en carpeta amd64/${NC}"
    cd amd64
elif [ -f "hbbs" ]; then
    echo -e "${GREEN}✓ Encontrados en raíz${NC}"
else
    echo -e "${RED}Error: No se encontraron los binarios${NC}"
    echo "Contenido del directorio:"
    ls -la
    exit 1
fi

# Verificar que los binarios existen
if [ ! -f "hbbs" ] || [ ! -f "hbbr" ]; then
    echo -e "${RED}Error: Binarios no encontrados${NC}"
    ls -la
    exit 1
fi

echo ""
echo -e "${GREEN}[6/9] Instalando binarios...${NC}"
mkdir -p /opt/rustdesk
cp hbbs hbbr /opt/rustdesk/

# Copiar rustdesk-utils si existe
if [ -f "rustdesk-utils" ]; then
    cp rustdesk-utils /opt/rustdesk/
fi

chmod +x /opt/rustdesk/hbbs /opt/rustdesk/hbbr

# Verificar instalación
if [ ! -f /opt/rustdesk/hbbs ]; then
    echo -e "${RED}Error: No se copiaron los binarios${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Binarios instalados en /opt/rustdesk${NC}"
ls -lh /opt/rustdesk/

# Limpiar temporales
cd /
rm -rf /tmp/rustdesk-extract /tmp/rustdesk-server-linux-amd64.zip

echo ""
echo -e "${GREEN}[7/9] Creando usuario rustdesk...${NC}"
id rustdesk &>/dev/null || useradd -r -s /bin/false rustdesk

echo ""
echo -e "${GREEN}[8/9] Configurando directorios...${NC}"
mkdir -p /var/lib/rustdesk
chown -R rustdesk:rustdesk /opt/rustdesk /var/lib/rustdesk

echo ""
echo -e "${GREEN}[9/9] Configurando firewall...${NC}"
if ! command -v ufw &>/dev/null; then
    apt install -y ufw
fi

ufw allow 22/tcp
ufw allow 21115/tcp comment 'RustDesk Web API'
ufw allow 21116/tcp comment 'RustDesk Signal TCP'
ufw allow 21116/udp comment 'RustDesk Signal UDP'
ufw allow 21117/tcp comment 'RustDesk Relay'
ufw allow 21118/tcp comment 'RustDesk Web Console'
ufw allow 21119/tcp comment 'RustDesk Relay Additional'
ufw --force enable

echo ""
echo -e "${GREEN}[10/10] Creando servicios systemd...${NC}"

# Servicio hbbs
cat > /etc/systemd/system/rustdesk-hbbs.service <<EOF
[Unit]
Description=RustDesk Signal Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=rustdesk
Group=rustdesk
WorkingDirectory=/var/lib/rustdesk
ExecStart=/opt/rustdesk/hbbs -r ${DOMAIN}:21117 -k _
Restart=on-failure
RestartSec=5
LimitNOFILE=1000000

StandardOutput=journal
StandardError=journal
SyslogIdentifier=rustdesk-hbbs

[Install]
WantedBy=multi-user.target
EOF

# Servicio hbbr
cat > /etc/systemd/system/rustdesk-hbbr.service <<EOF
[Unit]
Description=RustDesk Relay Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=rustdesk
Group=rustdesk
WorkingDirectory=/var/lib/rustdesk
ExecStart=/opt/rustdesk/hbbr -k _
Restart=on-failure
RestartSec=5
LimitNOFILE=1000000

StandardOutput=journal
StandardError=journal
SyslogIdentifier=rustdesk-hbbr

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rustdesk-hbbs rustdesk-hbbr

echo ""
echo -e "${GREEN}Iniciando servicios...${NC}"
systemctl start rustdesk-hbbs rustdesk-hbbr

echo ""
echo -e "${YELLOW}Esperando 10 segundos a que se generen las claves...${NC}"
sleep 10

# Verificar servicios
echo ""
echo -e "${YELLOW}Estado de servicios:${NC}"
systemctl status rustdesk-hbbs --no-pager -l | head -10
echo ""
systemctl status rustdesk-hbbr --no-pager -l | head -10

if systemctl is-active --quiet rustdesk-hbbs && systemctl is-active --quiet rustdesk-hbbr; then
    echo ""
    echo -e "${GREEN}✓ Servicios activos${NC}"
else
    echo ""
    echo -e "${RED}✗ Error en servicios. Logs:${NC}"
    journalctl -u rustdesk-hbbs -n 30 --no-pager
    journalctl -u rustdesk-hbbr -n 30 --no-pager
    exit 1
fi

echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║            ✓ INSTALACIÓN COMPLETADA                       ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo -e "${YELLOW}🔑 Clave pública:${NC}"
if [ -f /var/lib/rustdesk/id_ed25519.pub ]; then
    PUBLIC_KEY=$(cat /var/lib/rustdesk/id_ed25519.pub)
    echo -e "${GREEN}${PUBLIC_KEY}${NC}"
else
    echo -e "${YELLOW}Aún no generada. Espera 30 segundos y ejecuta:${NC}"
    echo "cat /var/lib/rustdesk/id_ed25519.pub"
    PUBLIC_KEY="PENDIENTE"
fi

echo ""
echo -e "${YELLOW}📝 Configuración para clientes RustDesk:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ID Server:    ${DOMAIN}"
echo "  Relay Server: ${DOMAIN}"
echo "  Key:          ${PUBLIC_KEY}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo -e "${YELLOW}🔧 Comandos útiles:${NC}"
echo "  Ver clave:        cat /var/lib/rustdesk/id_ed25519.pub"
echo "  Ver logs hbbs:    journalctl -u rustdesk-hbbs -f"
echo "  Ver logs hbbr:    journalctl -u rustdesk-hbbr -f"
echo "  Reiniciar:        systemctl restart rustdesk-hbbs rustdesk-hbbr"
echo "  Estado:           systemctl status rustdesk-hbbs rustdesk-hbbr"
echo "  Detener:          systemctl stop rustdesk-hbbs rustdesk-hbbr"
echo ""
echo -e "${YELLOW}📁 Ubicación:${NC}"
echo "  Binarios:         /opt/rustdesk/"
echo "  Datos/claves:     /var/lib/rustdesk/"
echo "  Servicios:        /etc/systemd/system/rustdesk-*.service"
echo ""
echo -e "${YELLOW}🔍 Verificar puertos:${NC}"
echo "  ss -tulpn | grep -E '2111[5-9]'"
echo ""
echo -e "${GREEN}✓ RustDesk Server listo para usar${NC}"
echo ""

# Crear script de info
cat > /root/rustdesk-info.sh <<'EOFINFO'
#!/bin/bash
echo "═══════════════════════════════════════════════════════════"
echo "  RustDesk Server - Información"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "🔑 Clave pública:"
if [ -f /var/lib/rustdesk/id_ed25519.pub ]; then
    cat /var/lib/rustdesk/id_ed25519.pub
else
    echo "No encontrada (servicios recién iniciados)"
fi
echo ""
echo "📊 Estado de servicios:"
systemctl status rustdesk-hbbs --no-pager | head -3
systemctl status rustdesk-hbbr --no-pager | head -3
echo ""
echo "🌐 Puertos escuchando:"
ss -tulpn | grep -E '2111[5-9]' | awk '{print $5}' | sort -u
echo ""
echo "📈 Uso de recursos:"
ps aux | grep -E '(hbbs|hbbr)' | grep -v grep
echo ""
EOFINFO

chmod +x /root/rustdesk-info.sh

echo -e "${YELLOW}💡 Tip: Ejecuta 'bash /root/rustdesk-info.sh' para ver info rápida${NC}"
echo ""
