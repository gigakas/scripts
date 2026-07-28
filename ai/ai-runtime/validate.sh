#!/usr/bin/env bash
set -euo pipefail

AI_SERVER="${1:-http://127.0.0.1:8001}"
AUTH_TOKEN="${CHATBOT_AI_BEARER_TOKEN:-}"
PASSED=0
FAILED=0

header() { echo ""; echo "=== $1 ==="; }

fail() { echo "FAIL: $1"; FAILED=$((FAILED + 1)); }
pass() { echo "PASS: $1"; PASSED=$((PASSED + 1)); }

AUTH_ARGS=()
if [[ -n "$AUTH_TOKEN" ]]; then
	AUTH_ARGS=(-H "Authorization: Bearer $AUTH_TOKEN")
fi

header "Health check"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$AI_SERVER/health")
if [[ "$STATUS" == "200" ]]; then
	pass "GET /health returned 200"
else
	fail "GET /health returned $STATUS"
fi

header "Deep health check"
DEEP=$(curl -s "${AUTH_ARGS[@]}" "$AI_SERVER/health/deep")
DEEP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${AUTH_ARGS[@]}" "$AI_SERVER/health/deep")
if [[ "$DEEP_STATUS" == "200" ]]; then
	pass "GET /health/deep returned 200"
	echo "$DEEP" | grep -q '"ollama_reachable": true' && pass "Ollama is reachable" || fail "Ollama reachable flag missing"
	echo "$DEEP" | grep -q '"chroma_reachable": true' && pass "ChromaDB is reachable" || fail "ChromaDB reachable flag missing"
else
	fail "GET /health/deep returned $DEEP_STATUS"
fi

header "Analyze endpoint"
RESPONSE=$(curl -s -X POST "$AI_SERVER/analyze" \
	-H "Content-Type: application/json" \
	"${AUTH_ARGS[@]}" \
	-d '{
		"model": "qwen3:1.7b",
		"messages": [
			{"role": "system", "content": "Reply in one short sentence."},
			{"role": "user", "content": "What is 2+2?"}
		],
		"options": {"num_predict": 50}
	}' 2>&1)

if echo "$RESPONSE" | grep -q '"result"'; then
	pass "POST /analyze returned result"
else
	fail "POST /analyze missing result"
fi

header "RAG write/read"
UPSERT=$(curl -s -X POST "$AI_SERVER/rag/upsert" \
	-H "Content-Type: application/json" \
	"${AUTH_ARGS[@]}" \
	-d '{
		"collection_name": "validation_runtime",
		"documents": [
			{"id": "doc-1", "text": "The support email is support@example.com.", "metadata": {"source": "validation"}}
		]
	}')

if echo "$UPSERT" | grep -q '"inserted": 1'; then
	pass "POST /rag/upsert inserted a document"
else
	fail "POST /rag/upsert did not report success"
fi

QUERY=$(curl -s -X POST "$AI_SERVER/rag/query" \
	-H "Content-Type: application/json" \
	"${AUTH_ARGS[@]}" \
	-d '{
		"collection_name": "validation_runtime",
		"query": "What is the support email?",
		"limit": 1
	}')

if echo "$QUERY" | grep -q 'support@example.com'; then
	pass "POST /rag/query returned stored document"
else
	fail "POST /rag/query did not return expected document"
fi

echo ""
echo "=================================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=================================================="

if [[ $FAILED -gt 0 ]]; then
	exit 1
fi
