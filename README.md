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
sudo bash system/install-docker.sh
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
