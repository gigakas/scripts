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
OLLAMA_AGENT_BASE_MODEL="qwen3:4b"
OLLAMA_AGENT_MODEL="qwen3-opencode:4b"
OLLAMA_AGENT_CONTEXT=12288
VLLM_DEFAULT_MODEL="cyankiwi/Qwen3-4B-Instruct-2507-AWQ-4bit"
VLLM_DEFAULT_MAX_LEN=12288
VLLM_DEFAULT_KV_DTYPE="fp8"

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo -e "\n${CYAN}=== $* ===${NC}\n"; }

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        err "Docker no esta instalado. Corre 1-install.sh primero."
        exit 1
    fi

    # Detectar si docker necesita sudo (usuario fuera del grupo docker)
    if docker info >/dev/null 2>&1; then
        DOCKER="docker"
    elif sudo docker info >/dev/null 2>&1; then
        DOCKER="sudo docker"
        warn "Usando 'sudo docker'. Para evitarlo, cerra sesion y volve a entrar"
        warn "  (el grupo 'docker' necesita recargarse)."
    else
        err "El daemon de Docker no responde. Inicialo con: sudo systemctl start docker"
        exit 1
    fi

    if $DOCKER compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="$DOCKER compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE="$DOCKER-compose"
    else
        err "Docker Compose no encontrado. Instala docker-compose-plugin."
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

    ram_mb="$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)"

    if [ "$gpu" = "nvidia" ]; then
        vram_mb="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null \
            | awk 'NR == 1 {print int($1)}')"
        vram_mb="${vram_mb:-0}"
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

    info "Perfil de hardware: ${vram_mb} MB VRAM, ${ram_mb} MB RAM"
    info "Agente Ollama recomendado: $OLLAMA_AGENT_MODEL ($OLLAMA_AGENT_CONTEXT contexto)"
    if [ "$gpu" = "nvidia" ]; then
        info "Agente vLLM recomendado: $VLLM_DEFAULT_MODEL ($VLLM_DEFAULT_MAX_LEN contexto, KV $VLLM_DEFAULT_KV_DTYPE)"
    fi
}

generate_api_key() {
    openssl rand -hex 32
}

save_token_info() {
    local token="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    cat > "$TOKEN_FILE" <<EOF
# API Bearer Token — generado $timestamp
# Usar en requests: Authorization: Bearer <token>
$token
EOF
    chmod 600 "$TOKEN_FILE"
    info "Token guardado en $TOKEN_FILE"
}

regenerate_token() {
    if [ ! -f "$ENV_FILE" ]; then
        warn "No existe .env. Desplega un backend primero."
        return 1
    fi

    if ! ask_yes_no "¿Generar un nuevo token de API? Esto invalidara el token actual." "n"; then
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
        info "Recreando chatbot-fastapi-ollama con el nuevo token..."
        $DOCKER_COMPOSE -f "$SCRIPT_DIR/docker-compose.ollama.yml" up -d --force-recreate fastapi-ollama 2>/dev/null || true
    fi
    if $DOCKER ps --format '{{.Names}}' | grep -q "chatbot-fastapi-vllm"; then
        info "Recreando chatbot-fastapi-vllm con el nuevo token..."
        $DOCKER_COMPOSE -f "$SCRIPT_DIR/docker-compose.vllm.yml" up -d --force-recreate fastapi-vllm 2>/dev/null || true
    fi

    echo ""
    info "Token regenerado y contenedores recreados con la nueva key."
}

