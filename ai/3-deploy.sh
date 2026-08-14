#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/ai-runtime"
ENV_FILE="$RUNTIME_DIR/.env"
TOKEN_FILE="$SCRIPT_DIR/.api-token"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DEFAULT_OLLAMA_MODELS=()
DEFAULT_EMBEDDING_MODEL="nomic-embed-text"
OLLAMA_DEFAULT_CHAT_MODEL="llama3.2:1b"
OLLAMA_AGENT_BASE_MODEL="qwen3:4b"
OLLAMA_AGENT_MODEL="qwen3-opencode:4b"
OLLAMA_AGENT_CONTEXT=12288
VLLM_DEFAULT_MODEL="cyankiwi/Qwen3-4B-Instruct-2507-AWQ-4bit"
VLLM_DEFAULT_TOOL_CALL_PARSER="hermes"
VLLM_DEFAULT_MAX_LEN=12288
VLLM_DEFAULT_KV_DTYPE="fp8"
VLLM_DEFAULT_MAX_NUM_SEQS=1
VLLM_DEFAULT_GPU_MEM_UTIL="0.95"
RTX_5090_24GB_PROFILE=false
LANGUAGE_CODE="${INSTALLER_LANGUAGE:-}"

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo -e "\n${CYAN}=== $* ===${NC}\n"; }

text() {
    if [ "$LANGUAGE_CODE" = "es" ]; then
        printf '%s' "$1"
    else
        printf '%s' "$2"
    fi
}

choose_language() {
    if [ "$LANGUAGE_CODE" = "es" ] || [ "$LANGUAGE_CODE" = "en" ]; then
        return
    fi

    echo "=============================================="
    echo " Seleccione un idioma / Select a language"
    echo "=============================================="
    echo " 1) Español"
    echo " 2) English"
    while true; do
        read -r -p "Opción / Option [1-2]: " language_option
        case "$language_option" in
            1) LANGUAGE_CODE="es"; return ;;
            2) LANGUAGE_CODE="en"; return ;;
            *) echo "Opción no válida / Invalid option" ;;
        esac
    done
}

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        err "$(text "Docker no está instalado. Ejecuta primero 1-install.sh." "Docker is not installed. Run 1-install.sh first.")"
        exit 1
    fi

    # Detectar si docker necesita sudo (usuario fuera del grupo docker)
    if docker info >/dev/null 2>&1; then
        DOCKER="docker"
    elif sudo docker info >/dev/null 2>&1; then
        DOCKER="sudo docker"
        warn "$(text "Usando 'sudo docker'. Para evitarlo, cierra sesión y vuelve a entrar" "Using 'sudo docker'. To avoid this, log out and back in")"
        warn "$(text "  (es necesario recargar el grupo 'docker')." "  (the 'docker' group needs to be reloaded).")"
    else
        err "$(text "El daemon de Docker no responde. Inícialo con: sudo systemctl start docker" "The Docker daemon is not responding. Start it with: sudo systemctl start docker")"
        exit 1
    fi

    if $DOCKER compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="$DOCKER compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE="$DOCKER-compose"
    else
        err "$(text "No se encontró Docker Compose. Instala docker-compose-plugin." "Docker Compose was not found. Install docker-compose-plugin.")"
        exit 1
    fi
}

check_gpu() {
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo "none"
        return
    fi
    if $DOCKER run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        echo "nvidia"
        return
    fi
    echo "none"
}

gpu_info() {
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null \
        | awk -F', ' '{printf "  - %s (%s VRAM)\n", $1, $2}'
}

