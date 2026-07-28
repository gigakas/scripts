#!/usr/bin/env bash
set -euo pipefail

DEFAULT_MODELS=("llama3.2:1b" "qwen2.5-coder:1.5b" "deepseek-r1:1.5b")
APP_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR_DEFAULT="/opt/chatbot-ai-runtime"
SERVICE_NAME_DEFAULT="chatbot-ai-runtime"
APP_HOST_DEFAULT="127.0.0.1"
APP_PORT_DEFAULT="8001"
OLLAMA_BASE_URL_DEFAULT="http://127.0.0.1:11434"
EMBEDDING_MODEL_DEFAULT="nomic-embed-text"

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		echo "Run with sudo: sudo bash install.sh"
		exit 1
	fi
}

ask_yes_no() {
	local prompt="$1"
	local default_value="${2:-y}"
	local answer=""
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

detect_gpu() {
	if command -v nvidia-smi >/dev/null 2>&1 || lspci 2>/dev/null | grep -qi "nvidia"; then
		echo "nvidia"
		return
	fi

	if lspci 2>/dev/null | grep -Eiq "amd|ati"; then
		echo "amd"
		return
	fi

	echo "cpu"
}

install_system_dependencies() {
	echo "[ai-runtime] Installing base dependencies..."
	apt-get update
	apt-get install -y curl ca-certificates gnupg lsb-release pciutils python3 python3-venv python3-pip rsync openssl
}

install_gpu_dependencies() {
	local gpu_type="$1"

	case "$gpu_type" in
		nvidia)
			echo "[ai-runtime] NVIDIA GPU detected."
			if command -v nvidia-smi >/dev/null 2>&1; then
				echo "[ai-runtime] NVIDIA driver is already available."
			elif ask_yes_no "Install recommended NVIDIA drivers with ubuntu-drivers?" "y"; then
				apt-get install -y ubuntu-drivers-common
				ubuntu-drivers autoinstall || echo "[ai-runtime] Warning: install/reboot NVIDIA drivers manually if Ollama does not use the GPU."
			else
				echo "[ai-runtime] Skipping NVIDIA driver installation."
			fi
			;;
		amd)
			echo "[ai-runtime] AMD GPU detected."
			if ask_yes_no "Install ROCm libraries available from APT?" "y"; then
				apt-get install -y rocm-opencl-runtime rocm-hip-runtime || echo "[ai-runtime] Warning: ROCm may require AMD repositories depending on your distro/GPU."
			else
				echo "[ai-runtime] Skipping ROCm installation."
			fi
			;;
		cpu)
			echo "[ai-runtime] No compatible GPU detected. CPU mode will be used."
			;;
	esac
}

install_ollama() {
	if command -v ollama >/dev/null 2>&1; then
		echo "[ai-runtime] Ollama is already installed."
	else
		echo "[ai-runtime] Installing Ollama..."
		curl -fsSL https://ollama.com/install.sh | sh
		hash -r
	fi

	systemctl daemon-reload || true
	systemctl enable ollama >/dev/null 2>&1 || true
	systemctl start ollama || systemctl restart ollama || true
	wait_for_ollama
}

wait_for_ollama() {
	local attempts=30
	local delay=2

	echo "[ai-runtime] Waiting for Ollama API..."

	for _ in $(seq 1 "$attempts"); do
		if curl -fsS "$OLLAMA_BASE_URL_DEFAULT/api/tags" >/dev/null 2>&1; then
			echo "[ai-runtime] Ollama API is ready."
			return 0
		fi

		sleep "$delay"
	done

	echo "[ai-runtime] Ollama API did not become ready in time."
	echo "[ai-runtime] Check status with: sudo systemctl status ollama"
	echo "[ai-runtime] Check logs with: sudo journalctl -u ollama -f"
	exit 1
}

pull_models() {
	local models_input=""
	local models=()

	echo "Model notes:"
	echo "  llama3.2:1b           General-purpose lightweight chat model. Good default for low-resource servers and fast support answers."
	echo "  qwen2.5-coder:1.5b    Code-focused lightweight model. Useful for technical support, scripts, JSON, logs, and structured outputs."
	echo "  deepseek-r1:1.5b       Reasoning-focused lightweight model. Useful when answers need step-by-step analysis or document reasoning."
	echo ""
	echo "Default models: ${DEFAULT_MODELS[*]}"
	read -r -p "Models to pull, separated by spaces [Enter = default]: " models_input

	if [ -z "$models_input" ]; then
		models=("${DEFAULT_MODELS[@]}")
	else
		read -r -a models <<< "$models_input"
	fi

	for model in "${models[@]}"; do
		echo "[ai-runtime] Pulling model: $model"
		ollama pull "$model" || echo "[ai-runtime] Warning: could not pull $model"
	done
}

create_api_key() {
	openssl rand -hex 32
}

