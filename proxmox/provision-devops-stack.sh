#!/usr/bin/env bash
# Instalador interactivo y portable: provisiona el stack de VMs/LXC del
# ejercicio de DEVOPS-PRACTICE-FRAPPE.md en CUALQUIER instalacion de
# Proxmox nueva (no depende de un VMID/IP/storage especifico, los detecta
# o los pregunta). Corre esto EN EL HOST PROXMOX, no en las VMs.
#
# No se probo contra un Proxmox real (no hay acceso a ese host desde esta
# sesion) - se valido corriendolo con stubs de qm/pct/pvesh/pveam que
# simulan sus salidas reales. Es idempotente por NOMBRE (no por VMID/CTID,
# que siempre es uno libre): si ya existe una VM/CT con ese nombre, la
# saltea. Cada rol tiene un offset de IP fijo (cp=+0, workers=+1..+49,
# ci-runner=+50, monitoring=+60, registry=+61) para que agregar nodos mas
# adelante (ej. subir de 2 a 3 workers) nunca pise la IP de uno existente.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo -e "\n${CYAN}=== $* ===${NC}\n"; }

ask() {
    local prompt="$1" default="$2" var
    read -r -p "$prompt [$default]: " var
    echo "${var:-$default}"
}

ask_yes_no() {
    local prompt="$1" default="${2:-y}" suffix="[Y/n]" answer
    [ "$default" = "n" ] && suffix="[y/N]"
    read -r -p "$prompt $suffix " answer
    answer="${answer:-$default}"
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || { err "'$1' no encontrado. Corre esto en el host Proxmox."; exit 1; }
}

if [ "$EUID" -ne 0 ]; then
    err "Corre esto como root en el host Proxmox."
    exit 1
fi
require_cmd qm
require_cmd pct
require_cmd pvesh
require_cmd pveam

title "Provisioning del stack DevOps (Frappe practice)"

# ------------------------------------------------------------------
# 1) Storage: listar pools y elegir uno con soporte de linked clone
# ------------------------------------------------------------------
info "Storage disponibles:"
pvesm status | awk 'NR==1 || $2 ~ /lvmthin|zfspool/'
STORAGE="$(ask "Storage a usar (debe soportar linked clone: lvmthin o zfspool)" "$(pvesm status | awk '$2 ~ /lvmthin|zfspool/{print $1; exit}')")"
if [ -z "$STORAGE" ]; then
    warn "No se detecto un storage con thin-provisioning. Vas a poder crear las VMs igual, pero se haran full clone (mas espacio)."
    STORAGE="$(ask "Storage a usar" "local-lvm")"
fi

# ------------------------------------------------------------------
# 2) Red: bridge, subred, gateway, DNS
# ------------------------------------------------------------------
info "Bridges disponibles:"
ls /sys/class/net | grep '^vmbr' || true
BRIDGE="$(ask "Bridge de red" "vmbr0")"
GATEWAY="$(ask "Gateway de la red" "192.168.1.1")"
CIDR="$(ask "Mascara CIDR" "24")"
BASE_IP="$(echo "$GATEWAY" | cut -d. -f1-3)"
START_HOST="$(ask "Ultimo octeto de IP donde empezar a asignar (se van a usar N consecutivos)" "101")"
NAMESERVER="$(ask "DNS server" "8.8.8.8")"
SEARCHDOMAIN="$(ask "Search domain" "local")"

# ------------------------------------------------------------------
# 3) Template de VM (Ubuntu 24.04 + cloud-init). Si no existe, ofrece
#    crearlo desde la cloud image oficial de Ubuntu.
# ------------------------------------------------------------------
TEMPLATE_VMID="$(ask "VMID de tu VM template Ubuntu 24.04 (0 = no tengo, crear uno ahora)" "0")"