ask_yes_no() {
    local prompt="$1"
    local default_value="${2:-y}"
    local suffix="[Y/n]"

    if [ "$default_value" = "n" ]; then
        suffix="[y/N]"
    fi

    read -r -p "$prompt $suffix " answer
    answer="${answer:-$default_value}"

    case "${answer,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

create_env_file() {
    local bearer_token="$1"

    if [ -f "$ENV_FILE" ]; then
        if ! ask_yes_no "El archivo .env ya existe. ¿Sobrescribir?" "n"; then
            info "Conservando .env existente."
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

    info ".env generado"
    save_token_info "$bearer_token"
}

wait_for_health() {
    local label="$1"
    local port="$2"
    local timeout="${3:-60}"
    local attempts=$(( timeout / 2 ))

    info "Esperando a que $label este listo en puerto $port (timeout: ${timeout}s)..."
    for _ in $(seq 1 $attempts); do
        if curl -fs "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
            info "$label listo en puerto $port"
            return 0
        fi
        sleep 2
    done

    warn "$label no respondio en ${timeout}s. Puede estar aun iniciando."
    warn "Revisa los logs: docker logs -f <container>"
}

manage_ollama_models() {
    if ! $DOCKER ps --format '{{.Names}}' | grep -q "ai-runtime-ollama"; then
        warn "El contenedor de Ollama no esta corriendo."
        return
    fi

    # ---- Pull inicial ----
    local models=()
    local models_input

    echo ""
    info "Modelos por defecto: ${DEFAULT_OLLAMA_MODELS[*]}"
    info "Modelo de embedding: $DEFAULT_EMBEDDING_MODEL"
    read -r -p "Modelos a descargar, separados por espacio [Enter = defaults + embedding]: " models_input

    if [ -z "$models_input" ]; then
        models=("${DEFAULT_OLLAMA_MODELS[@]}" "$DEFAULT_EMBEDDING_MODEL")
    else
        read -r -a models <<< "$models_input"
    fi

    for model in "${models[@]}"; do
        info "Descargando $model ..."
        $DOCKER exec ai-runtime-ollama ollama pull "$model" || warn "No se pudo descargar $model"
    done

    _create_opencode_model

    # ---- Menu de gestion ----
    while true; do
        echo ""
        echo "Gestion de modelos Ollama:"
        echo "  l) Listar modelos"
        echo "  a) Agregar modelo (pull)"
        echo "  e) Eliminar modelo (rm)"
        echo "  q) Terminar"
        read -r -p "Elegir [q]: " action
        action="${action:-q}"

        case "${action,,}" in
            l|list|listar)
                info "Modelos instalados:"
                $DOCKER exec ai-runtime-ollama ollama list
                ;;
            a|add|agregar)
                read -r -p "Nombre del modelo a descargar: " model_name
                if [ -n "$model_name" ]; then
                    $DOCKER exec ai-runtime-ollama ollama pull "$model_name" \
                        && info "$model_name descargado." \
                        || warn "No se pudo descargar $model_name"
                fi
                ;;
            e|rm|eliminar)
                read -r -p "Nombre del modelo a eliminar: " model_name
                if [ -n "$model_name" ]; then
                    $DOCKER exec ai-runtime-ollama ollama rm "$model_name" \
                        && info "$model_name eliminado." \
                        || warn "No se pudo eliminar $model_name"
                fi
                ;;
            q|quit|salir|"")
                break
                ;;
            *)
                warn "Opcion invalida."
                ;;
        esac
    done
}

_create_opencode_model() {
    if $DOCKER exec ai-runtime-ollama ollama show "$OLLAMA_AGENT_BASE_MODEL" >/dev/null 2>&1; then
        info "Creando $OLLAMA_AGENT_MODEL con contexto $OLLAMA_AGENT_CONTEXT ..."
        printf 'FROM %s\nPARAMETER num_ctx %s\n' "$OLLAMA_AGENT_BASE_MODEL" "$OLLAMA_AGENT_CONTEXT" \
            | $DOCKER exec -i ai-runtime-ollama ollama create "$OLLAMA_AGENT_MODEL" -f /dev/stdin \
            || warn "No se pudo crear $OLLAMA_AGENT_MODEL"
    fi
}

deploy_ollama() {
    local bearer_token="$1"
    local gpu="$2"
    local compose_args=(-f "$SCRIPT_DIR/docker-compose.ollama.yml")

    if [ "$gpu" = "nvidia" ]; then
        if ask_yes_no "Se detecto GPU NVIDIA. ¿Usarla tambien para Ollama?" "y"; then
            compose_args+=(-f "$SCRIPT_DIR/docker-compose.ollama.gpu.yml")
        fi
    fi

    read -r -p "Puerto backend Ollama [11434]: " ollama_port
    export OLLAMA_PORT="${ollama_port:-11434}"

    read -r -p "Puerto host AI Runtime (Ollama) [8001]: " app_port
    export CHATBOT_AI_OLLAMA_PORT="${app_port:-8001}"

    create_env_file "$bearer_token"

    info "Construyendo y levantando stack Ollama..."
    $DOCKER_COMPOSE "${compose_args[@]}" build
    $DOCKER_COMPOSE "${compose_args[@]}" up -d

    wait_for_health "AI Runtime (Ollama)" "$CHATBOT_AI_OLLAMA_PORT" 120

    echo ""
    if ask_yes_no "¿Descargar modelos Ollama ahora?" "y"; then
        manage_ollama_models
    fi

    title "Despliegue completado"
    echo "API Key: $bearer_token"
    echo ""
    echo "AI Runtime (Ollama): http://127.0.0.1:$CHATBOT_AI_OLLAMA_PORT  (contenedor: chatbot-fastapi-ollama)"
    echo "  curl http://127.0.0.1:$CHATBOT_AI_OLLAMA_PORT/health"
    printf '%s\n' "  curl -X POST http://127.0.0.1:$CHATBOT_AI_OLLAMA_PORT/analyze -H 'Authorization: Bearer $bearer_token' -H 'Content-Type: application/json' -d '{\"model\":\"llama3.2:1b\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply only: ok\"}]}'"
    echo ""
    echo "Logs:  $DOCKER logs -f chatbot-fastapi-ollama"
    echo "Stop:  $DOCKER_COMPOSE ${compose_args[*]} down"
}

