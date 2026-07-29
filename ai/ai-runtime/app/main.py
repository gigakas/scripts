import logging
import sys
import time

import chromadb
import requests
from fastapi import FastAPI, Header, HTTPException

from app.schemas import AnalyzeRequest, AnalyzeResponse, RagMatch, RagQueryRequest, RagQueryResponse, RagUpsertRequest, RagUpsertResponse
from app.settings import settings


logging.basicConfig(level=logging.INFO, stream=sys.stdout)
logger = logging.getLogger("ai-runtime")

app = FastAPI(title="Chatbot AI Runtime")
_chroma_client = None
_vllm_model_routes: dict[str, str] = {}


def _vllm_base_urls() -> list[str]:
	urls = [settings.vllm_base_url.rstrip("/")]
	for extra in settings.vllm_extra_base_urls.split(","):
		extra = extra.strip().rstrip("/")
		if extra and extra not in urls:
			urls.append(extra)
	return urls


def _resolve_vllm_base_url(model_name: str) -> str:
	base_url = _vllm_model_routes.get(model_name)
	if base_url:
		return base_url
	try:
		_vllm_models()
	except Exception:
		pass
	return _vllm_model_routes.get(model_name, _vllm_base_urls()[0])


def _authorize(authorization: str | None):
	if not settings.chatbot_ai_bearer_token:
		return
	expected = f"Bearer {settings.chatbot_ai_bearer_token}"
	if authorization != expected:
		raise HTTPException(status_code=401, detail="Unauthorized")


def _get_chroma_client():
	global _chroma_client
	if _chroma_client is None:
		_chroma_client = chromadb.PersistentClient(path=settings.chroma_persist_dir)
	return _chroma_client


def _get_collection(name: str):
	return _get_chroma_client().get_or_create_collection(name=name, metadata={"hnsw:space": "cosine"})


def _embed_via_ollama(texts: list[str], model_name: str) -> list[list[float]]:
	base_url = settings.ollama_base_url.rstrip("/")
	response = requests.post(
		f"{base_url}/api/embed",
		json={"model": model_name, "input": texts},
		timeout=settings.request_timeout,
	)
	if response.ok:
		data = response.json()
		embeddings = data.get("embeddings") or []
		if embeddings:
			return embeddings

	if response.status_code not in (404, 400):
		response.raise_for_status()

	embeddings = []
	for text in texts:
		legacy_response = requests.post(
			f"{base_url}/api/embeddings",
			json={"model": model_name, "prompt": text},
			timeout=settings.request_timeout,
		)
		legacy_response.raise_for_status()
		embeddings.append(legacy_response.json().get("embedding") or [])
	return embeddings


def _embed_via_vllm(texts: list[str], model_name: str) -> list[list[float]]:
	base_url = _resolve_vllm_base_url(model_name)
	response = requests.post(
		f"{base_url}/embeddings",
		json={"model": model_name, "input": texts},
		timeout=settings.request_timeout,
	)
	response.raise_for_status()
	data = response.json()
	return [item["embedding"] for item in data.get("data", [])]


def _embed_texts(texts: list[str], model_name: str | None = None) -> list[list[float]]:
	model_name = model_name or settings.embedding_model
	if settings.embedding_provider == "vllm":
		return _embed_via_vllm(texts, model_name)
	return _embed_via_ollama(texts, model_name)


def _ollama_models() -> list[str]:
	response = requests.get(f"{settings.ollama_base_url.rstrip('/')}/api/tags", timeout=10)
	response.raise_for_status()
	models = response.json().get("models", [])
	return [model.get("name", "") for model in models]


def _vllm_models() -> list[str]:
	all_models: list[str] = []
	last_error: Exception | None = None
	for base_url in _vllm_base_urls():
		try:
			response = requests.get(f"{base_url}/models", timeout=10)
			response.raise_for_status()
			models = response.json().get("data", [])
			for model in models:
				model_id = model.get("id", "")
				if not model_id:
					continue
				_vllm_model_routes[model_id] = base_url
				if model_id not in all_models:
					all_models.append(model_id)
		except Exception as e:
			logger.warning(f"vLLM endpoint unreachable ({base_url}): {e}")
			last_error = e

	if not all_models and last_error:
		raise last_error
	return all_models