configure_hardware_profile() {
    local gpu="$1"
    local vram_mb=0
    local ram_mb
    local gpu_name=""

    ram_mb="$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)"

    if [ "$gpu" = "nvidia" ]; then
        vram_mb="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null \
            | awk 'NR == 1 {print int($1)}')"
        vram_mb="${vram_mb:-0}"
        gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | awk 'NR == 1')"
        if [[ "$gpu_name" == *"RTX 5090"* ]] && [ "$vram_mb" -ge 23000 ]; then
            RTX_5090_24GB_PROFILE=true
        fi
    fi

    if [ "$vram_mb" -ge 12000 ]; then
        VLLM_DEFAULT_MODEL="Qwen/Qwen3-8B-AWQ"
        VLLM_DEFAULT_MAX_LEN=24576
    elif [ "$vram_mb" -ge 10000 ]; then
        VLLM_DEFAULT_MODEL="Qwen/Qwen3-8B-AWQ"
        VLLM_DEFAULT_MAX_LEN=12288
    elif [ "$vram_mb" -ge 7500 ]; then
        VLLM_DEFAULT_MODEL="cyankiwi/Qwen3-4B-Instruct-2507-AWQ-4bit"
        VLLM_DEFAULT_MAX_LEN=12288
    else
        VLLM_DEFAULT_MODEL="cyankiwi/Qwen3-4B-Instruct-2507-AWQ-4bit"
        VLLM_DEFAULT_MAX_LEN=8192
    fi

    if [ "$vram_mb" -ge 4500 ] || [ "$ram_mb" -ge 12000 ]; then
        OLLAMA_AGENT_BASE_MODEL="qwen3:4b"
        OLLAMA_AGENT_MODEL="qwen3-opencode:4b"
        OLLAMA_AGENT_CONTEXT=12288
    else
        OLLAMA_AGENT_BASE_MODEL="qwen3:1.7b"
        OLLAMA_AGENT_MODEL="qwen3-opencode:1.7b"
        OLLAMA_AGENT_CONTEXT=8192
    fi

    DEFAULT_OLLAMA_MODELS=("$OLLAMA_AGENT_BASE_MODEL" "deepseek-r1:1.5b" "llama3.2:1b" "gemma4:e2b-it-qat")

    info "$(text "Perfil de hardware: ${vram_mb} MB VRAM, ${ram_mb} MB RAM" "Hardware profile: ${vram_mb} MB VRAM, ${ram_mb} MB RAM")"
    info "$(text "Agente Ollama recomendado: $OLLAMA_AGENT_MODEL ($OLLAMA_AGENT_CONTEXT de contexto)" "Recommended Ollama agent: $OLLAMA_AGENT_MODEL ($OLLAMA_AGENT_CONTEXT context)")"
    if [ "$gpu" = "nvidia" ]; then
        info "$(text "Agente vLLM recomendado: $VLLM_DEFAULT_MODEL ($VLLM_DEFAULT_MAX_LEN de contexto, KV $VLLM_DEFAULT_KV_DTYPE)" "Recommended vLLM agent: $VLLM_DEFAULT_MODEL ($VLLM_DEFAULT_MAX_LEN context, KV $VLLM_DEFAULT_KV_DTYPE)")"
    fi
}

configure_rtx_5090_24gb_profile() {
    DEFAULT_OLLAMA_MODELS=("devstral-small-2:24b" "qwen3.5:27b" "qwen3-coder:30b")
    DEFAULT_EMBEDDING_MODEL="qwen3-embedding:0.6b"
    OLLAMA_DEFAULT_CHAT_MODEL="devstral-small-2:24b"
    VLLM_DEFAULT_MODEL="cyankiwi/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit"
    VLLM_DEFAULT_TOOL_CALL_PARSER="qwen3_xml"
    VLLM_DEFAULT_MAX_LEN=12288
    VLLM_DEFAULT_KV_DTYPE="fp8"
    VLLM_DEFAULT_MAX_NUM_SEQS=1
    VLLM_DEFAULT_GPU_MEM_UTIL="0.92"

    info "$(text "Perfil RTX 5090 de 24 GB para programación seleccionado." "RTX 5090 24 GB programming profile selected.")"
    info "$(text "Ollama recomendado" "Recommended Ollama"): ${DEFAULT_OLLAMA_MODELS[*]} + $DEFAULT_EMBEDDING_MODEL"
    info "$(text "vLLM recomendado" "Recommended vLLM"): $VLLM_DEFAULT_MODEL ($VLLM_DEFAULT_MAX_LEN $(text "de contexto" "context"), KV $VLLM_DEFAULT_KV_DTYPE)"
    warn "$(text "Ollama y vLLM comparten la GPU; evita usar dos modelos grandes al mismo tiempo." "Ollama and vLLM share the GPU; avoid using two large models at the same time.")"
}

generate_api_key() {
    openssl rand -hex 32
}