deploy_vllm() {
    local bearer_token="$1"
    local compose_file="$SCRIPT_DIR/docker-compose.vllm.yml"

    read -r -p "Modelo HuggingFace para vLLM [$VLLM_DEFAULT_MODEL]: " vllm_model
    export VLLM_MODEL="${vllm_model:-$VLLM_DEFAULT_MODEL}"

    read -r -p "Tool call parser [hermes]: " tool_call_parser
    export VLLM_TOOL_CALL_PARSER="${tool_call_parser:-hermes}"

    export VLLM_EXTRA_ARGS=""

    read -r -p "Max model length [$VLLM_DEFAULT_MAX_LEN]: " max_len
    export VLLM_MAX_MODEL_LEN="${max_len:-$VLLM_DEFAULT_MAX_LEN}"

    read -r -p "KV cache dtype [$VLLM_DEFAULT_KV_DTYPE]: " kv_cache_dtype
    export VLLM_KV_CACHE_DTYPE="${kv_cache_dtype:-$VLLM_DEFAULT_KV_DTYPE}"

    read -r -p "Max concurrent sequences [1]: " max_seqs
    export VLLM_MAX_NUM_SEQS="${max_seqs:-1}"

    read -r -p "GPU memory utilization [0.95]: " gpu_mem
    export VLLM_GPU_MEM_UTIL="${gpu_mem:-0.95}"

    read -r -p "Puerto backend vLLM [8000]: " vllm_port
    export VLLM_PORT="${vllm_port:-8000}"

    read -r -p "Puerto host AI Runtime (vLLM) [8002]: " app_port
    export CHATBOT_AI_VLLM_PORT="${app_port:-8002}"

    create_env_file "$bearer_token"

    info "Construyendo y levantando stack vLLM..."
    $DOCKER_COMPOSE -f "$compose_file" build
    $DOCKER_COMPOSE -f "$compose_file" up -d

    # vLLM puede tardar varios minutos en descargar y cargar el modelo
    wait_for_health "AI Runtime (vLLM)" "$CHATBOT_AI_VLLM_PORT" 600

    title "Despliegue completado"
    echo "API Key: $bearer_token"
    echo ""
    echo "AI Runtime (vLLM): http://127.0.0.1:$CHATBOT_AI_VLLM_PORT  (contenedor: chatbot-fastapi-vllm)"
    echo "  curl http://127.0.0.1:$CHATBOT_AI_VLLM_PORT/health"
    printf '%s\n' "  curl -X POST http://127.0.0.1:$CHATBOT_AI_VLLM_PORT/analyze -H 'Authorization: Bearer $bearer_token' -H 'Content-Type: application/json' -d '{\"model\":\"$VLLM_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply only: ok\"}]}'"
    echo ""
    echo "Logs:  $DOCKER logs -f chatbot-fastapi-vllm"
    echo "Stop:  $DOCKER_COMPOSE -f $compose_file down"
}

