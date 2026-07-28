# Unified AI Runtime

This folder contains the single supported deployment for the separated AI server architecture.

It combines:

- Ollama host bootstrap
- Optional GPU preparation
- FastAPI inference server
- ChromaDB persistence and retrieval endpoints
- `systemd` service installation

## Architecture

```text
Frappe -> AI Runtime -> Ollama / vLLM
                     -> ChromaDB
```

Frappe should keep business rules, users, logs, prompts, and orchestration.
The AI runtime should keep model execution, embeddings, and vector storage.

## Folder Contents

- `install.sh`: unified interactive installer for a clean AI server
- `Dockerfile`: container image for the AI Runtime
- `requirements.txt`: Python dependencies for the runtime
- `.env.example`: environment template
- `chatbot-ai-runtime.service.example`: example `systemd` service
- `app/main.py`: FastAPI app with Ollama/vLLM and ChromaDB endpoints
- `app/settings.py`: environment-based configuration
- `app/schemas.py`: API request and response schemas
- `validate.sh`: validation script for the runtime
- `reverse-proxy.md`: reverse proxy example and security notes

## Endpoints

### `GET /health`

Lightweight server health endpoint.

### `GET /health/deep`

Checks:

- bearer-token authorization when enabled
- Ollama connectivity
- installed Ollama models
- ChromaDB persistence availability

### `POST /analyze`

Primary inference endpoint used by Frappe.

### `GET /rag/collections`

Lists available ChromaDB collections.

### `POST /rag/upsert`

Stores documents in a ChromaDB collection using embeddings generated through Ollama.

### `POST /rag/query`

Runs semantic retrieval against a ChromaDB collection.

## Installation

Run on the target AI server:

```bash
cd ai/ai-runtime
sudo bash install.sh
```

The installer:

- installs base system packages
- detects CPU, NVIDIA, or AMD GPU
- offers GPU package installation when relevant
- installs Ollama if missing
- pulls default chat and embedding models
- copies this runtime to `/opt/chatbot-ai-runtime` by default
- creates `.venv` and installs Python dependencies
- writes `.env` with a generated bearer token
- prepares persistent ChromaDB storage
- installs and starts a `systemd` service

Default runtime paths:

- app dir: `/opt/chatbot-ai-runtime`
- service name: `chatbot-ai-runtime`
- ChromaDB dir: `/opt/chatbot-ai-runtime/data/chroma`

## Frappe Configuration

In `Chatbot Settings` or `Chatbot Analysis Settings`:

- `Model Provider = Internal AI API`
- `Internal AI API Base URL = http://<ai-server>:8001`
- `Internal AI API Key = <generated bearer token>`
- `Internal AI Model = qwen3:1.7b` or another installed model

## Manual Validation

```bash
curl http://127.0.0.1:8001/health
curl -H 'Authorization: Bearer <API_KEY>' http://127.0.0.1:8001/health/deep
curl -H 'Authorization: Bearer <API_KEY>' http://127.0.0.1:8001/rag/collections
```

Or run:

```bash
bash validate.sh http://127.0.0.1:8001
```

## Notes

- The runtime supports Ollama and vLLM for chat inference.
- The default embedding model is `nomic-embed-text`.
- ChromaDB storage is local to the AI server and should be backed up if the collections matter operationally.
