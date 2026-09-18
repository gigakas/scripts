#!/usr/bin/env bash
# Instala el entorno del agente auditor (venv local en ./env)
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -d env ]]; then
  echo "==> Creando venv"
  python3 -m venv env
fi
echo "==> Instalando dependencias"
./env/bin/pip install --quiet --upgrade pip
./env/bin/pip install --quiet "langgraph-cli[inmem]" langgraph langchain-openai python-dotenv requests

echo
echo "Listo. Para arrancar el server:"
echo "  cd $(pwd)"
echo "  source env/bin/activate"
echo "  langgraph dev --no-browser"
echo
echo "Studio: https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024"
echo "Corrida rápida sin server:"
echo "  ./env/bin/python -c \"import graph; r=graph.graph.invoke({'app_path':'/ruta/a/tu/apps/mi_app'}); print(r['informe'][:800])\""
