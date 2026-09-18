# auditor-frappe

Agente LangGraph que audita una app Frappe/ERPNext (back y front): inventario →
chequeos estáticos (SQL inyectable, `ignore_permissions`, `allow_guest`,
doctypes sin permisos, `eval/exec`, XSS `innerHTML`/`| safe`, secretos en JS,
`frappe.call` a métodos no whitelisted) → resumen LLM (opcional) → informe
markdown.

## Usar

```bash
./instalar.sh
source env/bin/activate
langgraph dev --no-browser
```

Studio: https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024
— en "Interact" pasar `{"app_path": "/ruta/a/apps/mi_app"}`.

Sin server (CLI):

```bash
./env/bin/python -c "import graph; print(graph.graph.invoke({'app_path':'/ruta/a/mi_app'})['informe'])"
```

Los informes quedan en `informes/*.md`.

## El botón

`frappe/boton_auditar.py` = método whitelisted para tu bench: crea el DocType
"Auditoria Code", pega el método como Server Script (API) y conecta un botón:

```js
frappe.call({ method: "auditar_app", args: { app: "mi_app" } })
```

Requiere el server del auditor arriba (`LANGGRAPH_URL` / `auditor_url` en
site_config).

## LLM

Opcional: `cp .env.example .env` y llena `OPENAI_API_KEY` (o `LLM_BASE_URL`
para OpenRouter/Groq/Ollama). Sin key funciona igual: el resumen lo genera
una heurística.
