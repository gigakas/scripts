#!/bin/bash
# Provisiona (o re-provisiona) todo el stack de VMs/LXC del ejercicio de
# DEVOPS-PRACTICE-FRAPPE.md a partir de UNA VM template ya creada a mano
# (Ubuntu 24.04 + cloud-init + qemu-guest-agent, convertida a Template en
# Proxmox) y UN template de LXC estandar de Ubuntu 24.04.
#
# Corre esto EN EL HOST PROXMOX (no en local.devops ni en ninguna VM).
# No lo probamos contra tu Proxmox real - no tengo acceso a ese host desde
# esta sesion, asi que revisa las variables de la seccion CONFIG antes de
# correrlo. Es idempotente: si un VMID/CTID ya existe, lo saltea con un aviso
# en vez de fallar o duplicar.
set -euo pipefail

# ============================================================
# CONFIG - AJUSTA ESTO A TU PROXMOX ANTES DE CORRER
# ============================================================

TEMPLATE_VMID=9000              # VMID de la VM template (Ubuntu 24.04 + cloud-init), ya creada a mano
STORAGE="local-lvm"             # Storage pool (debe soportar linked clone: LVM-thin o ZFS)
BRIDGE="vmbr0"                  # Bridge de red de Proxmox
GATEWAY="192.168.171.1"         # Gateway de la red 192.168.171.0/24
CIDR="24"
NAMESERVER="8.8.8.8"
SEARCHDOMAIN="local"
SSH_PUBKEY_FILE="/root/.ssh/authorized_keys_devops"  # 1 clave publica por linea, se inyecta via cloud-init/pct

LXC_TEMPLATE_STORAGE="local"    # Storage donde viven los templates de contenedor (pveam)
LXC_TEMPLATE="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"  # Ajusta al nombre real disponible (ver: pveam available)

# vCPU | RAM(MB) | Disco(GB) | IP                | VMID/CTID | Nombre
VMS=(
  "2|4096|40|192.168.171.101|101|local.k8s-cp"
  "2|6144|50|192.168.171.102|102|local.k8s-worker1"
  "2|6144|50|192.168.171.103|103|local.k8s-worker2"
  "2|3072|40|192.168.171.104|104|local.k8s-ci-runner"
)

LXCS=(
  "2|3072|40|192.168.171.105|105|local.monitoring"
  "1|2048|60|192.168.171.106|106|local.registry"
)

# ============================================================
# No hace falta tocar nada debajo de esta linea
# ============================================================

log() { echo "[+] $*"; }
warn() { echo "[!] $*"; }

if [ "$EUID" -ne 0 ]; then
  echo "[-] Corre esto como root en el host Proxmox."
  exit 1
fi

if ! command -v qm >/dev/null 2>&1 || ! command -v pct >/dev/null 2>&1; then
  echo "[-] No se encontraron 'qm'/'pct'. Este script corre en el host Proxmox, no en una VM."
  exit 1
fi

if ! qm status "$TEMPLATE_VMID" >/dev/null 2>&1; then
  echo "[-] No existe una VM/template con VMID $TEMPLATE_VMID. Creala primero (ver Fase 0.5 del ejercicio)."
  exit 1
fi

SSHKEYS_ARG=()
if [ -f "$SSH_PUBKEY_FILE" ]; then
  SSHKEYS_ARG=(--sshkeys "$SSH_PUBKEY_FILE")
else
  warn "No se encontro $SSH_PUBKEY_FILE - las VMs/LXC quedaran sin key preinstalada (habra que copiarla a mano con ssh-copy-id despues)."
fi

provision_vm() {
  local cores="$1" mem="$2" disk="$3" ip="$4" vmid="$5" name="$6"

  if qm status "$vmid" >/dev/null 2>&1; then
    warn "VM $vmid ($name) ya existe, la salteo."
    return
  fi

  log "Clonando template $TEMPLATE_VMID -> $vmid ($name), linked clone..."
  qm clone "$TEMPLATE_VMID" "$vmid" --name "$name" --full false

  log "Ajustando recursos: $cores vCPU / ${mem} MB RAM..."
  qm set "$vmid" --cores "$cores" --memory "$mem"

  log "Redimensionando disco a ${disk}G (solo crece, nunca achica)..."
  qm resize "$vmid" scsi0 "${disk}G" || warn "No se pudo resize scsi0 en $vmid, revisa el nombre del disco (puede ser virtio0/sata0 segun tu template)."

  log "Configurando red estatica $ip/$CIDR via cloud-init..."
  qm set "$vmid" \
    --ipconfig0 "ip=${ip}/${CIDR},gw=${GATEWAY}" \
    --nameserver "$NAMESERVER" \
    --searchdomain "$SEARCHDOMAIN" \
    --ciuser devops \
    "${SSHKEYS_ARG[@]}"

  log "Iniciando $name (VMID $vmid)..."
  qm start "$vmid"
}

provision_lxc() {
  local cores="$1" mem="$2" disk="$3" ip="$4" ctid="$5" name="$6"

  if pct status "$ctid" >/dev/null 2>&1; then
    warn "CT $ctid ($name) ya existe, lo salteo."
    return
  fi

  log "Creando LXC $ctid ($name)..."
  pct create "$ctid" "${LXC_TEMPLATE_STORAGE}:vztmpl/${LXC_TEMPLATE}" \
    --hostname "${name#local.}" \
    --cores "$cores" \
    --memory "$mem" \
    --rootfs "${STORAGE}:${disk}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${ip}/${CIDR},gw=${GATEWAY}" \
    --nameserver "$NAMESERVER" \
    --searchdomain "$SEARCHDOMAIN" \
    --unprivileged 1 \
    --features "nesting=0"

  if [ -f "$SSH_PUBKEY_FILE" ]; then
    log "Inyectando clave SSH publica en el CT..."
    pct start "$ctid"
    sleep 5
    pct exec "$ctid" -- mkdir -p /root/.ssh
    pct push "$ctid" "$SSH_PUBKEY_FILE" /root/.ssh/authorized_keys
    pct exec "$ctid" -- chmod 600 /root/.ssh/authorized_keys
  else
    log "Iniciando $name (CTID $ctid)..."
    pct start "$ctid"
  fi
}

echo "=========================================================="
echo " Provisionando stack DevOps (Frappe practice) en Proxmox"
echo "=========================================================="

for entry in "${VMS[@]}"; do
  IFS='|' read -r cores mem disk ip vmid name <<< "$entry"
  provision_vm "$cores" "$mem" "$disk" "$ip" "$vmid" "$name"
done

for entry in "${LXCS[@]}"; do
  IFS='|' read -r cores mem disk ip ctid name <<< "$entry"
  provision_lxc "$cores" "$mem" "$disk" "$ip" "$ctid" "$name"
done

echo "=========================================================="
echo " 🎉 Provisioning completo"
echo "=========================================================="
echo ""
echo "Agrega esto a /etc/hosts de las maquinas que necesiten resolver los nombres:"
for entry in "${VMS[@]}" "${LXCS[@]}"; do
  IFS='|' read -r _ _ _ ip _ name <<< "$entry"
  echo "$ip $name"
done
