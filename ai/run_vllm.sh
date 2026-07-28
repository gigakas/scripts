#!/bin/bash

# Comprobar si se pasó el argumento del modelo
if [ -z "$1" ]; then
    echo "❌ Error: Debes especificar un modelo de Hugging Face."
    echo "Uso: $0 <nombre-del-modelo>"
    exit 1
fi

MODELO="$1"
QUANT_ARG=""

if [[ "$MODELO" == *"AWQ"* || "$MODELO" == *"awq"* ]]; then
    QUANT_ARG="--quantization awq"
fi

echo "🚀 Ajustando ventana de contexto a 2048 tokens..."
echo "------------------------------------------------------------"

docker run -it --name vllm_server --rm \
    --gpus all \
    -v ~/.cache/huggingface:/root/.cache/huggingface \
    -p 8000:8000 \
    --ipc=host \
    --entrypoint python3 \
    vllm/vllm-openai:latest \
    -m vllm.entrypoints.openai.api_server \
    --model "$MODELO" \
    $QUANT_ARG \
    --max-model-len 2048 \
    --max-num-seqs 2 \
    --gpu-memory-utilization 0.88 \
    --enforce-eager \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_xml
