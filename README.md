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

```bash
sudo bash system/01-install-kubectl.sh
sudo bash system/02-install-helm.sh
sudo bash system/03-install-kind.sh
sudo bash system/04-install-k9s.sh
sudo bash system/05-install-trivy.sh
sudo bash system/06-install-k6.sh
```

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
