# Chatbot AI Runtime

API interna (FastAPI) para chat/analisis y RAG, con dos backends de inferencia
intercambiables: **Ollama** y **vLLM**. Ambos corren en contenedores Docker
separados y totalmente independientes entre si.

## Arquitectura

```
Cliente -> fastapi-ollama (puerto 8001) -> ai-runtime-ollama (11434)
Cliente -> fastapi-vllm   (puerto 8002) -> ai-runtime-vllm   (8000)
```

- **Misma API para ambos**: `fastapi-ollama` y `fastapi-vllm` corren
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
| `docker-compose.ollama.yml` | `fastapi-ollama` + `ollama` (imagen `latest`, CPU) |
| `docker-compose.ollama.gpu.yml` | Override opcional: agrega GPU NVIDIA a `ollama` (usar junto al archivo anterior) |
| `docker-compose.vllm.yml` | `fastapi-vllm` + `vllm` (imagen `latest`, requiere GPU NVIDIA) |
| `1-install.sh` | Instalador completo: Docker + NVIDIA Container Toolkit + despliegue del backend |
| `2-setup-nvidia.sh` | Solo NVIDIA Container Toolkit (requerido para vLLM y para el override GPU de Ollama) |
| `3-deploy.sh` | Solo despliegue interactivo (asume Docker y NVIDIA ya instalados) |
| `run_vllm.sh` | Lanza un vLLM suelto con `docker run` (fuera de compose), para pruebas rapidas |
| `ai-runtime/` | Codigo fuente de la API (FastAPI) e `install-native.sh` para desplegarla sin Docker (systemd) |

## Instalacion rapida

```bash
./1-install.sh
```

Instala Docker + NVIDIA Container Toolkit (si hay GPU), elige backend (Ollama o
vLLM), pide los parametros necesarios, genera `ai-runtime/.env` con un
`CHATBOT_AI_BEARER_TOKEN` aleatorio, y levanta el stack correspondiente.

Si Docker y NVIDIA Container Toolkit ya estan instalados, podes usar
directamente `./3-deploy.sh`.

Para tener ambos backends corriendo, ejecuta `./3-deploy.sh` dos veces (una
por cada opcion) — son stacks independientes, no hay conflicto entre ellos.

El instalador detecta la VRAM de la primera GPU NVIDIA y la RAM del sistema. A
partir de esos datos propone defaults que siempre se pueden sobrescribir:

| Hardware | Agente vLLM | Contexto | Agente Ollama |
|---|---|---|---|
| NVIDIA 12 GB+ | `Qwen3-8B-AWQ` + KV FP8 | 24k | `qwen3-opencode:4b` |
| NVIDIA 10-11 GB | `Qwen3-8B-AWQ` + KV FP8 | 12k | `qwen3-opencode:4b` |
| NVIDIA 8-9 GB | `Qwen3-4B-Instruct-2507-AWQ-4bit` + KV FP8 | 12k | `qwen3-opencode:4b` |
| NVIDIA menor a 8 GB | `Qwen3-4B-Instruct-2507-AWQ-4bit` + KV FP8 | 8k | Segun VRAM/RAM |
| Sin NVIDIA, RAM 12 GB+ | No disponible | — | `qwen3-opencode:4b` |
| Sin NVIDIA, RAM menor a 12 GB | No disponible | — | `qwen3-opencode:1.7b` |

Esto permite reutilizar el mismo repositorio en instalaciones distintas sin
editar los archivos Compose. Ollama prioriza deliberadamente modelos pequenos:
4B para equipos con al menos 12 GB de RAM y 1.7B para equipos mas limitados.
Modelos como `qwen3-coder:30b` quedan como opcion manual y nunca se descargan
automaticamente.

### Manual (sin los scripts de deploy)

```bash
# Ollama (CPU)
docker compose -f docker-compose.ollama.yml up -d --build

# Ollama con GPU NVIDIA (override opcional)
docker compose -f docker-compose.ollama.yml -f docker-compose.ollama.gpu.yml up -d --build

# vLLM (siempre requiere GPU NVIDIA)
VLLM_MODEL=cyankiwi/Qwen3-4B-Instruct-2507-AWQ-4bit VLLM_TOOL_CALL_PARSER=hermes docker compose -f docker-compose.vllm.yml up -d --build
```

## Gestion de modelos

### Diferencias clave: Ollama vs vLLM