if [ "$TEMPLATE_VMID" = "0" ] || ! qm status "$TEMPLATE_VMID" >/dev/null 2>&1; then
    title "Creando VM template Ubuntu 24.04 desde cero"
    TEMPLATE_VMID="$(pvesh get /cluster/nextid)"
    IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    IMG_FILE="/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img"
    mkdir -p "$(dirname "$IMG_FILE")"
    if [ ! -f "$IMG_FILE" ]; then
        info "Descargando cloud image de Ubuntu 24.04..."
        curl -fsSL -o "$IMG_FILE" "$IMG_URL"
    fi
    info "Creando VM $TEMPLATE_VMID para el template..."
    qm create "$TEMPLATE_VMID" --name "ubuntu-2404-cloudinit-template" --memory 2048 --cores 2 \
        --net0 "virtio,bridge=${BRIDGE}" --scsihw virtio-scsi-pci --ostype l26
    qm importdisk "$TEMPLATE_VMID" "$IMG_FILE" "$STORAGE"
    qm set "$TEMPLATE_VMID" --scsi0 "${STORAGE}:vm-${TEMPLATE_VMID}-disk-0"
    qm set "$TEMPLATE_VMID" --ide2 "${STORAGE}:cloudinit"
    qm set "$TEMPLATE_VMID" --boot order=scsi0 --serial0 socket --vga serial0
    qm set "$TEMPLATE_VMID" --agent enabled=1
    qm resize "$TEMPLATE_VMID" scsi0 10G
    info "Convirtiendo VM $TEMPLATE_VMID a template..."
    qm template "$TEMPLATE_VMID"
    info "Template listo (VMID $TEMPLATE_VMID). Instala/actualiza paquetes clonando y ajustando a mano si necesitas algo mas alla de Ubuntu base + cloud-init + qemu-guest-agent."
fi

# ------------------------------------------------------------------
# 4) SSH key a inyectar
# ------------------------------------------------------------------
SSH_PUBKEY_FILE="$(ask "Archivo con tu clave publica SSH a preinstalar (vacio = ninguna, copias despues con ssh-copy-id)" "")"
SSHKEYS_ARG=()
if [ -n "$SSH_PUBKEY_FILE" ] && [ -f "$SSH_PUBKEY_FILE" ]; then
    SSHKEYS_ARG=(--sshkeys "$SSH_PUBKEY_FILE")
else
    warn "Sin clave SSH preinstalada - vas a necesitar 'ssh-copy-id' a mano en cada nodo despues."
fi

# ------------------------------------------------------------------
# 5) Topologia: cuantos workers, si sumar el registry opcional
# ------------------------------------------------------------------
NUM_WORKERS="$(ask "Cantidad de k8s workers" "2")"
WITH_REGISTRY="n"
ask_yes_no "Sumar LXC de registry privado (opcional)?" "n" && WITH_REGISTRY="y"

# ------------------------------------------------------------------
# 6) Detectar template de LXC Ubuntu 24.04 (descargarlo si falta)
# ------------------------------------------------------------------
LXC_TEMPLATE_STORAGE="$(ask "Storage donde viven los templates de contenedor" "local")"
LXC_TEMPLATE="$(pveam list "$LXC_TEMPLATE_STORAGE" 2>/dev/null | awk '/ubuntu-24.04-standard/{print $1; exit}' | sed "s#${LXC_TEMPLATE_STORAGE}:vztmpl/##")"
if [ -z "$LXC_TEMPLATE" ]; then
    info "No hay template de Ubuntu 24.04 para LXC descargado, buscando el disponible..."
    pveam update >/dev/null 2>&1 || true
    LXC_TEMPLATE="$(pveam available --section system | awk '/ubuntu-24.04-standard/{print $2; exit}')"
    if [ -z "$LXC_TEMPLATE" ]; then
        err "No se encontro ningun template ubuntu-24.04-standard en 'pveam available'. Revisa manualmente."
        exit 1
    fi
    info "Descargando $LXC_TEMPLATE..."
    pveam download "$LXC_TEMPLATE_STORAGE" "$LXC_TEMPLATE"
fi

# ------------------------------------------------------------------
# Funciones de provisioning
#
# La idempotencia se chequea por NOMBRE, no por VMID/CTID: como el ID se
# pide siempre a "pvesh get /cluster/nextid" (que por definicion da uno
# libre), nunca va a "chocar" con uno existente - si chequeramos por ID
# nunca detectariamos un duplicado. Por eso se busca primero si ya existe
# una VM/CT con ese nombre (qm list / pct list) antes de pedir un ID nuevo.
# ------------------------------------------------------------------
find_qm_by_name() {
    qm list | awk -v n="$1" '$2==n{print $1; exit}'
}

find_pct_by_name() {
    # $NF (ultimo campo), no $4: la columna "Lock" suele venir vacia y
    # awk no genera un campo vacio para eso - el nombre corre a $3 cuando
    # no hay lock y a $4 cuando si hay, asi que $NF es lo unico estable.
    pct list | awk -v n="$1" '$NF==n{print $1; exit}'
}