save_token_info() {
    local token="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    cat > "$TOKEN_FILE" <<EOF
# API Bearer Token — $(text "generado" "generated") $timestamp
# $(text "Usar en las solicitudes" "Use in requests"): Authorization: Bearer <token>
$token
EOF
    chmod 600 "$TOKEN_FILE"
    info "$(text "Token guardado en $TOKEN_FILE" "Token saved to $TOKEN_FILE")"
}

regenerate_token() {
    if [ ! -f "$ENV_FILE" ]; then
        warn "$(text "No existe .env. Despliega primero un backend." ".env does not exist. Deploy a backend first.")"
        return 1
    fi

    if ! ask_yes_no "$(text "¿Generar un nuevo token de API? Esto invalidará el token actual." "Generate a new API token? This will invalidate the current token.")" "n"; then
        return 1
    fi

    local new_token
    new_token="$(generate_api_key)"

    if grep -q 'CHATBOT_AI_BEARER_TOKEN=' "$ENV_FILE"; then
        sed -i "s|CHATBOT_AI_BEARER_TOKEN=.*|CHATBOT_AI_BEARER_TOKEN=$new_token|" "$ENV_FILE"
    else
        echo "CHATBOT_AI_BEARER_TOKEN=$new_token" >> "$ENV_FILE"
    fi

    save_token_info "$new_token"

    # Recrear contenedores fastapi para que lean el nuevo token del .env
    # docker restart no relee env_file; hay que hacer up -d para recrear
    if $DOCKER ps --format '{{.Names}}' | grep -q "chatbot-fastapi-ollama"; then
        info "$(text "Recreando chatbot-fastapi-ollama con el nuevo token..." "Recreating chatbot-fastapi-ollama with the new token...")"
        $DOCKER_COMPOSE -f "$SCRIPT_DIR/docker-compose.ollama.yml" up -d --force-recreate fastapi-ollama 2>/dev/null || true
    fi
    if $DOCKER ps --format '{{.Names}}' | grep -q "chatbot-fastapi-vllm"; then
        info "$(text "Recreando chatbot-fastapi-vllm con el nuevo token..." "Recreating chatbot-fastapi-vllm with the new token...")"
        $DOCKER_COMPOSE -f "$SCRIPT_DIR/docker-compose.vllm.yml" up -d --force-recreate fastapi-vllm 2>/dev/null || true
    fi

    echo ""
    info "$(text "Token regenerado y contenedores recreados con la nueva clave." "Token regenerated and containers recreated with the new key.")"
}

ask_yes_no() {
    local prompt="$1"
    local default_value="${2:-y}"
    local suffix="[Y/n]"

    if [ "$default_value" = "n" ]; then
        suffix="$(text "[s/N]" "[y/N]")"
    elif [ "$LANGUAGE_CODE" = "es" ]; then
        suffix="[S/n]"
    fi

    read -r -p "$prompt $suffix " answer
    answer="${answer:-$default_value}"

    case "${answer,,}" in
        y|yes|s|si|sí) return 0 ;;
        *)     return 1 ;;
    esac
}

create_env_file() {
    local bearer_token="$1"

    if [ -f "$ENV_FILE" ]; then
        if ! ask_yes_no "$(text "El archivo .env ya existe. ¿Sobrescribirlo?" "The .env file already exists. Overwrite it?")" "n"; then
            info "$(text "Conservando el archivo .env existente." "Keeping the existing .env file.")"
            return
        fi
    fi

    cat > "$ENV_FILE" <<EOF
CHATBOT_AI_HOST=0.0.0.0
CHATBOT_AI_PORT=8001
CHATBOT_AI_PROVIDER=ollama
CHATBOT_AI_BEARER_TOKEN=$bearer_token
OLLAMA_BASE_URL=http://127.0.0.1:11434
VLLM_BASE_URL=http://127.0.0.1:8000/v1
VLLM_EXTRA_BASE_URLS=
EMBEDDING_PROVIDER=ollama
REQUEST_TIMEOUT=90
EMBEDDING_MODEL=$DEFAULT_EMBEDDING_MODEL
CHROMA_PERSIST_DIR=/opt/chatbot-ai-runtime/data/chroma
EOF

    info "$(text ".env generado" ".env generated")"
    save_token_info "$bearer_token"
}