| Caracteristica | Ollama | vLLM |
|---|---|---|
| Cuantizacion | Automatica (GGUF, Q4_K_M) | Manual (modelos pre-cuantizados AWQ/GPTQ o BF16/FP16) |
| GPU minima | Cualquiera (incluye fallback CPU) | Requiere NVIDIA (solo GPU) |
| Modelos simultaneos | Multiples en un contenedor | Un modelo por contenedor |
| Formato de pesos | GGUF (descarga automatica) | HuggingFace safetensors |
| Velocidad | Buena | Excelente (optimizado para serving) |
| Memoria modelo 7B | ~4.7 GB (Q4_K_M) | ~14 GB (BF16, sin cuantizar) |
| Cambiar de modelo | Instantaneo (`ollama pull/rm`) | Requiere recrear contenedor |
| Ideal para | Desarrollo local, prototipado, VRAM limitada | Produccion, alta carga, tool calling |

### Cuando usar cada uno

**Usa Ollama (puerto 8001)** si:
- Tienes 8 GB de VRAM o menos y necesitas modelos 7B+
- Queres probar varios modelos sin reiniciar contenedores
- Necesitas fallback a CPU/RAM; para tool calling usa `qwen3-opencode:4b`
- El modelo se beneficia de cuantizacion GGUF

**Usa vLLM (puerto 8002)** si:
- Necesitas maxima velocidad de inferencia
- Usas tool calling / function calling (OpenAI API)
- Tenes suficiente VRAM para el modelo en BF16/FP16
- Queres servir un modelo en produccion con alta concurrencia

### Ollama (GPU + CPU)

Ollama detecta automaticamente si hay GPU NVIDIA y la usa. Si no hay GPU
o no cabe el modelo, usa CPU con los 64 GB de RAM. Un solo contenedor
sirve multiples modelos a la vez. No se toca ningun archivo.

```bash
# Listar modelos disponibles
docker exec ai-runtime-ollama ollama list

# Descargar modelos (elige automaticamente la cuantizacion optima)
docker exec ai-runtime-ollama ollama pull qwen3:4b              # Agente liviano (~2.5 GB)
docker exec ai-runtime-ollama ollama pull qwen2.5-coder:7b    # Código (~4.7 GB, cabe en 8 GB VRAM)
docker exec ai-runtime-ollama ollama pull llama3.2:1b          # Ligero (~1.3 GB)
docker exec ai-runtime-ollama ollama pull deepseek-r1:1.5b     # Razonamiento (~1.1 GB)
docker exec ai-runtime-ollama ollama pull codestral:22b        # Código avanzado (~13 GB, CPU con 64 GB RAM)
docker exec ai-runtime-ollama ollama pull nomic-embed-text     # Embeddings para RAG (~274 MB)

# Eliminar modelos
docker exec ai-runtime-ollama ollama rm llama3.2:1b

# Ver uso de VRAM en tiempo real
docker exec ai-runtime-ollama ollama ps

# Seguir el log en vivo (carga de modelo, requests, errores)
docker compose -f docker-compose.ollama.yml logs -f ollama
docker logs -f ai-runtime-ollama
```

**Modelos recomendados para 8 GB VRAM + 64 GB RAM:**

| Proposito | Modelo | Memoria | Backend |
|---|---|---|---|
| Agente con herramientas | `qwen3-opencode:4b` | ~2.5 GB | GPU/CPU |
| Codigo (recomendado) | `qwen2.5-coder:7b` | ~4.7 GB | GPU |
| General/Chat | `llama3.1:8b` | ~4.9 GB | GPU |
| Razonamiento | `deepseek-r1:8b` | ~4.9 GB | GPU |
| Codigo avanzado | `codestral:22b` | ~13 GB | CPU (usa RAM) |
| Embeddings (RAG) | `nomic-embed-text` | ~274 MB | GPU/CPU |

`qwen3-opencode:4b` se crea desde `Modelfile.qwen-opencode` sobre
`qwen3:4b`, aumentando el contexto a 12k. Es la opcion recomendada para
OpenCode porque emite llamadas estructuradas que Ollama expone como
`tool_calls`. `qwen2.5-coder:7b` genera mejor codigo aislado, pero en este
entorno devolvio las llamadas como texto JSON y no permite que el agente las
ejecute de forma fiable.

### vLLM (solo GPU)

Cada contenedor ejecuta **un unico modelo** en GPU. Los pesos quedan
en el volumen `chatbot_vllm_hf_cache`. No se pierden al cambiar de modelo.

#### Elegir modelo

El modelo se controla con la variable `VLLM_MODEL`. Si no se define, usa el
default del `docker-compose.vllm.yml`
(`cyankiwi/Qwen3-4B-Instruct-2507-AWQ-4bit`, optimizado para agentes en GPU de 8 GB).

