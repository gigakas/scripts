"""Auditor de código (back y front) de apps Frappe/ERPNext como grafo LangGraph.

Flujo: inventario -> chequeos estáticos -> (LLM si hay hallazgos y hay API key)
-> informe markdown. Se corre sin LLM: sin OPENAI_API_KEY el nodo llm degrada
a un resumen heurístico.

Cubre:
- Backend .py: SQL inyectable, ignore_permissions, allow_guest, ignore_mandatory,
  eval/exec, hooks de override.
- Frontend .js: innerHTML/document.write, .html(variable), secretos hardcodeados.
- Plantillas .html/.jinja: `| safe`, autoescape off.
- Consistencia front/back: frappe.call a métodos del app no whitelisted.
- Doctypes: sin filas de permisos.

Invocación (Studio, API o Python directo):
    graph.invoke({"app_path": "/ruta/a/apps/mi_app"})
"""

import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import TypedDict


class Estado(TypedDict, total=False):
    app_path: str
    archivos: list
    archivos_js: list
    archivos_tpl: list
    doctypes: list
    metodos_whitelist: dict
    hallazgos: list
    resumen: str
    informe: str
    error: str


EXCLUIR_DIRS = {".git", "node_modules", "__pycache__", ".venv", "env", "venv", "dist", "locales"}

# (regla, severidad, regex, detalle)
REGLAS_PY = [
    ("sql_inyectable", "alta",
     re.compile(r"frappe\.db\.(sql|count)\s*\(.*(f['\"]|\.format\(|%\s*\(|%\s*\{|['\"]\s*\+|\+\s*['\"])"),
     "Query SQL construida con interpolación de strings; usar parámetros (%s) y una tupla/lista de valores."),
    ("ignore_permissions", "alta",
     re.compile(r"ignore_permissions\s*=\s*True"),
     "Llamada con ignore_permissions=True; revisar si hay un control de rol explícito antes."),
    ("allow_guest", "media",
     re.compile(r"allow_guest\s*=\s*True"),
     "Método whitelisted accesible sin sesión (allow_guest=True); riesgo de enumeración/IDOR."),
    ("ignore_mandatory", "media",
     re.compile(r"ignore_mandatory\s*=\s*True"),
     "Guardado saltando campos obligatorios."),
    ("eval_exec", "alta",
     re.compile(r"\b(eval|exec)\s*\("),
     "eval/exec sobre datos — revisar que no provengan de input de usuario."),
    ("hook_osa", "baja",
     re.compile(r"override_whitelisted_methods|override_doctype_class"),
     "Sobrescribe métodos/clases core (overriding): documentarlo y fijar versión mínima."),
]

REGLAS_JS = [
    ("xss_innerhtml", "alta",
     re.compile(r"\.innerHTML\s*=|document\.write\("),
     "Asignación directa de innerHTML/document.write: XSS si el valor contiene datos de usuario; usar frappe.utils.escape / textContent."),
    ("xss_jquery_html", "media",
     re.compile(r"\.html\(\s*[A-Za-z_$]"),
     ".html(variable): verificar que la variable no incluya input de usuario sin escapar."),
    ("secreto_en_js", "alta",
     re.compile(r"(?i)\b(api[_-]?key|apikey|secret|token|password|passwd)\s*[:=]\s*['\"][A-Za-z0-9_\-./+=]{12,}['\"]"),
     "Posible secreto hardcodeado en JS: todo public/js se descarga en el navegador."),
]

REGLAS_TPL = [
    ("xss_template_safe", "alta",
     re.compile(r"\|\s*safe\b"),
     "Filtro `| safe` en Jinja desactiva el autoescape: XSS si el valor proviene de documentos."),
    ("xss_autoescape_off", "alta",
     re.compile(r"{%\s*autoescape\s+false"),
     "Bloque con autoescape desactivado en plantilla."),
]

DOCTYPE_JSON = re.compile(r"[/\\]doctype[/\\](?P<nombre>[\w-]+)[/\\](?P=nombre)\.json$")
WHITELIST_DEC = re.compile(r"@frappe\.whitelist")
JS_METHOD_CALL = re.compile(r"method:\s*['\"]([A-Za-z_][\w.]*)['\"]")


def _iter_por_ext(raiz: Path, exts: tuple):
    for ext in exts:
        for p in raiz.rglob(f"*{ext}"):
            if EXCLUIR_DIRS & set(p.parts):
                continue
            if ext == ".js" and p.name.endswith(".min.js"):
                continue
            yield p