main() {
    title "Chatbot AI Runtime — Despliegue Docker"

    if [ ! -d "$RUNTIME_DIR" ]; then
        err "No se encontro la carpeta ai-runtime/ en $SCRIPT_DIR."
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
        info "Backends ya desplegados:"
        $ollama_running && echo "  - Ollama  (puerto: chatbot-fastapi-ollama)"
        $vllm_running   && echo "  - vLLM    (puerto: chatbot-fastapi-vllm)"
    fi

    local gpu
    gpu="$(check_gpu)"
    if [ "$gpu" = "nvidia" ]; then
        info "GPU NVIDIA detectada y accesible en Docker."
        gpu_info
    else
        info "Sin GPU NVIDIA en Docker. vLLM no esta disponible."
    fi
    configure_hardware_profile "$gpu"

    echo ""
    if $ollama_running && $vllm_running; then
        echo "Ambos backends ya estan desplegados."
        echo "  0) Gestionar modelos de Ollama"
        echo "  1) Re-desplegar Ollama (down + up)"
        if [ "$gpu" = "nvidia" ]; then
            echo "  2) Re-desplegar vLLM (down + up)"
        fi
        echo "  t) Regenerar token de API"
        echo "  q) Salir"
        read -r -p "Elegir [0]: " choice
        choice="${choice:-0}"
    elif $ollama_running; then
        echo "Ollama ya desplegado. ¿Que queres hacer?"
        echo "  1) Re-desplegar Ollama (down + up)"
        if [ "$gpu" = "nvidia" ]; then
            echo "  2) Agregar vLLM al stack existente"
        fi
        echo "  0) Gestionar modelos de Ollama"
        echo "  t) Regenerar token de API"
        echo "  q) Salir"
        read -r -p "Elegir [0]: " choice
        choice="${choice:-0}"
    elif $vllm_running; then
        echo "vLLM ya desplegado. ¿Que queres hacer?"
        echo "  1) Agregar Ollama al stack existente"
        if [ "$gpu" = "nvidia" ]; then
            echo "  2) Re-desplegar vLLM (down + up)"
        fi
        echo "  0) Gestionar modelos de Ollama"
        echo "  t) Regenerar token de API"
        echo "  q) Salir"
        read -r -p "Elegir [1]: " choice
        choice="${choice:-1}"
    else
        echo "¿Que backend queres desplegar?"
        echo "  1) Ollama — CPU/GPU, multiples modelos en un contenedor"
        if [ "$gpu" = "nvidia" ]; then
            echo "  2) vLLM  — Requiere GPU NVIDIA, un modelo por contenedor"
            echo "  3) Ambos — Ollama + vLLM (stacks independientes)"
        fi
        echo "  0) Solo gestionar modelos (sin desplegar)"
        read -r -p "Elegir [1]: " choice
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
            info "Ajustando OLLAMA_BASE_URL para que vLLM use Ollama como motor de embeddings..."
            $DOCKER restart chatbot-fastapi-vllm >/dev/null 2>&1 || true
        fi
    fi

    case "$choice" in
        1)
            deploy_ollama "$bearer_token" "$gpu"
            ;;
        2)
            if [ "$gpu" != "nvidia" ]; then
                err "vLLM requiere GPU NVIDIA. No se detecto GPU en Docker."
                exit 1
            fi
            deploy_vllm "$bearer_token"
            ;;
        3)
            if [ "$gpu" != "nvidia" ]; then
                err "vLLM requiere GPU NVIDIA. No se detecto GPU en Docker."
                exit 1
            fi
            deploy_ollama "$bearer_token" "$gpu"
            echo ""
            info "Ahora desplegando vLLM (mismo bearer token)..."
            if [ -f "$ENV_FILE" ]; then
                sed -i 's|OLLAMA_BASE_URL=http://127.0.0.1:11434|OLLAMA_BASE_URL=http://host.docker.internal:11434|' "$ENV_FILE"
            fi
            deploy_vllm "$bearer_token"
            ;;
        *)
            err "Opcion invalida."
            exit 1
            ;;
    esac

    echo ""
    info "Ejecuta este script de nuevo para agregar, redeployar o gestionar modelos."

    # ---- Gestion de modelos post-deploy ----
    if $DOCKER ps --format '{{.Names}}' 2>/dev/null | grep -q "ai-runtime-ollama"; then
        if ask_yes_no "¿Gestionar modelos de Ollama (listar/agregar/eliminar)?" "n"; then
            manage_ollama_models
        fi
    fi
    if $DOCKER ps --format '{{.Names}}' 2>/dev/null | grep -q "ai-runtime-vllm"; then
        echo ""
        info "Para cambiar el modelo de vLLM:"
        echo "  $DOCKER_COMPOSE -f $SCRIPT_DIR/docker-compose.vllm.yml down"
        echo "  VLLM_MODEL=<nuevo-modelo> $DOCKER_COMPOSE -f $SCRIPT_DIR/docker-compose.vllm.yml up -d --build"
        echo "  Los pesos quedan cacheados en el volumen chatbot_vllm_hf_cache."
    fi
}

main "$@"