wait_for_health() {
    local label="$1"
    local port="$2"
    local timeout="${3:-60}"
    local attempts=$(( timeout / 2 ))

    info "$(text "Esperando a que $label esté listo en el puerto $port (tiempo límite: ${timeout}s)..." "Waiting for $label on port $port (timeout: ${timeout}s)...")"
    for _ in $(seq 1 $attempts); do
        if curl -fs "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
            info "$(text "$label está listo en el puerto $port" "$label is ready on port $port")"
            return 0
        fi
        sleep 2
    done

    warn "$(text "$label no respondió en ${timeout}s. Es posible que todavía se esté iniciando." "$label did not respond within ${timeout}s. It may still be starting.")"
    warn "$(text "Revisa los logs" "Check the logs"): docker logs -f <container>"
}

manage_ollama_models() {
    if ! $DOCKER ps --format '{{.Names}}' | grep -q "ai-runtime-ollama"; then
        warn "$(text "El contenedor de Ollama no se está ejecutando." "The Ollama container is not running.")"
        return
    fi

    # ---- Pull inicial ----
    local models=()
    local models_input

    echo ""
    info "$(text "Modelos predeterminados" "Default models"): ${DEFAULT_OLLAMA_MODELS[*]}"
    info "$(text "Modelo de embeddings" "Embedding model"): $DEFAULT_EMBEDDING_MODEL"
    read -r -p "$(text "Modelos que se descargarán, separados por espacios [Enter = predeterminados + embeddings]: " "Models to download, separated by spaces [Enter = defaults + embedding]: ")" models_input

    if [ -z "$models_input" ]; then
        models=("${DEFAULT_OLLAMA_MODELS[@]}" "$DEFAULT_EMBEDDING_MODEL")
    else
        read -r -a models <<< "$models_input"
    fi

    for model in "${models[@]}"; do
        info "$(text "Descargando $model..." "Downloading $model...")"
        $DOCKER exec ai-runtime-ollama ollama pull "$model" || warn "$(text "No se pudo descargar $model" "Could not download $model")"
    done

    _create_opencode_model

    # ---- Menu de gestion ----
    while true; do
        echo ""
        echo "$(text "Gestión de modelos de Ollama:" "Ollama model management:")"
        echo "  l) $(text "Listar modelos" "List models")"
        echo "  a) $(text "Agregar modelo (pull)" "Add model (pull)")"
        echo "  e) $(text "Eliminar modelo (rm)" "Remove model (rm)")"
        echo "  q) $(text "Terminar" "Finish")"
        read -r -p "$(text "Elegir" "Choose") [q]: " action
        action="${action:-q}"

        case "${action,,}" in
            l|list|listar)
                info "$(text "Modelos instalados:" "Installed models:")"
                $DOCKER exec ai-runtime-ollama ollama list
                ;;
            a|add|agregar)
                read -r -p "$(text "Nombre del modelo que se descargará: " "Name of the model to download: ")" model_name
                if [ -n "$model_name" ]; then
                    $DOCKER exec ai-runtime-ollama ollama pull "$model_name" \
                        && info "$(text "$model_name descargado." "$model_name downloaded.")" \
                        || warn "$(text "No se pudo descargar $model_name" "Could not download $model_name")"
                fi
                ;;
            e|rm|eliminar)
                read -r -p "$(text "Nombre del modelo que se eliminará: " "Name of the model to remove: ")" model_name
                if [ -n "$model_name" ]; then
                    $DOCKER exec ai-runtime-ollama ollama rm "$model_name" \
                        && info "$(text "$model_name eliminado." "$model_name removed.")" \
                        || warn "$(text "No se pudo eliminar $model_name" "Could not remove $model_name")"
                fi
                ;;
            q|quit|salir|"")
                break
                ;;
            *)
                warn "$(text "Opción no válida." "Invalid option.")"
                ;;
        esac
    done
}

_create_opencode_model() {
    if $DOCKER exec ai-runtime-ollama ollama show "$OLLAMA_AGENT_BASE_MODEL" >/dev/null 2>&1; then
        info "$(text "Creando $OLLAMA_AGENT_MODEL con contexto $OLLAMA_AGENT_CONTEXT..." "Creating $OLLAMA_AGENT_MODEL with context $OLLAMA_AGENT_CONTEXT...")"
        printf 'FROM %s\nPARAMETER num_ctx %s\n' "$OLLAMA_AGENT_BASE_MODEL" "$OLLAMA_AGENT_CONTEXT" \
            | $DOCKER exec -i ai-runtime-ollama ollama create "$OLLAMA_AGENT_MODEL" -f /dev/stdin \
            || warn "$(text "No se pudo crear $OLLAMA_AGENT_MODEL" "Could not create $OLLAMA_AGENT_MODEL")"
    fi
}