sed_escape() {
	printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

deploy_runtime() {
	local app_dir="$APP_DIR_DEFAULT"
	local service_name="$SERVICE_NAME_DEFAULT"
	local app_user="${SUDO_USER:-frappe}"
	local app_group=""
	local host="$APP_HOST_DEFAULT"
	local port="$APP_PORT_DEFAULT"
	local ollama_base_url="$OLLAMA_BASE_URL_DEFAULT"
	local embedding_model="$EMBEDDING_MODEL_DEFAULT"
	local chroma_dir=""
	local api_key=""
	local escaped_app_dir=""
	local escaped_env_file=""
	local escaped_exec_start=""

	read -r -p "Runtime target directory [$app_dir]: " app_dir
	app_dir="${app_dir:-$APP_DIR_DEFAULT}"

	read -r -p "Service user [$app_user]: " app_user
	app_user="${app_user:-${SUDO_USER:-frappe}}"

	if ! id "$app_user" >/dev/null 2>&1; then
		echo "User does not exist: $app_user"
		exit 1
	fi

	app_group="$(id -gn "$app_user")"

	read -r -p "Runtime host [$host]: " host
	host="${host:-$APP_HOST_DEFAULT}"

	read -r -p "Runtime port [$port]: " port
	port="${port:-$APP_PORT_DEFAULT}"

	read -r -p "Ollama base URL [$ollama_base_url]: " ollama_base_url
	ollama_base_url="${ollama_base_url:-$OLLAMA_BASE_URL_DEFAULT}"

	read -r -p "Embedding model [$embedding_model]: " embedding_model
	embedding_model="${embedding_model:-$EMBEDDING_MODEL_DEFAULT}"

	chroma_dir="$app_dir/data/chroma"
	read -r -p "Chroma persist directory [$chroma_dir]: " chroma_dir
	chroma_dir="${chroma_dir:-$app_dir/data/chroma}"

	read -r -p "systemd service name [$service_name]: " service_name
	service_name="${service_name:-$SERVICE_NAME_DEFAULT}"

	echo "[ai-runtime] Copying files to $app_dir..."
	mkdir -p "$app_dir"
	if [ "$APP_SOURCE_DIR" != "$app_dir" ]; then
		rsync -a --delete --exclude '.venv' --exclude '.env' --exclude 'data' "$APP_SOURCE_DIR/" "$app_dir/"
	fi

	api_key="$(create_api_key)"
	mkdir -p "$chroma_dir"
	cat > "$app_dir/.env" <<EOF
CHATBOT_AI_HOST=$host
CHATBOT_AI_PORT=$port
CHATBOT_AI_PROVIDER=ollama
CHATBOT_AI_BEARER_TOKEN=$api_key
OLLAMA_BASE_URL=$ollama_base_url
REQUEST_TIMEOUT=90
EMBEDDING_MODEL=$embedding_model
CHROMA_PERSIST_DIR=$chroma_dir
EOF

	python3 -m venv "$app_dir/.venv"
	"$app_dir/.venv/bin/python" -m pip install --upgrade pip
	"$app_dir/.venv/bin/python" -m pip install -r "$app_dir/requirements.txt"

	cp "$app_dir/chatbot-ai-runtime.service.example" "/etc/systemd/system/$service_name.service"
	escaped_app_dir="$(sed_escape "$app_dir")"
	escaped_env_file="$(sed_escape "$app_dir/.env")"
	escaped_exec_start="$(sed_escape "$app_dir/.venv/bin/uvicorn app.main:app --host \${CHATBOT_AI_HOST} --port \${CHATBOT_AI_PORT}")"
	sed -i "s|^WorkingDirectory=.*|WorkingDirectory=$escaped_app_dir|" "/etc/systemd/system/$service_name.service"
	sed -i "s|^EnvironmentFile=.*|EnvironmentFile=$escaped_env_file|" "/etc/systemd/system/$service_name.service"
	sed -i "s|^ExecStart=.*|ExecStart=$escaped_exec_start|" "/etc/systemd/system/$service_name.service"
	sed -i "s|^User=.*|User=$app_user|" "/etc/systemd/system/$service_name.service"

	chown -R "$app_user:$app_group" "$app_dir"
	systemctl daemon-reload
	systemctl enable "$service_name"
	systemctl restart "$service_name"

	echo ""
	echo "AI runtime installed."
	echo "API key: $api_key"
	echo "App dir: $app_dir"
	echo "Chroma dir: $chroma_dir"
	echo ""
	echo "Endpoint tests:"
	echo "curl http://$host:$port/health"
	echo "curl -H 'Authorization: Bearer $api_key' http://$host:$port/health/deep"
	echo "curl -H 'Authorization: Bearer $api_key' http://$host:$port/rag/collections"
	printf '%s\n' "curl -X POST http://$host:$port/analyze \\
  -H 'Authorization: Bearer $api_key' \\
  -H 'Content-Type: application/json' \\
  -d '{\"model\":\"qwen3:1.7b\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply only: ok\"}],\"options\":{\"temperature\":0}}'"
}

main() {
	local gpu_type=""

	require_root
	install_system_dependencies
	gpu_type="$(detect_gpu)"
	install_gpu_dependencies "$gpu_type"
	install_ollama
	pull_models
	deploy_runtime
}

main "$@"
