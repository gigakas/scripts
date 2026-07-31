# Scripts

Colección de scripts y herramientas de sistema, organizados por tipo.

---

## ai/

Herramientas de despliegue de IA (LLM inference + RAG) con soporte para Ollama y vLLM,
cada uno en su propio docker-compose independiente. Ver [ai/README.md](ai/README.md)
para la guía completa (arquitectura, instalación, gestión de modelos, seguridad).

```bash
cd ai
bash deploy-docker.sh
```

---

## proxmox/

Script interactivo y portable (no hardcodea IPs/VMIDs de ningún entorno
particular) para provisionar la infraestructura del ejercicio de
[`DEVOPS-PRACTICE-FRAPPE.md`](DEVOPS-PRACTICE-FRAPPE.md) en **cualquier
instalación de Proxmox nueva**: detecta storage/bridge disponibles, crea la
VM template Ubuntu 24.04 + cloud-init desde cero si no tenés una, clona
(linked clone) el control plane + N workers + CI runner, y crea los LXC de
observabilidad/registry. Corre **en el host Proxmox**, no en las VMs.

```bash
sudo bash proxmox/provision-devops-stack.sh
```

Te va preguntando storage, bridge, red, cuántos workers, etc. — no hace
falta editar el script. Es idempotente **por nombre** (no por VMID/CTID,
que siempre es uno libre): correrlo de nuevo con más workers solo crea los
que faltan, sin duplicar ni pisar la IP de los que ya existen (cada rol
tiene un offset de IP fijo). Validado corriéndolo contra stubs de
`qm`/`pct`/`pvesh`/`pveam` que simulan sus salidas reales — no se probó
contra un Proxmox real todavía.

---

## apps/lan-mouse/

Compartir teclado/ratón entre equipos. `src/` es el clon del proyecto Rust upstream
([feschber/lan-mouse](https://github.com/feschber/lan-mouse)); `install.sh` compila
e instala el binario de forma nativa (Wayland/X11).

```bash
bash apps/lan-mouse/install.sh
```

---

## system/

Utilidades de sistema Linux.

### Instalar Docker

Instala Docker Engine (docker-ce) desde el repo oficial en Ubuntu 24.04/26.04 o Debian 12/13:

```bash
sudo bash system/00-install-docker.sh
```

### Toolchain DevOps (ejercicio Frappe)

Scripts numerados para instalar, en orden, las herramientas del ejercicio
práctico de [`DEVOPS-PRACTICE-FRAPPE.md`](DEVOPS-PRACTICE-FRAPPE.md) sobre
una VM Ubuntu 24.04 dedicada. Cada uno es independiente y agrega una sola
herramienta; al final va a existir un script integrador que los corre todos
en secuencia.

| # | Script | Instala |
|---|---|---|
| 00 | `00-install-docker.sh` | Docker Engine + Compose (ver arriba) |
| 01 | `01-install-kubectl.sh` | `kubectl` (CLI de Kubernetes, binario oficial) |
| 02 | `02-install-helm.sh` | Helm (gestor de paquetes de Kubernetes) |
| 03 | `03-install-kind.sh` | `kind` (cluster de Kubernetes local, nodos como contenedores Docker) |
| 04 | `04-install-k9s.sh` | k9s (TUI para navegar el cluster) |
| 05 | `05-install-trivy.sh` | Trivy (escaneo de vulnerabilidades de imagenes/manifests) |
| 06 | `06-install-k6.sh` | k6 (generador de carga / load testing) |
| 07 | `07-install-argocd-cli.sh` | Cliente CLI de ArgoCD (GitOps) |
| 08 | `08-install-velero-cli.sh` | Cliente CLI de Velero (backup/restore) |

```bash
sudo bash system/01-install-kubectl.sh
sudo bash system/02-install-helm.sh
sudo bash system/03-install-kind.sh
sudo bash system/04-install-k9s.sh
sudo bash system/05-install-trivy.sh
sudo bash system/06-install-k6.sh
sudo bash system/07-install-argocd-cli.sh
sudo bash system/08-install-velero-cli.sh
```

Todos probados end-to-end contra la VM de práctica (Ubuntu 24.04, `local.devops`).

### Integrador (corre todo en orden)

```bash
sudo bash system/install-devops-stack.sh
```

Descubre automáticamente todos los `system/NN-install-*.sh` (por orden
numérico) y los corre en secuencia — agregar un componente nuevo es solo
dejar el script numerado junto a los demás, no hace falta tocar el
integrador.

### VMware modo promiscuo

Habilita permanentemente el modo promiscuo en redes de VMware Workstation:

```bash
sudo system/promiscusModevmware.sh
```

Crea un servicio systemd que aplica permisos 0666 a `/dev/vmnet*` al arrancar VMware.

### Remover logo de Ubuntu

Elimina el logo de Ubuntu del menú de actividades:

```bash
sudo system/remove-ubuntu-logo.sh
```