deploy_ollama() {
    local bearer_token="$1"
    local gpu="$2"
    local compose_args=(-f "$SCRIPT_DIR/docker-compose.ollama.yml")

    if [ "$gpu" = "nvidia" ]; then
        if ask_yes_no "$(text "Se detectó una GPU NVIDIA. ¿Usarla también para Ollama?" "An NVIDIA GPU was detected. Use it for Ollama too?")" "y"; then
            compose_args+=(-f "$SCRIPT_DIR/docker-compose.ollama.gpu.yml")
        fi
    fi

    read -r -p "$(text "Puerto del backend de Ollama" "Ollama backend port") [11434]: " ollama_port
    export OLLAMA_PORT="${ollama_port:-11434}"

    read -r -p "$(text "Puerto host de AI Runtime (Ollama)" "AI Runtime host port (Ollama)") [8001]: " app_port
    export CHATBOT_AI_OLLAMA_PORT="${app_port:-8001}"

    create_env_file "$bearer_token"

    info "$(text "Construyendo e iniciando el stack de Ollama..." "Building and starting the Ollama stack...")"
    $DOCKER_COMPOSE "${compose_args[@]}" build
    $DOCKER_COMPOSE "${compose_args[@]}" up -d

    wait_for_health "AI Runtime (Ollama)" "$CHATBOT_AI_OLLAMA_PORT" 120

    echo ""
    if ask_yes_no "$(text "¿Descargar modelos de Ollama ahora?" "Download Ollama models now?")" "y"; then
        manage_ollama_models
    fi

    title "$(text "Despliegue completado" "Deployment completed")"
    echo "API Key: $bearer_token"
    echo ""
    echo "AI Runtime (Ollama): http://127.0.0.1:$CHATBOT_AI_OLLAMA_PORT  ($(text "contenedor" "container"): chatbot-fastapi-ollama)"
    echo "  curl http://127.0.0.1:$CHATBOT_AI_OLLAMA_PORT/health"
    printf '%s\n' "  curl -X POST http://127.0.0.1:$CHATBOT_AI_OLLAMA_PORT/analyze -H 'Authorization: Bearer $bearer_token' -H 'Content-Type: application/json' -d '{\"model\":\"$OLLAMA_DEFAULT_CHAT_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply only: ok\"}]}'"
    echo ""
    echo "$(text "Logs" "Logs"):  $DOCKER logs -f chatbot-fastapi-ollama"
    echo "$(text "Detener" "Stop"):  $DOCKER_COMPOSE ${compose_args[*]} down"
}