def nodo_inventario(estado: Estado) -> dict:
    app_path = Path(estado.get("app_path", "")).expanduser().resolve()
    if not app_path.is_dir():
        return {"error": f"No existe la ruta: {app_path}", "archivos": [], "doctypes": []}

    archivos = [str(p) for p in _iter_por_ext(app_path, (".py",))]
    archivos_js = [str(p) for p in _iter_por_ext(app_path, (".js",))]
    archivos_tpl = [str(p) for p in _iter_por_ext(app_path, (".html", ".jinja", ".j2"))]

    doctypes = []
    for p in _iter_por_ext(app_path, (".json",)):
        m = DOCTYPE_JSON.search(str(p))
        if not m:
            continue
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        if data.get("istable"):
            continue
        doctypes.append({
            "nombre": data.get("name", m.group("nombre")),
            "modulo": data.get("module", ""),
            "n_permisos": len(data.get("permissions") or []),
        })

    # registro de métodos whitelisted (dotted name -> allow_guest)
    metodos: dict = {}
    for ruta in archivos:
        try:
            lineas = Path(ruta).read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for i, ln in enumerate(lineas):
            if not WHITELIST_DEC.search(ln):
                continue
            bloque = " ".join(lineas[i:i + 4])
            dm = re.search(r"def\s+(\w+)", bloque)
            if not dm:
                continue
            rel = Path(ruta).relative_to(app_path)
            partes = list(rel.parts)
            partes[-1] = partes[-1][:-3]
            mod = re.search(r"@frappe\.whitelist\(\s*(.*?)\)", bloque)
            guest = bool(mod and "allow_guest" in mod.group(1))
            metodos[".".join(partes) + "." + dm.group(1)] = guest

    return {
        "app_path": str(app_path),
        "archivos": archivos[:3000],
        "archivos_js": archivos_js[:3000],
        "archivos_tpl": archivos_tpl[:3000],
        "doctypes": doctypes,
        "metodos_whitelist": metodos,
        "error": "",
    }


def _scan(estado: Estado, claves: tuple, reglas: list, solo_hooks: bool = False) -> list:
    app = estado["app_path"] + "/"
    hallazgos = []
    for ruta in estado.get(claves[0], []):
        try:
            lineas = Path(ruta).read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        if solo_hooks and Path(ruta).name != "hooks.py":
            continue
        rel = ruta.replace(app, "")
        for i, linea in enumerate(lineas, 1):
            for regla, sev, rx, detalle in reglas:
                if rx.search(linea):
                    hallazgos.append({
                        "archivo": rel, "linea": i, "regla": regla,
                        "severidad": sev, "snippet": linea.strip()[:160],
                        "detalle": detalle,
                    })
    return hallazgos


def nodo_estatico(estado: Estado) -> dict:
    reglas_py = [r for r in REGLAS_PY if r[0] != "hook_osa"]
    hallazgos = _scan(estado, ("archivos",), reglas_py)
    hallazgos += _scan(estado, ("archivos",), [r for r in REGLAS_PY if r[0] == "hook_osa"], solo_hooks=True)
    hallazgos += _scan(estado, ("archivos_js",), REGLAS_JS)
    hallazgos += _scan(estado, ("archivos_tpl",), REGLAS_TPL)

    # consistencia front/back: frappe.call() a métodos de esta app no whitelisted
    app_nombre = Path(estado["app_path"]).name
    for ruta in estado.get("archivos_js", []):
        try:
            texto = Path(ruta).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = ruta.replace(estado["app_path"] + "/", "")
        for m in JS_METHOD_CALL.finditer(texto):
            metodo = m.group(1)
            if not metodo.startswith(app_nombre + "."):
                continue  # core u otra app: no auditable aquí
            if metodo not in estado.get("metodos_whitelist", {}):
                hallazgos.append({
                    "archivo": rel,
                    "linea": texto[:m.start()].count("\n") + 1,
                    "regla": "metodo_no_whitelisted",
                    "severidad": "media",
                    "snippet": f'method: "{metodo}"',
                    "detalle": "El JS llama a un método de esta app que no aparece con @frappe.whitelist (roto, o whitelisted en otro lado: verificar).",
                })

    for dt in estado.get("doctypes", []):
        if dt["n_permisos"] == 0:
            hallazgos.append({
                "archivo": f"doctype/{dt['nombre']}",
                "linea": 0,
                "regla": "doctype_sin_permisos",
                "severidad": "alta",
                "snippet": "permissions = []",
                "detalle": "Doctype sin filas de permisos: nadie (salvo System Manager) puede acceder; probable olvido.",
            })

    return {"hallazgos": hallazgos}


