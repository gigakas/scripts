#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/ai-runtime"
ENV_FILE="$RUNTIME_DIR/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DEFAULT_OLLAMA_MODELS=("deepseek-r1:1.5b" "llama3.2:1b" "gemma4:e2b-it-qat")
DEFAULT_EMBEDDING_MODEL="nomic-embed-text"

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
title() { echo -e "\n${CYAN}=== $* ===${NC}\n"; }

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "$1 is not installed. Install it first."
        exit 1
    fi
}

check_docker() {
    require_cmd docker
    if ! docker info >/dev/null 2>&1; then
        err "Docker daemon is not running. Start it with: sudo systemctl start docker"
        exit 1
    fi
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker-compose"
    else
        err "Docker Compose plugin not found. Install docker-compose-plugin or docker-compose."
        exit 1
    fi
}

check_gpu() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        if docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
            echo "nvidia"
            return
        fi
    fi
    echo "none"
}

gpu_info() {
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null \
        | awk -F', ' '{printf "  - %s (%s VRAM)\n", $1, $2}'
}

generate_api_key() {
    openssl rand -hex 32
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
        *) return 1 ;;
    esac
}

create_env_file() {
    local bearer_token="$1"

    if [ -f "$ENV_FILE" ]; then
        if ! ask_yes_no ".env file already exists. Overwrite?" "n"; then
            info "Keeping existing .env file."
            return
        fi
    fi

    # docker-compose.ollama.yml y docker-compose.vllm.yml sobreescriben
    # CHATBOT_AI_PROVIDER/OLLAMA_BASE_URL/VLLM_BASE_URL/etc por su cuenta, asi
    # que aqui solo quedan los valores compartidos entre ambos.
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

    info "Generated .env"
    info "Bearer token: $bearer_token"
}

wait_for_health() {
    local label="$1"
    local port="$2"
    local attempts=30

    info "Waiting for $label to be ready on port $port..."
    for _ in $(seq 1 $attempts); do
        if curl -fs "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
            info "$label is ready on port $port"
            return 0
        fi
        sleep 2
    done

    warn "$label may still be starting. Check logs with: docker logs -f <container>"
}

pull_ollama_models() {
    local models=()
    local models_input=""

    if ! docker ps --format '{{.Names}}' | grep -q "ai-runtime-ollama"; then
        warn "Ollama container is not running. Skipping model pull."
        return
    fi

    info "Default models: ${DEFAULT_OLLAMA_MODELS[*]}"
    info "Embedding model: $DEFAULT_EMBEDDING_MODEL"
    read -r -p "Models to pull, space-separated [Enter = defaults + embedding]: " models_input

    if [ -z "$models_input" ]; then
        models=("${DEFAULT_OLLAMA_MODELS[@]}" "$DEFAULT_EMBEDDING_MODEL")
    else
        read -r -a models <<< "$models_input"
    fi

    for model in "${models[@]}"; do
        info "Pulling $model ..."
        docker exec ai-runtime-ollama ollama pull "$model" || warn "Could not pull $model"
    done
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

    read -r -p "Ollama backend port [11434]: " ollama_port
    export OLLAMA_PORT="${ollama_port:-11434}"

    read -r -p "AI Runtime (Ollama) host port [8001]: " app_port
    export CHATBOT_AI_OLLAMA_PORT="${app_port:-8001}"

    create_env_file "$bearer_token"

    info "Building and starting Ollama stack..."
    $DOCKER_COMPOSE "${compose_args[@]}" build
    $DOCKER_COMPOSE "${compose_args[@]}" up -d

    wait_for_health "AI Runtime (Ollama)" "$CHATBOT_AI_OLLAMA_PORT"

    echo ""
    if ask_yes_no "Pull Ollama models now?" "y"; then
        pull_ollama_models
    fi

    title "Deployment Complete"
    echo "API Key: $bearer_token"
    echo ""
    echo "AI Runtime (Ollama): http://127.0.0.1:$CHATBOT_AI_OLLAMA_PORT  (container: chatbot-fastapi-ollama)"
    echo "  curl http://127.0.0.1:$CHATBOT_AI_OLLAMA_PORT/health"
    printf '%s\n' "  curl -X POST http://127.0.0.1:$CHATBOT_AI_OLLAMA_PORT/analyze -H 'Authorization: Bearer $bearer_token' -H 'Content-Type: application/json' -d '{\"model\":\"llama3.2:1b\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply only: ok\"}]}'"
    echo ""
    echo "Logs:  docker logs -f chatbot-fastapi-ollama"
    echo "Stop:  $DOCKER_COMPOSE ${compose_args[*]} down"
}