```bash
# Cambiar al modelo deseado (recrea el contenedor, pesos cacheados)
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=Qwen/Qwen2.5-Coder-7B-Instruct-AWQ docker compose -f docker-compose.vllm.yml up -d --build
```

#### Modelos que caben en 8 GB VRAM con vLLM

vLLM usa BF16 por defecto (~2 bytes/param). Para que un modelo quepa en
8 GB, necesitas usar versiones cuantizadas (AWQ, GPTQ, FP8) o modelos
pequenos (4B o menos).

| Modelo | Precision | Peso aprox | Cabe en 8 GB? |
|---|---|---|---|
| `cyankiwi/Qwen3-4B-Instruct-2507-AWQ-4bit` (default del compose) | AWQ (INT4) | ~3 GB | Si, con contexto de 12k |
| `Qwen/Qwen2.5-3B-Instruct` | BF16 | ~6 GB | Si, holgado |
| `Qwen/Qwen2.5-Coder-7B-Instruct-AWQ` | AWQ (INT4) | ~4 GB | Si, holgado |
| `Qwen/Qwen2.5-7B-Instruct` | BF16 | ~14 GB | No, requiere +14 GB (ver AWQ) |
| `Qwen/Qwen2.5-Coder-7B-Instruct` | BF16 | ~14 GB | No (ver modelo AWQ) |

**Modelos recomendados por proposito (equivalente vLLM de la tabla de Ollama):**

| Proposito | Ollama (equivalente) | `VLLM_MODEL` | Memoria aprox | Cabe en 8 GB? |
|---|---|---|---|---|
| Agente con herramientas (default) | `qwen3:8b` | `cyankiwi/Qwen3-4B-Instruct-2507-AWQ-4bit` | ~3 GB | Si, con contexto de 12k |
| Codigo (recomendado) | `qwen2.5-coder:7b` | `Qwen/Qwen2.5-Coder-7B-Instruct-AWQ` | ~4 GB | Si, holgado |
| General/Chat | `llama3.1:8b` | `Qwen/Qwen2.5-7B-Instruct-AWQ` | ~4-5 GB | Si |
| Razonamiento | `deepseek-r1:8b` | `casperhansen/deepseek-r1-distill-qwen-7b-awq` | ~4-5 GB | Si |
| Codigo avanzado | `codestral:22b` (CPU) | Sin equivalente viable en 8 GB de VRAM | ~12-13 GB (AWQ) | No |
| Embeddings (RAG) | `nomic-embed-text` | Usar Ollama via `OLLAMA_BASE_URL` (ver seccion Seguridad/env) | — | — |

Notas:
- `cyankiwi/Qwen3-4B-Instruct-2507-AWQ-4bit` es el default porque genera `tool_calls` estructurados
  con `VLLM_TOOL_CALL_PARSER=hermes`. Esto permite que agentes como OpenCode
  creen y editen archivos en vez de limitarse a explicar los pasos.
- `Qwen/Qwen2.5-Coder-7B-Instruct-AWQ` ofrece mejor calidad de codigo por
  respuesta, pero con seleccion automatica puede devolver la llamada de
  herramienta como texto/XML. Usalo para chat o generacion de codigo, no como
  default de un agente autonomo.
- Estos dos repositorios usan una plantilla `<tool_call>` con argumentos JSON,
  compatible con `hermes`. El parser `qwen3_xml` corresponde a otra variante
  XML de Qwen3 y deja las llamadas de este modelo como texto normal.
- Para Llama en vez de Qwen en "General/Chat": `hugging-quants/Meta-Llama-3.1-8B-Instruct-AWQ-INT4` (~5 GB).
- `casperhansen/deepseek-r1-distill-qwen-7b-awq` es una cuantizacion AWQ comunitaria (DeepSeek no publica un AWQ oficial); la version BF16 sin cuantizar (`deepseek-ai/DeepSeek-R1-Distill-Qwen-7B`) pesa ~14 GB y no entra en 8 GB.
- vLLM no tiene fallback a CPU/RAM como Ollama (es GPU o nada), por eso no hay equivalente de `codestral:22b` en este setup.
- Embeddings: vLLM soporta modo `--task embed`, pero como el stack ya esta preparado para usar Ollama via `OLLAMA_BASE_URL=http://host.docker.internal:11434`, no hace falta duplicarlo en vLLM salvo que quieras independencia total de Ollama.

#### Modelos recomendados para GPU con 24 GB VRAM (ej. RTX 5090)

Con 24 GB hay margen para modelos 32B en AWQ o modelos 7B/14B sin cuantizar
(BF16), lo que da mejor calidad de respuesta y/o contexto mucho mas largo.