def _hay_llm() -> bool:
    return bool(os.environ.get("OPENAI_API_KEY") or os.environ.get("LLM_BASE_URL"))


def nodo_llm(estado: Estado) -> dict:
    hs = estado.get("hallazgos", [])
    if not hs or not _hay_llm():
        conteo = {}
        for h in hs:
            conteo[h["regla"]] = conteo.get(h["regla"], 0) + 1
        top = ", ".join(f"{k}: {v}" for k, v in sorted(conteo.items(), key=lambda x: -x[1])[:6])
        return {"resumen": f"(sin LLM) {len(hs)} hallazgos estáticos. Top: {top or '-'}"}

    try:
        from langchain_openai import ChatOpenAI

        prompt = (
            "Eres auditor senior de código en Frappe/ERPNext (backend y frontend). Resume en español "
            "(máx 15 líneas) los riesgos principales y las 3 acciones prioritarias. Hallazgos (JSON truncado):\n"
            + json.dumps(hs[:30], ensure_ascii=False)[:6000]
        )
        modelo = ChatOpenAI(
            model=os.environ.get("LLM_MODEL", "gpt-4o-mini"),
            base_url=os.environ.get("LLM_BASE_URL") or None,
            temperature=0,
        )
        return {"resumen": modelo.invoke(prompt).content.strip()}
    except Exception as e:  # noqa: BLE001
        return {"resumen": f"LLM falló ({e}); se entrega solo el análisis estático."}


SEV_ORDEN = {"alta": 0, "media": 1, "baja": 2}


def nodo_informe(estado: Estado) -> dict:
    if estado.get("error"):
        return {"informe": f"# Error de auditoría\n\n{estado['error']}"}

    hs = sorted(estado.get("hallazgos", []), key=lambda h: SEV_ORDEN.get(h["severidad"], 9))
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    app = Path(estado.get("app_path", "?")).name

    lineas = [
        f"# Auditoría de código (back + front) — {app}",
        f"- Ruta: `{estado.get('app_path')}`",
        f"- Fecha: {ts}",
        f"- Python: {len(estado.get('archivos', []))} | JS: {len(estado.get('archivos_js', []))} "
        f"| Plantillas: {len(estado.get('archivos_tpl', []))} | Doctypes: {len(estado.get('doctypes', []))} "
        f"| Métodos whitelisted: {len(estado.get('metodos_whitelist', {}))}",
        f"- Hallazgos: {len(hs)}",
        "",
        "## Resumen",
        estado.get("resumen") or "(sin resumen)",
        "",
        "## Hallazgos",
    ]
    if not hs:
        lineas.append("Sin hallazgos con las reglas configuradas.")
    for h in hs:
        lineas.append(
            f"- **[{h['severidad'].upper()}] {h['regla']}** — `{h['archivo']}"
            f"{':' + str(h['linea']) if h['linea'] else ''}`  \n  {h['detalle']}\n  > `{h['snippet']}`"
        )

    informe = "\n".join(lineas)
    out = Path(__file__).parent / "informes"
    out.mkdir(exist_ok=True)
    slug = re.sub(r"\W+", "_", app)[:40]
    archivo = out / f"auditoria_{slug}_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.md"
    archivo.write_text(informe, encoding="utf-8")
    return {"informe": informe}


def _ruta_llm(estado: Estado) -> str:
    return "llm" if estado.get("hallazgos") else "informe"


from langgraph.graph import END, START, StateGraph  # noqa: E402

builder = StateGraph(Estado)
builder.add_node("inventario", nodo_inventario)
builder.add_node("estatico", nodo_estatico)
builder.add_node("llm", nodo_llm)
builder.add_node("informe", nodo_informe)

builder.add_edge(START, "inventario")
builder.add_edge("inventario", "estatico")
builder.add_conditional_edges("estatico", _ruta_llm, ["llm", "informe"])
builder.add_edge("llm", "informe")
builder.add_edge("informe", END)

graph = builder.compile()