@app.get("/models")
@app.get("/v1/models")
def list_models():
	if settings.chatbot_ai_provider == "vllm":
		models = _vllm_models()
	else:
		models = _ollama_models()
	return {
		"object": "list",
		"data": [{"id": model, "object": "model"} for model in models],
	}


@app.get("/health")
def health():
	return {
		"status": "ok",
		"provider": settings.chatbot_ai_provider,
		"embedding_provider": settings.embedding_provider,
		"vector_store": "chromadb",
	}


@app.get("/health/deep")
def health_deep(authorization: str | None = Header(default=None)):
	_authorize(authorization)
	checks: dict = {
		"server": "ok",
		"provider": settings.chatbot_ai_provider,
		"embedding_provider": settings.embedding_provider,
		"vector_store": "chromadb",
		"chroma_persist_dir": settings.chroma_persist_dir,
	}
	healthy = True

	if settings.chatbot_ai_provider == "vllm":
		try:
			models = _vllm_models()
			checks["models"] = models
			checks["vllm_reachable"] = True
			checks["vllm_model_count"] = len(models)
			checks["vllm_models"] = models[:8]
		except Exception as e:
			checks["vllm_reachable"] = False
			checks["vllm_error"] = f"{type(e).__name__}: {str(e)}"
			healthy = False
	else:
		try:
			models = _ollama_models()
			checks["models"] = models
			checks["ollama_reachable"] = True
			checks["ollama_model_count"] = len(models)
			checks["ollama_models"] = models[:8]
		except Exception as e:
			checks["ollama_reachable"] = False
			checks["ollama_error"] = f"{type(e).__name__}: {str(e)}"
			healthy = False

	try:
		collections = _get_chroma_client().list_collections()
		collection_names = [getattr(collection, "name", str(collection)) for collection in collections]
		checks["chroma_reachable"] = True
		checks["chroma_collection_count"] = len(collection_names)
		checks["chroma_collections"] = collection_names[:8]
	except Exception as e:
		checks["chroma_reachable"] = False
		checks["chroma_error"] = f"{type(e).__name__}: {str(e)}"
		healthy = False

	if healthy:
		return checks

	raise HTTPException(status_code=503, detail=checks)


def _analyze_via_ollama(payload: AnalyzeRequest) -> tuple[dict, float]:
	options = dict(payload.options or {})
	requested_num_ctx = options.get("num_ctx")
	if not requested_num_ctx or requested_num_ctx < settings.ollama_default_num_ctx:
		options["num_ctx"] = settings.ollama_default_num_ctx
	logger.info(f"Ollama request: model={payload.model} options={options}")
	request_payload = {
		"model": payload.model,
		"messages": [message.model_dump() for message in payload.messages],
		"stream": False,
		"options": options,
	}
	if payload.response_format == "json":
		request_payload["format"] = "json"

	started = time.perf_counter()
	response = requests.post(
		f"{settings.ollama_base_url.rstrip('/')}/api/chat",
		json=request_payload,
		timeout=settings.request_timeout,
	)
	if not response.ok:
		logger.warning(f"Ollama error {response.status_code}: {response.text[:300]}")
		raise HTTPException(status_code=502, detail=f"Ollama error: {response.text[:300]}")
	latency_ms = int((time.perf_counter() - started) * 1000)
	return response.json(), latency_ms


def _analyze_via_vllm(payload: AnalyzeRequest) -> tuple[dict, float]:
	request_payload: dict = {
		"model": payload.model,
		"messages": [message.model_dump() for message in payload.messages],
	}
	options = payload.options or {}
	temperature = options.get("temperature")
	if temperature is not None:
		request_payload["temperature"] = float(temperature)
	top_p = options.get("top_p")
	if top_p is not None:
		request_payload["top_p"] = float(top_p)
	max_tokens = options.get("max_tokens") or options.get("num_predict")
	if max_tokens is not None:
		request_payload["max_tokens"] = int(max_tokens)

	if payload.response_format == "json":
		request_payload["response_format"] = {"type": "json_object"}

	base_url = _resolve_vllm_base_url(payload.model)
	started = time.perf_counter()
	response = requests.post(
		f"{base_url}/chat/completions",
		json=request_payload,
		timeout=settings.request_timeout,
	)
	if not response.ok:
		print(f"[vLLM ERROR {response.status_code}] {response.text}", flush=True)
		raise HTTPException(status_code=502, detail=f"vLLM error: {response.text[:300]}")
	latency_ms = int((time.perf_counter() - started) * 1000)
	return response.json(), latency_ms