| Proposito | `VLLM_MODEL` | Precision | Memoria aprox | Cabe en 24 GB? |
|---|---|---|---|---|
| Texto/analisis (maxima calidad) | `Qwen/Qwen2.5-32B-Instruct-AWQ` | AWQ (INT4) | ~20 GB | Si, justo |
| Texto/analisis (sin cuantizar, mas contexto libre) | `Qwen/Qwen2.5-7B-Instruct` | BF16 | ~14 GB | Si, deja ~10 GB libres |
| Razonamiento (maxima calidad) | `unsloth/DeepSeek-R1-Distill-Qwen-32B-AWQ` | AWQ (INT4) | ~20 GB | Si, justo |
| Codigo (maxima calidad) | `Qwen/Qwen2.5-Coder-32B-Instruct-AWQ` | AWQ (INT4) | ~20 GB | Si, justo |
| Codigo (sin cuantizar, mas contexto libre) | `Qwen/Qwen2.5-Coder-7B-Instruct` | BF16 | ~14 GB | Si, deja ~10 GB libres |
| Embeddings (RAG) | `BAAI/bge-m3` (vLLM `--task embed`) | BF16 | ~2 GB | Si, se puede correr junto a otro modelo |

Notas:
- Los modelos de 32B en AWQ dejan poco margen (~4 GB) para `--max-model-len` y
  KV cache; si necesitas contexto largo (>8k tokens) o mas concurrencia
  (`--max-num-seqs`), preferi las opciones BF16 de 7B, que dejan ~10 GB libres.
- Con 24 GB ya es viable correr **dos modelos vLLM a la vez** (ver
  "Agregar un segundo modelo vLLM" mas abajo), por ejemplo un 7B BF16 de
  texto/codigo junto con `BAAI/bge-m3` para embeddings, sin depender de Ollama.
- Ningun modelo 70B (ej. Llama 3.3 70B) entra en 24 GB ni siquiera en AWQ
  (~40 GB); para esos rangos hace falta 48 GB+ de VRAM.
- `unsloth/DeepSeek-R1-Distill-Qwen-32B-AWQ` es una cuantizacion comunitaria
  (DeepSeek no publica AWQ oficial de este modelo).

#### Cambiar de modelo segun necesidad

Cambiar de modelo siempre sigue el mismo patron: bajar el contenedor y
volver a levantarlo con `VLLM_MODEL` apuntando al nuevo modelo (los pesos
ya descargados quedan cacheados en el volumen `chatbot_vllm_hf_cache`, asi
que un modelo ya usado antes vuelve a arrancar rapido).

```bash
# Patron general
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=<org/modelo> docker compose -f docker-compose.vllm.yml up -d --build
```

**GPU 8 GB VRAM:**

```bash
# Agente con herramientas (default; recomendado para OpenCode)
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=cyankiwi/Qwen3-4B-Instruct-2507-AWQ-4bit VLLM_TOOL_CALL_PARSER=hermes VLLM_KV_CACHE_DTYPE=fp8 docker compose -f docker-compose.vllm.yml up -d --build

# Codigo (recomendado)
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=Qwen/Qwen2.5-Coder-7B-Instruct-AWQ VLLM_TOOL_CALL_PARSER=hermes docker compose -f docker-compose.vllm.yml up -d --build

# General/Chat/analisis de texto
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=Qwen/Qwen2.5-7B-Instruct-AWQ docker compose -f docker-compose.vllm.yml up -d --build

# Razonamiento
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=casperhansen/deepseek-r1-distill-qwen-7b-awq docker compose -f docker-compose.vllm.yml up -d --build

# Liviano / mucho contexto y concurrencia
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=Qwen/Qwen2.5-3B-Instruct docker compose -f docker-compose.vllm.yml up -d --build
```

**GPU 24 GB VRAM (ej. RTX 5090):**

```bash
# Texto/analisis, maxima calidad
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=Qwen/Qwen2.5-32B-Instruct-AWQ docker compose -f docker-compose.vllm.yml up -d --build

# Texto/analisis, sin cuantizar (mas contexto/concurrencia libre)
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=Qwen/Qwen2.5-7B-Instruct docker compose -f docker-compose.vllm.yml up -d --build

# Razonamiento, maxima calidad
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=unsloth/DeepSeek-R1-Distill-Qwen-32B-AWQ docker compose -f docker-compose.vllm.yml up -d --build

# Codigo, maxima calidad
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=Qwen/Qwen2.5-Coder-32B-Instruct-AWQ docker compose -f docker-compose.vllm.yml up -d --build

# Codigo, sin cuantizar (mas contexto/concurrencia libre)
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=Qwen/Qwen2.5-Coder-7B-Instruct docker compose -f docker-compose.vllm.yml up -d --build

# Embeddings (requiere overridear el comando del servicio para --task embed)
docker compose -f docker-compose.vllm.yml down
VLLM_MODEL=BAAI/bge-m3 VLLM_EXTRA_ARGS="--task embed" docker compose -f docker-compose.vllm.yml up -d --build
```