deploy_vllm() {
    local bearer_token="$1"
    local compose_file="$SCRIPT_DIR/docker-compose.vllm.yml"

    read -r -p "vLLM HuggingFace model [Qwen/Qwen3-7B]: " vllm_model
    export VLLM_MODEL="${vllm_model:-Qwen/Qwen3-7B}"

    if [[ "$VLLM_MODEL" == *"AWQ"* ]] || [[ "$VLLM_MODEL" == *"awq"* ]]; then
        export VLLM_EXTRA_ARGS="--quantization awq"
    else
        export VLLM_EXTRA_ARGS=""
    fi

    read -r -p "vLLM max model length [2048]: " max_len
    export VLLM_MAX_MODEL_LEN="${max_len:-2048}"

    read -r -p "vLLM max concurrent sequences [2]: " max_seqs
    export VLLM_MAX_NUM_SEQS="${max_seqs:-2}"

    read -r -p "vLLM GPU memory utilization [0.88]: " gpu_mem
    export VLLM_GPU_MEM_UTIL="${gpu_mem:-0.88}"

    read -r -p "vLLM backend port [8000]: " vllm_port
    export VLLM_PORT="${vllm_port:-8000}"

    read -r -p "AI Runtime (vLLM) host port [8002]: " app_port
    export CHATBOT_AI_VLLM_PORT="${app_port:-8002}"

    create_env_file "$bearer_token"

    info "Building and starting vLLM stack..."
    $DOCKER_COMPOSE -f "$compose_file" build
    $DOCKER_COMPOSE -f "$compose_file" up -d

    wait_for_health "AI Runtime (vLLM)" "$CHATBOT_AI_VLLM_PORT"

    title "Deployment Complete"
    echo "API Key: $bearer_token"
    echo ""
    echo "AI Runtime (vLLM): http://127.0.0.1:$CHATBOT_AI_VLLM_PORT  (container: chatbot-fastapi-vllm)"
    echo "  curl http://127.0.0.1:$CHATBOT_AI_VLLM_PORT/health"
    printf '%s\n' "  curl -X POST http://127.0.0.1:$CHATBOT_AI_VLLM_PORT/analyze -H 'Authorization: Bearer $bearer_token' -H 'Content-Type: application/json' -d '{\"model\":\"$VLLM_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply only: ok\"}]}'"
    echo ""
    echo "vLLM y Ollama guardan sus modelos por separado (no se comparten cachés)."
    echo "Para agregar un segundo modelo vLLM, ve la receta en docker-compose.vllm.yml."
    echo ""
    echo "Logs:  docker logs -f chatbot-fastapi-vllm"
    echo "Stop:  $DOCKER_COMPOSE -f $compose_file down"
}

main() {
    title "Chatbot AI Runtime - Docker Deployment"

    check_docker

    local gpu
    gpu="$(check_gpu)"
    if [ "$gpu" = "nvidia" ]; then
        info "NVIDIA GPU detected and available in Docker."
        gpu_info
    else
        info "No NVIDIA GPU available in Docker. vLLM will not work."
    fi

    echo ""
    echo "Que backend quieres instalar?"
    echo "  1) ollama - Ollama (CPU/GPU, varios modelos en un mismo contenedor)"
    if [ "$gpu" = "nvidia" ]; then
        echo "  2) vllm   - vLLM (requiere GPU NVIDIA, un modelo por contenedor)"
    fi
    read -r -p "Select [1]: " choice
    choice="${choice:-1}"

    local bearer_token
    bearer_token="$(generate_api_key)"

    case "$choice" in
        1)
            deploy_ollama "$bearer_token" "$gpu"
            ;;
        2)
            if [ "$gpu" != "nvidia" ]; then
                err "vLLM requires NVIDIA GPU. No GPU detected in Docker."
                exit 1
            fi
            deploy_vllm "$bearer_token"
            ;;
        *)
            err "Invalid choice"
            exit 1
            ;;
    esac

    echo ""
    info "Para instalar el otro backend, vuelve a correr este script."
}

main "$@"
