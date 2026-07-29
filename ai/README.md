# Chatbot AI Runtime

API interna (FastAPI) para chat/analisis y RAG, con dos backends de inferencia
intercambiables: **Ollama** y **vLLM**. Ambos corren en contenedores Docker
separados y totalmente independientes entre si.

## Arquitectura

```
Cliente -> ai-runtime-ollama (puerto 8001) -> ollama-server (11434)
Cliente -> ai-runtime-vllm   (puerto 8002) -> vllm-server   (8000)
```

- **Misma API para ambos**: `ai-runtime-ollama` y `ai-runtime-vllm` corren
  exactamente el mismo codigo (`./ai-runtime`), solo cambia la configuracion
  (`CHATBOT_AI_PROVIDER` y la URL del backend). El contrato de endpoints
  (`/analyze`, `/rag/*`, `/health`, `/models`) es identico.
- **Independientes**: cada backend vive en su propio docker-compose, con su
  propia red y sus propios volumenes. Puedes levantar solo uno, el otro, o
  ambos (corriendo los dos comandos).
- **Los modelos NO se comparten entre Ollama y vLLM.** Ollama usa su propio
  formato interno (GGUF); vLLM carga pesos en formato Hugging Face
  (safetensors). Aunque pidas "el mismo modelo" a los dos, cada uno descarga
  y cachea su propia copia por separado.

## Archivos

| Archivo | Que levanta |
|---|---|
| `docker-compose.ollama.yml` | `ai-runtime-ollama` + `ollama` (imagen `latest`, CPU) |
| `docker-compose.ollama.gpu.yml` | Override opcional: agrega GPU NVIDIA a `ollama` (usar junto al archivo anterior) |
| `docker-compose.vllm.yml` | `ai-runtime-vllm` + `vllm` (imagen `latest`, requiere GPU NVIDIA) |
| `deploy-docker.sh` | Instalador interactivo (Docker): elige un backend, genera el `.env` y levanta el stack |
| `run_vllm.sh` | Lanza un vLLM suelto con `docker run` (fuera de compose), para pruebas rapidas |
| `setup_nvidia_docker.sh` | Instala el NVIDIA Container Toolkit (requerido para vLLM y para el override GPU de Ollama) |
| `ai-runtime/` | Codigo fuente de la API (FastAPI) e `install-native.sh` para desplegarla sin Docker (systemd) |

## Instalacion rapida

```bash
./deploy-docker.sh
```

Pregunta que backend instalar (Ollama o vLLM, segun si detecta GPU NVIDIA),
pide los parametros necesarios, genera `ai-runtime/.env` con un
`CHATBOT_AI_BEARER_TOKEN` aleatorio, y levanta el stack correspondiente.
Para tener ambos backends corriendo, ejecuta `./deploy-docker.sh` dos veces (una
por cada opcion) — son stacks independientes, no hay conflicto entre ellos.

### Manual (sin deploy-docker.sh)

```bash
# Ollama (CPU)
docker compose -f docker-compose.ollama.yml up -d --build

# Ollama con GPU NVIDIA (override opcional)
docker compose -f docker-compose.ollama.yml -f docker-compose.ollama.gpu.yml up -d --build

# vLLM (siempre requiere GPU NVIDIA)
VLLM_MODEL=Qwen/Qwen3-7B docker compose -f docker-compose.vllm.yml up -d --build
```

## Gestion de modelos

### Ollama
Un solo contenedor sirve varios modelos a la vez. No se toca ningun archivo:

```bash
docker exec ollama-server ollama pull llama3.2:1b   # agregar
docker exec ollama-server ollama rm llama3.2:1b     # quitar
docker exec ollama-server ollama list                # ver los que hay
```

### vLLM
Cada modelo requiere su propio contenedor (un proceso vLLM = un modelo fijo).
Por defecto viene un solo modelo (`vllm`, controlado por `VLLM_MODEL`). Para
agregar un segundo modelo (`vllm-2`, `vllm-3`, ...), sigue la receta comentada
dentro de `docker-compose.vllm.yml`: copiar el bloque de servicio, cambiar el
prefijo de variables (`VLLM2_*`, `VLLM3_*`...), sumar su URL a
`VLLM_EXTRA_BASE_URLS` en `ai-runtime-vllm`, y `docker compose up -d --build`.
La API elige automaticamente a que contenedor mandar cada request segun el
campo `"model"` de `/analyze`.

## Seguridad

- La API (`ai-runtime-*`) exige `Authorization: Bearer <CHATBOT_AI_BEARER_TOKEN>`
  en `/analyze`, `/rag/*` y `/health/deep` si esa variable esta definida en
  `ai-runtime/.env`. **Si esta vacia, la API queda sin proteccion.**
- Los puertos de los motores de inferencia (`vllm:8000`, `ollama:11434`) estan
  atados a `127.0.0.1` en ambos compose — no quedan expuestos en la red; solo
  se llega a ellos desde el propio host o desde su `ai-runtime-*` via la red
  interna de Docker. El control de acceso real vive en el bearer token de la API.
- Si el motor de inferencia corre en **otra maquina** (no vía estos
  docker-compose, sino accedido por IP/red), esos puertos no tienen
  autenticacion propia: cualquiera que llegue a esa IP puede usarlos directo.
  vLLM soporta `--api-key` nativo para ese caso; Ollama no tiene auth nativa
  (requeriria un proxy delante o restriccion por firewall/VPN).

## Persistencia

Todo lo importante vive en volumenes Docker nombrados (sobreviven a
`docker compose down`; se borran solo con `down -v`):

| Volumen | Contenido |
|---|---|
| `chatbot_ollama_data` | Modelos descargados por Ollama |
| `chatbot_vllm_hf_cache` | Pesos de Hugging Face descargados por vLLM |
| `chatbot_chroma_data_ollama` / `chatbot_chroma_data_vllm` | Colecciones RAG (ChromaDB), una por backend |

## Variables de entorno principales

`ai-runtime/.env` (compartido, ver `.env.example`):

| Variable | Uso |
|---|---|
| `CHATBOT_AI_BEARER_TOKEN` | Token para autenticar contra la API |
| `EMBEDDING_PROVIDER` / `EMBEDDING_MODEL` | Motor y modelo usado para embeddings de RAG |
| `REQUEST_TIMEOUT` | Timeout (segundos) para llamadas al motor de inferencia |
| `CHROMA_PERSIST_DIR` | Ruta interna donde ChromaDB persiste sus datos |

Variables por servicio (pasadas como entorno al correr `docker compose`, no
en el `.env`): `OLLAMA_PORT`, `CHATBOT_AI_OLLAMA_PORT` para el stack de
Ollama; `VLLM_MODEL`, `VLLM_PORT`, `VLLM_MAX_MODEL_LEN`,
`VLLM_MAX_NUM_SEQS`, `VLLM_GPU_MEM_UTIL`, `VLLM_EXTRA_ARGS`,
`CHATBOT_AI_VLLM_PORT` para el de vLLM. `deploy-docker.sh` las pide de forma
interactiva.

## Endpoints de la API

- `GET /health` — estado basico (publico)
- `GET /health/deep` — estado detallado incluyendo backend y ChromaDB (requiere bearer token)
- `GET /models` / `GET /v1/models` — modelos disponibles en el backend activo
- `POST /analyze` — chat/completion (requiere bearer token)
- `GET /rag/collections`, `POST /rag/upsert`, `POST /rag/query` — RAG sobre ChromaDB (requiere bearer token)

Ver `ai-runtime/reverse-proxy.md` para exponerla detras de Nginx con TLS.