Si un modelo no arranca por falta de VRAM (OOM al cargar), bajale el
contexto y/o la concurrencia antes de cambiar de modelo:

```bash
VLLM_MODEL=<org/modelo> VLLM_MAX_MODEL_LEN=4096 VLLM_MAX_NUM_SEQS=1 VLLM_GPU_MEM_UTIL=0.90 \
  docker compose -f docker-compose.vllm.yml up -d --build
```

#### Ver logs (seguimiento de la carga del modelo)

Despues de cambiar de modelo, segui el log en vivo para confirmar que
termino de cargar (o para ver el error si no arranca):

```bash
# Log en vivo del motor vLLM (descarga de pesos, carga en VRAM, errores CUDA/OOM)
docker compose -f docker-compose.vllm.yml logs -f vllm

# Log en vivo de la API (fastapi-vllm)
docker compose -f docker-compose.vllm.yml logs -f fastapi-vllm

# Ambos servicios a la vez
docker compose -f docker-compose.vllm.yml logs -f

# Ultimas N lineas sin seguir en vivo
docker compose -f docker-compose.vllm.yml logs --tail=200 vllm

# Alternativa usando el nombre del contenedor directamente
docker logs -f ai-runtime-vllm
```

El modelo termino de cargar cuando ves `Application startup complete` (o
`Uvicorn running on...`) en el log de `vllm`. Si en cambio ves
`CUDA out of memory` o el contenedor se reinicia solo (`docker compose ps`
lo muestra en loop de restart), bajale `VLLM_MAX_MODEL_LEN` /
`VLLM_MAX_NUM_SEQS` / `VLLM_GPU_MEM_UTIL` como en el ejemplo anterior.

#### Agregar un segundo modelo vLLM

Para correr dos modelos vLLM a la vez (requiere suficiente VRAM para ambos),
copia el bloque del servicio `vllm` en `docker-compose.vllm.yml`
(instrucciones detalladas en los comentarios del archivo).

```bash
# Variables para el segundo modelo
VLLM2_MODEL=Qwen/Qwen2.5-Coder-7B-Instruct-AWQ
VLLM2_PORT=8010

# Agregar en fastapi-vllm:
# VLLM_EXTRA_BASE_URLS=http://vllm-2:8000/v1
```

#### Limpiar cache de modelos vLLM

```bash
# Ver que modelos estan cacheados
docker exec ai-runtime-vllm ls /root/.cache/huggingface/hub/

# Borrar todo el cache (requiere recrear contenedor despues)
docker compose -f docker-compose.vllm.yml down -v
```

### Alternar entre backends (Ollama y vLLM) sin perder datos

Los pesos descargados persisten en los volumenes Docker incluso si tiras
los contenedores. Solo se borran con `docker compose down -v`.

```bash
# Alternar entre Ollama y vLLM segun lo que necesites:
# - Ollama: puerto 8001 (chatbot-fastapi-ollama)
# - vLLM:  puerto 8002 (chatbot-fastapi-vllm)
```

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
Ollama; `VLLM_MODEL`, `VLLM_TOOL_CALL_PARSER`, `VLLM_PORT`, `VLLM_MAX_MODEL_LEN`,
`VLLM_KV_CACHE_DTYPE`, `VLLM_MAX_NUM_SEQS`, `VLLM_GPU_MEM_UTIL`, `VLLM_EXTRA_ARGS`,
`CHATBOT_AI_VLLM_PORT` para el de vLLM. `3-deploy.sh` las pide de forma
interactiva.

## Endpoints de la API

- `GET /health` — estado basico (publico)
- `GET /health/deep` — estado detallado incluyendo backend y ChromaDB (requiere bearer token)
- `GET /models` / `GET /v1/models` — modelos disponibles en el backend activo
- `POST /analyze` — chat/completion (requiere bearer token)
- `GET /rag/collections`, `POST /rag/upsert`, `POST /rag/query` — RAG sobre ChromaDB (requiere bearer token)

Ver `ai-runtime/reverse-proxy.md` para exponerla detras de Nginx con TLS.