deploy_vllm() {
    local bearer_token="$1"
    local compose_file="$SCRIPT_DIR/docker-compose.vllm.yml"

    read -r -p "$(text "Modelo de Hugging Face para vLLM" "Hugging Face model for vLLM") [$VLLM_DEFAULT_MODEL]: " vllm_model
    export VLLM_MODEL="${vllm_model:-$VLLM_DEFAULT_MODEL}"

    read -r -p "Tool call parser [$VLLM_DEFAULT_TOOL_CALL_PARSER]: " tool_call_parser
    export VLLM_TOOL_CALL_PARSER="${tool_call_parser:-$VLLM_DEFAULT_TOOL_CALL_PARSER}"

    export VLLM_EXTRA_ARGS=""

    read -r -p "$(text "Longitud máxima del modelo" "Maximum model length") [$VLLM_DEFAULT_MAX_LEN]: " max_len
    export VLLM_MAX_MODEL_LEN="${max_len:-$VLLM_DEFAULT_MAX_LEN}"

    read -r -p "KV cache dtype [$VLLM_DEFAULT_KV_DTYPE]: " kv_cache_dtype
    export VLLM_KV_CACHE_DTYPE="${kv_cache_dtype:-$VLLM_DEFAULT_KV_DTYPE}"

    read -r -p "$(text "Máximo de secuencias simultáneas" "Maximum concurrent sequences") [$VLLM_DEFAULT_MAX_NUM_SEQS]: " max_seqs
    export VLLM_MAX_NUM_SEQS="${max_seqs:-$VLLM_DEFAULT_MAX_NUM_SEQS}"

    read -r -p "$(text "Uso de memoria de la GPU" "GPU memory utilization") [$VLLM_DEFAULT_GPU_MEM_UTIL]: " gpu_mem
    export VLLM_GPU_MEM_UTIL="${gpu_mem:-$VLLM_DEFAULT_GPU_MEM_UTIL}"

    read -r -p "$(text "Puerto del backend de vLLM" "vLLM backend port") [8000]: " vllm_port
    export VLLM_PORT="${vllm_port:-8000}"

    read -r -p "$(text "Puerto host de AI Runtime (vLLM)" "AI Runtime host port (vLLM)") [8002]: " app_port
    export CHATBOT_AI_VLLM_PORT="${app_port:-8002}"

    create_env_file "$bearer_token"

    info "$(text "Construyendo e iniciando el stack de vLLM..." "Building and starting the vLLM stack...")"
    $DOCKER_COMPOSE -f "$compose_file" build
    $DOCKER_COMPOSE -f "$compose_file" up -d

    # vLLM puede tardar varios minutos en descargar y cargar el modelo
    wait_for_health "AI Runtime (vLLM)" "$CHATBOT_AI_VLLM_PORT" 600

    title "$(text "Despliegue completado" "Deployment completed")"
    echo "API Key: $bearer_token"
    echo ""
    echo "AI Runtime (vLLM): http://127.0.0.1:$CHATBOT_AI_VLLM_PORT  ($(text "contenedor" "container"): chatbot-fastapi-vllm)"
    echo "  curl http://127.0.0.1:$CHATBOT_AI_VLLM_PORT/health"
    printf '%s\n' "  curl -X POST http://127.0.0.1:$CHATBOT_AI_VLLM_PORT/analyze -H 'Authorization: Bearer $bearer_token' -H 'Content-Type: application/json' -d '{\"model\":\"$VLLM_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply only: ok\"}]}'"
    echo ""
    echo "$(text "Logs" "Logs"):  $DOCKER logs -f chatbot-fastapi-vllm"
    echo "$(text "Detener" "Stop"):  $DOCKER_COMPOSE -f $compose_file down"
}

