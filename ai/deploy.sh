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

DEFAULT_OLLAMA_MODELS=("llama3.2:1b" "qwen2.5-coder:1.5b" "deepseek-r1:1.5b")
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
        if docker run --rm --gpus all nvidia/cuda:12.6-base nvidia-smi >/dev/null 2>&1; then
            echo "nvidia"
            return
        fi
    fi
    echo "none"
}

generate_api_key() {
    openssl rand -hex 32
}

create_env_file() {
    local provider="$1"
    local vllm_model="${2:-Qwen/Qwen3-7B}"
    local app_port="${3:-8001}"
    local bearer_token="${4:-}"

    if [ -f "$ENV_FILE" ]; then
        if ! ask_yes_no ".env file already exists. Overwrite?" "n"; then
            info "Keeping existing .env file."
            return
        fi
    fi

    if [ -z "$bearer_token" ]; then
        bearer_token="$(generate_api_key)"
    fi

    local vllm_url="http://127.0.0.1:8000/v1"
    local ollama_url="http://127.0.0.1:11434"
    local embedding_provider="ollama"

    if [ "$provider" = "vllm" ]; then
        embedding_provider="ollama"
        warn "Using Ollama for embeddings with vLLM provider."
        warn "Make sure ollama service is also running or configure EMBEDDING_PROVIDER."
    fi

    cat > "$ENV_FILE" <<EOF
CHATBOT_AI_HOST=0.0.0.0
CHATBOT_AI_PORT=$app_port
CHATBOT_AI_PROVIDER=$provider
CHATBOT_AI_BEARER_TOKEN=$bearer_token
OLLAMA_BASE_URL=$ollama_url
VLLM_BASE_URL=$vllm_url
EMBEDDING_PROVIDER=$embedding_provider
REQUEST_TIMEOUT=90
EMBEDDING_MODEL=$DEFAULT_EMBEDDING_MODEL
CHROMA_PERSIST_DIR=/opt/chatbot-ai-runtime/data/chroma
EOF

    info "Generated .env with provider=$provider"
    info "Bearer token: $bearer_token"
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

pull_ollama_models() {
    local models=()
    local models_input=""

    if ! docker ps --format '{{.Names}}' | grep -q "ollama-server"; then
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
        docker exec ollama-server ollama pull "$model" || warn "Could not pull $model"
    done
}

build_and_start() {
    local profile="$1"
    local compose_args=("--profile" "$profile")

    info "Building AI Runtime image..."
    $DOCKER_COMPOSE -f "$SCRIPT_DIR/docker-compose.yml" build ai-runtime

    info "Starting services with profile: $profile"
    $DOCKER_COMPOSE -f "$SCRIPT_DIR/docker-compose.yml" "${compose_args[@]}" up -d

    info "Waiting for AI Runtime to be ready..."
    local attempts=30
    local app_port="${CHATBOT_AI_PORT:-8001}"
    for _ in $(seq 1 $attempts); do
        if curl -fs "http://127.0.0.1:$app_port/health" >/dev/null 2>&1; then
            info "AI Runtime is ready on port $app_port"
            return 0
        fi
        sleep 2
    done

    warn "AI Runtime may still be starting. Check logs with: docker logs chatbot-ai-runtime"
}

show_summary() {
    local provider="$1"
    local app_port="${CHATBOT_AI_PORT:-8001}"
    local bearer_token=""
    local app_host="127.0.0.1"

    if [ -f "$ENV_FILE" ]; then
        bearer_token="$(grep -oP 'CHATBOT_AI_BEARER_TOKEN=\K.*' "$ENV_FILE" || echo "")"
    fi

    title "Deployment Complete"

    echo "AI Runtime:    http://$app_host:$app_port"
    echo "Provider:      $provider"
    echo "API Key:       $bearer_token"
    echo ""
    echo "Health checks:"
    echo "  curl http://$app_host:$app_port/health"
    echo "  curl -H 'Authorization: Bearer $bearer_token' http://$app_host:$app_port/health/deep"
    echo ""
    echo "Analyze test:"
    printf '%s\n' "  curl -X POST http://$app_host:$app_port/analyze \\"
    printf '%s\n' "    -H 'Authorization: Bearer $bearer_token' \\"
    printf '%s\n' "    -H 'Content-Type: application/json' \\"
    if [ "$provider" = "vllm" ]; then
        printf '%s\n' "    -d '{\"model\":\"${VLLM_MODEL:-Qwen/Qwen3-7B}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply only: ok\"}]}'"
    else
        printf '%s\n' "    -d '{\"model\":\"llama3.2:1b\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply only: ok\"}]}'"
    fi
    echo ""
    echo "Frappe configuration:"
    echo "  Model Provider          = Internal AI API"
    echo "  Internal AI API Base URL = http://$app_host:$app_port"
    echo "  Internal AI API Key      = $bearer_token"
    echo "  Internal AI Model        = ${VLLM_MODEL:-llama3.2:1b}"
    echo ""
    echo "Logs: docker logs -f chatbot-ai-runtime"
    echo "Stop:  $DOCKER_COMPOSE -f $SCRIPT_DIR/docker-compose.yml down"
}

main() {
    local gpu=""
    local provider=""

    title "Chatbot AI Runtime - Docker Deployment"

    check_docker

    gpu="$(check_gpu)"
    if [ "$gpu" = "nvidia" ]; then
        info "NVIDIA GPU detected and available in Docker."
    else
        info "No NVIDIA GPU available in Docker. vLLM will not work."
        info "Use Ollama provider for CPU-only or AMD GPU setups."
    fi

    echo ""
    echo "Choose inference provider:"
    echo "  1) ollama - Ollama (CPU/GPU, easiest setup)"
    if [ "$gpu" = "nvidia" ]; then
        echo "  2) vllm   - vLLM (NVIDIA GPU required, best performance)"
        echo "  3) full   - Both vLLM + Ollama"
    fi
    read -r -p "Select [1]: " provider_choice
    provider_choice="${provider_choice:-1}"

    case "$provider_choice" in
        1) provider="ollama"; profile="ollama" ;;
        2)
            if [ "$gpu" != "nvidia" ]; then
                err "vLLM requires NVIDIA GPU. No GPU detected in Docker."
                exit 1
            fi
            provider="vllm"; profile="vllm"
            ;;
        3)
            if [ "$gpu" != "nvidia" ]; then
                err "Full stack requires NVIDIA GPU. No GPU detected in Docker."
                exit 1
            fi
            provider="vllm"; profile="full"
            ;;
        *) err "Invalid choice"; exit 1 ;;
    esac

    info "Selected provider: $provider (profile: $profile)"

    if [ "$provider" = "vllm" ] || [ "$profile" = "full" ]; then
        read -r -p "vLLM HuggingFace model [Qwen/Qwen3-7B]: " vllm_model
        vllm_model="${vllm_model:-Qwen/Qwen3-7B}"
        export VLLM_MODEL="$vllm_model"

        if [[ "$vllm_model" == *"AWQ"* ]] || [[ "$vllm_model" == *"awq"* ]]; then
            export VLLM_EXTRA_ARGS="--quantization awq"
        else
            export VLLM_EXTRA_ARGS=""
        fi

        read -r -p "HuggingFace cache dir [~/.cache/huggingface]: " hf_cache
        hf_cache="${hf_cache:-$HOME/.cache/huggingface}"
        hf_cache="${hf_cache/#\~/$HOME}"
        export HF_CACHE_DIR="$hf_cache"

        read -r -p "vLLM max model length [2048]: " max_len
        export VLLM_MAX_MODEL_LEN="${max_len:-2048}"

        read -r -p "vLLM max concurrent sequences [2]: " max_seqs
        export VLLM_MAX_NUM_SEQS="${max_seqs:-2}"

        read -r -p "vLLM GPU memory utilization [0.88]: " gpu_mem
        export VLLM_GPU_MEM_UTIL="${gpu_mem:-0.88}"
    fi

    if [ "$profile" = "ollama" ] || [ "$profile" = "full" ]; then
        read -r -p "Ollama host port [11434]: " ollama_port
        export OLLAMA_PORT="${ollama_port:-11434}"
    fi

    read -r -p "AI Runtime host port [8001]: " app_port
    export CHATBOT_AI_PORT="${app_port:-8001}"

    local bearer_token="$(generate_api_key)"
    create_env_file "$provider" "${VLLM_MODEL:-Qwen/Qwen3-7B}" "${app_port:-8001}" "$bearer_token"

    build_and_start "$profile"

    if [ "$profile" = "ollama" ] || [ "$profile" = "full" ]; then
        echo ""
        if ask_yes_no "Pull Ollama models now?" "y"; then
            pull_ollama_models
        fi
    fi

    show_summary "$provider"
}

main "$@"
