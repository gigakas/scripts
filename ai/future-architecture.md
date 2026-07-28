# Future Architecture Decisions

## Redis on the AI server (item 54)

**Decision: Not needed in phase 1. Evaluate when one of these triggers occurs:**

- Throughput exceeds 10+ sustained concurrent analysis requests.
- Multiple worker processes need shared state.
- You implement caching for repeated prompts or model responses.
- You add rate limiting or request queuing on the AI server side.
- Latency-sensitive workloads benefit from response caching.

**When Redis is introduced, prefer:**
- A dedicated Redis instance or container (not shared with Frappe's Redis).
- Environment-based configuration.
- Using Redis for queue management, not as a primary data store.

## RAG / Vector DB future (item 55)

**Decision: The AI runtime now ships with ChromaDB support.**

**Current direction:**
- Frappe remains the orchestration layer.
- The separated AI runtime now supports inference, embeddings, and ChromaDB-backed retrieval.
- Existing Frappe-local RAG can remain temporarily during migration.

**Recommended next migration steps:**
1. Move collection writes and retrieval calls to `deployment/ai_runtime/app/main.py` endpoints.
2. Keep collection naming stable across Frappe and the AI runtime.
3. Re-index collections when changing the embedding model.
4. Reduce direct `chromadb` imports in Frappe once all retrieval paths call the AI runtime.

**Target architecture:**
```
Frappe -> AI Runtime/analyze -> Ollama
Frappe -> AI Runtime/rag     -> Chroma
```