main() {
    choose_language
    title "$(text "Chatbot AI Runtime — Despliegue con Docker" "Chatbot AI Runtime — Docker deployment")"

    if [ ! -d "$RUNTIME_DIR" ]; then
        err "$(text "No se encontró el directorio ai-runtime/ en $SCRIPT_DIR." "The ai-runtime/ directory was not found in $SCRIPT_DIR.")"
        exit 1
    fi

    check_docker

    # Detectar backends ya desplegados
    local ollama_running=false
    local vllm_running=false
    if $DOCKER ps --format '{{.Names}}' 2>/dev/null | grep -q "chatbot-fastapi-ollama"; then
        ollama_running=true
    fi
    if $DOCKER ps --format '{{.Names}}' 2>/dev/null | grep -q "chatbot-fastapi-vllm"; then
        vllm_running=true
    fi

    if $ollama_running || $vllm_running; then
        echo ""
        info "$(text "Backends ya desplegados:" "Backends already deployed:")"
        $ollama_running && echo "  - Ollama  ($(text "contenedor" "container"): chatbot-fastapi-ollama)"
        $vllm_running   && echo "  - vLLM    ($(text "contenedor" "container"): chatbot-fastapi-vllm)"
    fi

    local gpu
    gpu="$(check_gpu)"
    if [ "$gpu" = "nvidia" ]; then
        info "$(text "GPU NVIDIA detectada y accesible desde Docker." "NVIDIA GPU detected and accessible from Docker.")"
        gpu_info
    else
        info "$(text "No hay una GPU NVIDIA disponible en Docker. vLLM no está disponible." "No NVIDIA GPU is available in Docker. vLLM is unavailable.")"
    fi
    configure_hardware_profile "$gpu"

    echo ""
    if $ollama_running && $vllm_running; then
        echo "$(text "Ambos backends ya están desplegados." "Both backends are already deployed.")"
        echo "  0) $(text "Gestionar modelos de Ollama" "Manage Ollama models")"
        echo "  1) $(text "Volver a desplegar Ollama (down + up)" "Redeploy Ollama (down + up)")"
        if [ "$gpu" = "nvidia" ]; then
            echo "  2) $(text "Volver a desplegar vLLM (down + up)" "Redeploy vLLM (down + up)")"
        fi
        echo "  t) $(text "Regenerar token de API" "Regenerate API token")"
        echo "  q) $(text "Salir" "Exit")"
        read -r -p "$(text "Elegir" "Choose") [0]: " choice
        choice="${choice:-0}"
    elif $ollama_running; then
        echo "$(text "Ollama ya está desplegado. ¿Qué deseas hacer?" "Ollama is already deployed. What would you like to do?")"
        echo "  1) $(text "Volver a desplegar Ollama (down + up)" "Redeploy Ollama (down + up)")"
        if [ "$gpu" = "nvidia" ]; then
            echo "  2) $(text "Agregar vLLM al stack existente" "Add vLLM to the existing stack")"
        fi
        echo "  0) $(text "Gestionar modelos de Ollama" "Manage Ollama models")"
        echo "  t) $(text "Regenerar token de API" "Regenerate API token")"
        echo "  q) $(text "Salir" "Exit")"
        read -r -p "$(text "Elegir" "Choose") [0]: " choice
        choice="${choice:-0}"
    elif $vllm_running; then
        echo "$(text "vLLM ya está desplegado. ¿Qué deseas hacer?" "vLLM is already deployed. What would you like to do?")"
        echo "  1) $(text "Agregar Ollama al stack existente" "Add Ollama to the existing stack")"
        if [ "$gpu" = "nvidia" ]; then
            echo "  2) $(text "Volver a desplegar vLLM (down + up)" "Redeploy vLLM (down + up)")"
        fi
        echo "  0) $(text "Gestionar modelos de Ollama" "Manage Ollama models")"
        echo "  t) $(text "Regenerar token de API" "Regenerate API token")"
        echo "  q) $(text "Salir" "Exit")"
        read -r -p "$(text "Elegir" "Choose") [1]: " choice
        choice="${choice:-1}"
    else
        echo "$(text "¿Qué backend deseas desplegar?" "Which backend would you like to deploy?")"
        echo "  1) Ollama — $(text "CPU/GPU, varios modelos en un contenedor" "CPU/GPU, multiple models in one container")"
        if [ "$gpu" = "nvidia" ]; then
            echo "  2) vLLM  — $(text "Requiere una GPU NVIDIA, un modelo por contenedor" "Requires an NVIDIA GPU, one model per container")"
            echo "  3) $(text "Ambos" "Both") — Ollama + vLLM ($(text "stacks independientes" "independent stacks"))"
            if $RTX_5090_24GB_PROFILE; then
                echo "  4) RTX 5090 24 GB — $(text "Programación con Ollama + vLLM 30B AWQ" "Programming with Ollama + vLLM 30B AWQ")"
            fi
        fi
        echo "  0) $(text "Solo gestionar modelos (sin desplegar)" "Manage models only (do not deploy)")"
        read -r -p "$(text "Elegir" "Choose") [1]: " choice
        choice="${choice:-1}"
    fi

    # Opcion 0 / q / t no necesitan despliegue
    if [ "$choice" = "0" ]; then
        manage_ollama_models
        exit 0
    fi
    if [ "$choice" = "q" ]; then
        exit 0
    fi
    if [ "$choice" = "t" ]; then
        regenerate_token
        exit 0
    fi

    if [ "$choice" = "4" ]; then
        if ! $RTX_5090_24GB_PROFILE; then
            err "$(text "El perfil RTX 5090 de 24 GB requiere una RTX 5090 con al menos 23 GB de VRAM accesible desde Docker." "The RTX 5090 24 GB profile requires an RTX 5090 with at least 23 GB of VRAM accessible from Docker.")"
            exit 1
        fi
        configure_rtx_5090_24gb_profile
    fi

    # Reusar bearer token del .env si existe, sino generar uno nuevo
    local bearer_token
    if [ -f "$ENV_FILE" ] && grep -q 'CHATBOT_AI_BEARER_TOKEN=' "$ENV_FILE"; then
        bearer_token="$(grep 'CHATBOT_AI_BEARER_TOKEN=' "$ENV_FILE" | cut -d= -f2)"
    else
        bearer_token="$(generate_api_key)"
    fi

    # Si estamos agregando Ollama a un stack vLLM, ajustar OLLAMA_BASE_URL
    if $vllm_running && [ "$choice" = "1" ] && ! $ollama_running; then
        if [ -f "$ENV_FILE" ] && grep -q 'OLLAMA_BASE_URL=http://127.0.0.1:11434' "$ENV_FILE"; then
            sed -i 's|OLLAMA_BASE_URL=http://127.0.0.1:11434|OLLAMA_BASE_URL=http://host.docker.internal:11434|' "$ENV_FILE"
            info "$(text "Ajustando OLLAMA_BASE_URL para que vLLM use Ollama como motor de embeddings..." "Adjusting OLLAMA_BASE_URL so vLLM uses Ollama as the embedding engine...")"
            $DOCKER restart chatbot-fastapi-vllm >/dev/null 2>&1 || true
        fi
    fi

    case "$choice" in
        1)
            deploy_ollama "$bearer_token" "$gpu"
            ;;
        2)
            if [ "$gpu" != "nvidia" ]; then
                err "$(text "vLLM requiere una GPU NVIDIA. No se detectó ninguna GPU en Docker." "vLLM requires an NVIDIA GPU. No GPU was detected in Docker.")"
                exit 1
            fi
            deploy_vllm "$bearer_token"
            ;;
        3)
            if [ "$gpu" != "nvidia" ]; then
                err "$(text "vLLM requiere una GPU NVIDIA. No se detectó ninguna GPU en Docker." "vLLM requires an NVIDIA GPU. No GPU was detected in Docker.")"
                exit 1
            fi
            deploy_ollama "$bearer_token" "$gpu"
            echo ""
            info "$(text "Desplegando ahora vLLM (mismo bearer token)..." "Now deploying vLLM (same bearer token)...")"
            if [ -f "$ENV_FILE" ]; then
                sed -i 's|OLLAMA_BASE_URL=http://127.0.0.1:11434|OLLAMA_BASE_URL=http://host.docker.internal:11434|' "$ENV_FILE"
            fi
            deploy_vllm "$bearer_token"
            ;;
        4)
            deploy_ollama "$bearer_token" "$gpu"
            echo ""
            info "$(text "Desplegando ahora vLLM con el perfil RTX 5090 de 24 GB (mismo bearer token)..." "Now deploying vLLM with the RTX 5090 24 GB profile (same bearer token)...")"
            if [ -f "$ENV_FILE" ]; then
                sed -i 's|OLLAMA_BASE_URL=http://127.0.0.1:11434|OLLAMA_BASE_URL=http://host.docker.internal:11434|' "$ENV_FILE"
            fi
            deploy_vllm "$bearer_token"
            ;;
        *)
            err "$(text "Opción no válida." "Invalid option.")"
            exit 1
            ;;
    esac

    echo ""
    info "$(text "Ejecuta este script nuevamente para agregar, volver a desplegar o gestionar modelos." "Run this script again to add, redeploy, or manage models.")"

    # ---- Gestion de modelos post-deploy ----
    if $DOCKER ps --format '{{.Names}}' 2>/dev/null | grep -q "ai-runtime-ollama"; then
        if ask_yes_no "$(text "¿Gestionar modelos de Ollama (listar/agregar/eliminar)?" "Manage Ollama models (list/add/remove)?")" "n"; then
            manage_ollama_models
        fi
    fi
    if $DOCKER ps --format '{{.Names}}' 2>/dev/null | grep -q "ai-runtime-vllm"; then
        echo ""
        info "$(text "Para cambiar el modelo de vLLM:" "To change the vLLM model:")"
        echo "  $DOCKER_COMPOSE -f $SCRIPT_DIR/docker-compose.vllm.yml down"
        echo "  VLLM_MODEL=<$(text "nuevo-modelo" "new-model")> $DOCKER_COMPOSE -f $SCRIPT_DIR/docker-compose.vllm.yml up -d --build"
        echo "  $(text "Los pesos permanecen en la caché del volumen chatbot_vllm_hf_cache." "Model weights remain cached in the chatbot_vllm_hf_cache volume.")"
    fi
}

main "$@"