@app.post("/analyze", response_model=AnalyzeResponse)
def analyze(payload: AnalyzeRequest, authorization: str | None = Header(default=None)):
	_authorize(authorization)

	if settings.chatbot_ai_provider == "vllm":
		data, latency_ms = _analyze_via_vllm(payload)
		choice = (data.get("choices") or [{}])[0]
		message = choice.get("message") or {}
		usage = data.get("usage") or {}
		return AnalyzeResponse(
			result=(message.get("content") or "").strip(),
			prompt_tokens=usage.get("prompt_tokens") or 0,
			completion_tokens=usage.get("completion_tokens") or 0,
			usage={
				"prompt_tokens": usage.get("prompt_tokens") or 0,
				"completion_tokens": usage.get("completion_tokens") or 0,
			},
			provider="vllm",
			model=payload.model,
			latency_ms=latency_ms,
			status="success",
		)

	data, latency_ms = _analyze_via_ollama(payload)
	return AnalyzeResponse(
		result=(data.get("message", {}) or {}).get("content", "").strip(),
		prompt_tokens=int(data.get("prompt_eval_count") or 0),
		completion_tokens=int(data.get("eval_count") or 0),
		usage={
			"prompt_tokens": int(data.get("prompt_eval_count") or 0),
			"completion_tokens": int(data.get("eval_count") or 0),
		},
		provider="ollama",
		model=payload.model,
		latency_ms=latency_ms,
		status="success",
	)


@app.get("/rag/collections")
def rag_collections(authorization: str | None = Header(default=None)):
	_authorize(authorization)
	collections = _get_chroma_client().list_collections()
	collection_names = [getattr(collection, "name", str(collection)) for collection in collections]
	return {
		"status": "success",
		"collections": collection_names,
		"count": len(collection_names),
	}


@app.post("/rag/upsert", response_model=RagUpsertResponse)
def rag_upsert(payload: RagUpsertRequest, authorization: str | None = Header(default=None)):
	_authorize(authorization)
	collection = _get_collection(payload.collection_name)
	texts = [document.text for document in payload.documents]
	ids = [document.id for document in payload.documents]
	metadatas = [document.metadata for document in payload.documents]
	embedding_model = payload.embedding_model or settings.embedding_model
	embeddings = _embed_texts(texts, embedding_model)
	collection.upsert(ids=ids, documents=texts, metadatas=metadatas, embeddings=embeddings)
	return RagUpsertResponse(
		collection_name=payload.collection_name,
		inserted=len(payload.documents),
		total_documents=collection.count(),
		embedding_model=embedding_model,
		status="success",
	)


@app.post("/rag/query", response_model=RagQueryResponse)
def rag_query(payload: RagQueryRequest, authorization: str | None = Header(default=None)):
	_authorize(authorization)
	collection = _get_collection(payload.collection_name)
	embedding_model = payload.embedding_model or settings.embedding_model
	query_embedding = _embed_texts([payload.query], embedding_model)[0]
	query_response = collection.query(
		query_embeddings=[query_embedding],
		n_results=payload.limit,
		where=payload.where or None,
		include=["documents", "metadatas", "distances"],
	)

	ids = (query_response.get("ids") or [[]])[0]
	documents = (query_response.get("documents") or [[]])[0]
	metadatas = (query_response.get("metadatas") or [[]])[0]
	distances = (query_response.get("distances") or [[]])[0]

	matches = []
	for index, item_id in enumerate(ids):
		matches.append(RagMatch(
			id=item_id,
			document=documents[index] if index < len(documents) else "",
			metadata=metadatas[index] if index < len(metadatas) else {},
			distance=distances[index] if index < len(distances) else None,
		))

	return RagQueryResponse(
		collection_name=payload.collection_name,
		query=payload.query,
		matches=matches,
		embedding_model=embedding_model,
		status="success",
	)
