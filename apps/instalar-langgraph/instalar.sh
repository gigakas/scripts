#!/usr/bin/env bash
# Crea un proyecto LangGraph nuevo (venv + deps + esqueleto) en la ruta dada.
# Uso:  ./instalar.sh ~/Documentos/mi-agente
set -euo pipefail

PROYECTO="${1:-}"
if [[ -z "$PROYECTO" ]]; then
  echo "Uso: $0 <ruta-del-nuevo-proyecto>"
  echo 'Ejemplo: $0 ~/Documentos/mi-agente'
  exit 1
fi

if [[ -e "$PROYECTO" ]]; then
  echo "Ya existe: $PROYECTO (no lo piso)"
  exit 1
fi

echo "==> Creando estructura en $PROYECTO"
mkdir -p "$PROYECTO"
cd "$PROYECTO"

cat > langgraph.json <<'JSON'
{
  "dependencies": ["."],
  "graphs": {
    "mi_grafo": "./graph.py:graph"
  },
  "env": ".env"
}
JSON

cat > graph.py <<'PY'
from typing import Annotated, TypedDict

from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages


class Estado(TypedDict):
    mensajes: Annotated[list, add_messages]


def nodo_responder(estado: Estado) -> dict:
    ultimo = estado["mensajes"][-1]
    texto = getattr(ultimo, "content", str(ultimo))

    try:
        import os

        if os.environ.get("OPENAI_API_KEY"):
            from langchain_openai import ChatOpenAI

            modelo = ChatOpenAI(
                model=os.environ.get("LLM_MODEL", "gpt-4o-mini"),
                base_url=os.environ.get("LLM_BASE_URL") or None,
                temperature=0,
            )
            r = modelo.invoke(estado["mensajes"])
            return {"mensajes": [r]}
    except Exception as e:  # noqa: BLE001
        return {"mensajes": [{"role": "assistant", "content": f"Error de LLM: {e}"}]}

    return {"mensajes": [{"role": "assistant", "content": f"(sin LLM) ecos: {texto}"}]}


builder = StateGraph(Estado)
builder.add_node("responder", nodo_responder)
builder.add_edge(START, "responder")
builder.add_edge("responder", END)

graph = builder.compile()
PY

cat > .env.example <<'ENV'
# Copia a .env y llena lo que uses. Todo es opcional para el esqueleto.
OPENAI_API_KEY=
*** Sin esto usa OpenAI. Puede ser OpenRouter, Groq, Ollama...
LLM_BASE_URL=
LLM_MODEL=gpt-4o-mini
ENV

touch .env
printf '%s\n' "env/" ".langgraph_api/" ".env" "informes/" > .gitignore

echo "==> Creando venv (python3)"
python3 -m venv env
./env/bin/pip install --quiet --upgrade pip
echo "==> Instalando LangGraph (puede tardar un poco)"
./env/bin/pip install --quiet "langgraph-cli[inmem]" langgraph langchain-openai python-dotenv

echo
echo "Listo. Para arrancar:"
echo "  cd $PROYECTO"
echo "  source env/bin/activate"
echo "  langgraph dev --no-browser"
echo
echo "Studio: https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024"