provision_vm() {
    local cores="$1" mem="$2" disk="$3" ip="$4" name="$5" existing

    existing="$(find_qm_by_name "$name")"
    if [ -n "$existing" ]; then
        warn "VM '$name' ya existe (VMID $existing), la salteo."
        return
    fi

    local vmid
    vmid="$(pvesh get /cluster/nextid)"

    info "Clonando template $TEMPLATE_VMID -> $vmid ($name)..."
    qm clone "$TEMPLATE_VMID" "$vmid" --name "$name" --full false 2>/dev/null \
        || qm clone "$TEMPLATE_VMID" "$vmid" --name "$name" --full true

    qm set "$vmid" --cores "$cores" --memory "$mem" >/dev/null
    qm resize "$vmid" scsi0 "${disk}G" >/dev/null 2>&1 || warn "No se pudo resize scsi0 en $vmid (nombre de disco puede diferir en tu template)."
    qm set "$vmid" \
        --ipconfig0 "ip=${ip}/${CIDR},gw=${GATEWAY}" \
        --nameserver "$NAMESERVER" \
        --searchdomain "$SEARCHDOMAIN" \
        --ciuser devops \
        "${SSHKEYS_ARG[@]}" >/dev/null

    qm start "$vmid"
    info "$name (VMID $vmid) iniciada en $ip"
}

provision_lxc() {
    local cores="$1" mem="$2" disk="$3" ip="$4" name="$5" existing

    existing="$(find_pct_by_name "${name#local.}")"
    if [ -n "$existing" ]; then
        warn "CT '$name' ya existe (CTID $existing), lo salteo."
        return
    fi

    local ctid
    ctid="$(pvesh get /cluster/nextid)"

    info "Creando LXC $ctid ($name)..."
    pct create "$ctid" "${LXC_TEMPLATE_STORAGE}:vztmpl/${LXC_TEMPLATE}" \
        --hostname "${name#local.}" \
        --cores "$cores" \
        --memory "$mem" \
        --rootfs "${STORAGE}:${disk}" \
        --net0 "name=eth0,bridge=${BRIDGE},ip=${ip}/${CIDR},gw=${GATEWAY}" \
        --nameserver "$NAMESERVER" \
        --searchdomain "$SEARCHDOMAIN" \
        --unprivileged 1 \
        --features "nesting=0" >/dev/null

    pct start "$ctid"
    if [ -n "$SSH_PUBKEY_FILE" ] && [ -f "$SSH_PUBKEY_FILE" ]; then
        sleep 5
        pct exec "$ctid" -- mkdir -p /root/.ssh
        pct push "$ctid" "$SSH_PUBKEY_FILE" /root/.ssh/authorized_keys
        pct exec "$ctid" -- chmod 600 /root/.ssh/authorized_keys
    fi
    info "$name (CTID $ctid) iniciado en $ip"
}

# ------------------------------------------------------------------
# 7) Provisionar todos los nodos (VMID/CTID se resuelven adentro de
#    provision_vm/provision_lxc, recien si el nombre no existe todavia)
#
# IPs por OFFSET FIJO por rol, no secuencial: si corres el script de
# nuevo mas adelante para agregar un worker (ej. subir de 2 a 3), cada
# rol conserva siempre la misma IP sin importar que otros nodos ya
# existan o en que orden se creen - evita que un nodo nuevo choque con
# la IP ya asignada de otro (soporta hasta 49 workers antes de pisar el
# offset de ci-runner, mas que de sobra para este ejercicio).
# ------------------------------------------------------------------
title "Creando nodos"

provision_vm 2 4096 40 "${BASE_IP}.${START_HOST}" "local.k8s-cp"

for i in $(seq 1 "$NUM_WORKERS"); do
    provision_vm 2 6144 50 "${BASE_IP}.$((START_HOST + i))" "local.k8s-worker${i}"
done

provision_vm 2 3072 40 "${BASE_IP}.$((START_HOST + 50))" "local.k8s-ci-runner"

provision_lxc 2 3072 40 "${BASE_IP}.$((START_HOST + 60))" "local.monitoring"

if [ "$WITH_REGISTRY" = "y" ]; then
    provision_lxc 1 2048 60 "${BASE_IP}.$((START_HOST + 61))" "local.registry"
fi

title "🎉 Provisioning completo"
echo "Agrega esto al /etc/hosts de la maquina desde donde vas a operar:"
echo ""
echo "${BASE_IP}.${START_HOST} local.k8s-cp"
for i in $(seq 1 "$NUM_WORKERS"); do
    echo "${BASE_IP}.$((START_HOST + i)) local.k8s-worker${i}"
done
echo "${BASE_IP}.$((START_HOST + 50)) local.k8s-ci-runner"
echo "${BASE_IP}.$((START_HOST + 60)) local.monitoring"
[ "$WITH_REGISTRY" = "y" ] && echo "${BASE_IP}.$((START_HOST + 61)) local.registry"
true
