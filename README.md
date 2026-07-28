# Scripts

Colección de scripts y herramientas de sistema, organizados por tipo.

---

## ai/

Herramientas de despliegue de IA (LLM inference + RAG) con soporte para Ollama y vLLM.

### Requisitos previos

- Docker + Docker Compose (o docker-compose-plugin)
- NVIDIA GPU + drivers + NVIDIA Container Toolkit (opcional, requerido para vLLM)

Instalar NVIDIA Container Toolkit:

```bash
sudo bash ai/setup_nvidia_docker.sh
```

### Deploy con Docker (recomendado)

```bash
cd ai
bash deploy.sh
```

Menú interactivo que permite elegir el provider:
- `ollama` — solo Ollama (CPU/GPU, setup más simple)
- `vllm` — solo vLLM (requiere NVIDIA GPU, mejor rendimiento)
- `full` — ambos vLLM + Ollama

El script genera `.env` con API key, construye la imagen y levanta los containers. Al terminar muestra los endpoints y la configuración para Frappe.

**Endpoints expuestos:**

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| GET | `/health` | No | Health check |
| GET | `/health/deep` | Bearer | Chequeo profundo (Ollama/vLLM + ChromaDB) |
| POST | `/analyze` | Bearer | Inferencia de chat |
| GET | `/rag/collections` | Bearer | Lista colecciones ChromaDB |
| POST | `/rag/upsert` | Bearer | Inserta documentos en ChromaDB |
| POST | `/rag/query` | Bearer | Búsqueda semántica en ChromaDB |

**Usar docker-compose directamente:**

```bash
# Ollama
cd ai && docker compose --profile ollama up -d

# vLLM
VLLM_MODEL=Qwen/Qwen3-7B docker compose --profile vllm up -d

# Ambos
VLLM_MODEL=Qwen/Qwen3-7B docker compose --profile full up -d
```

Variables de entorno para vLLM: `VLLM_MODEL`, `VLLM_MAX_MODEL_LEN` (default: 2048), `VLLM_MAX_NUM_SEQS` (default: 2), `VLLM_GPU_MEM_UTIL` (default: 0.88).

### Deploy nativo (sin Docker)

Instala Ollama + AI Runtime como servicio systemd:

```bash
cd ai/ai-runtime
sudo bash install.sh
```

### vLLM standalone

Ejecuta solo vLLM como servidor OpenAI-compatible:

```bash
bash ai/run_vllm.sh <modelo-huggingface>
# Ejemplo:
bash ai/run_vllm.sh Qwen/Qwen3-7B
```

Expone en `http://localhost:8000/v1`.

### Validar la API

```bash
cd ai/ai-runtime
bash validate.sh http://127.0.0.1:8001
```

Requiere `CHATBOT_AI_BEARER_TOKEN` en el entorno si la API tiene autenticación.

### Configuración en Frappe

En `Chatbot Settings` / `Chatbot Analysis Settings`:

```
Model Provider           = Internal AI API
Internal AI API Base URL = http://<ai-server>:8001
Internal AI API Key      = <bearer token generado>
Internal AI Model        = llama3.2:1b  (Ollama)
                           Qwen/Qwen3-7B (vLLM)
```

---

## lan-mouse/

Compartir teclado/ratón entre equipos. Contiene el proyecto Rust y sus fuentes.

```bash
bash install-lanmouse.sh
```

Instala dependencias, compila y despliega Lan Mouse de forma nativa (Wayland/X11).

---

## system/

Utilidades de sistema Linux.

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
