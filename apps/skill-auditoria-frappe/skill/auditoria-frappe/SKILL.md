---
name: auditoria-frappe
description: Auditar código (backend y frontend) de una app Frappe/ERPNext. Usar cuando el usuario pida auditar, revisar o revisar seguridad de una app o carpeta de una app de bench (p. ej. "audita mi_app", "revisa esta app antes del release").
---

# Auditoría de código Frappe/ERPNext

Audita una app bajo `~/bench-repo/apps/<app>` (o la ruta que dé el usuario).
Produce un informe con hallazgos por severidad. No modifique el código: solo reporta.

## Proceso

1. **Inventario.** Lista: archivos `.py` (excluyendo `node_modules`, `__pycache__`, `.git`), doctypes (`*/doctype/*/*.json`), `hooks.py`, fixtures, y jobs programados (`scheduler_events`).
2. **Chequeos estáticos.** Busca con grep/rg y reporta cada match con `archivo:linea`:
   - `frappe.db.sql(` / `frappe.db.count(` con f-string, `.format(`, `%` + tupla mal formada o concatenación `+` → **ALTA** (SQL inyectable). Nota: `%s` con parámetros es correcto, no lo marques.
   - `ignore_permissions=True` → **ALTA** (verifica que haya `has_permission` explícito antes).
   - `@frappe.whitelist(allow_guest=True)` → **MEDIA**.
   - `ignore_mandatory=True` → **MEDIA**.
   - `eval(` / `exec(` sobre datos que puedan venir de usuario → **ALTA**.
   - Doctype con `"permissions": []` (no es table) → **ALTA**.
   - Sobrescritura de core (`override_whitelisted_methods`, `override_doctype_class`, `override_doctype_code`) → **BAJA**, pedir documentación de versiones.
   - `frappe.cache()` sin versión/namespace por sitio → **BAJA**.
2b. **Chequeos frontend.** En `.js` (incluidos client scripts) y plantillas `.html`/`.jinja`:
   - `innerHTML =`, `document.write(`, jQuery `.html(variable)` con datos de usuario → **ALTA/MEDIA** (XSS); sugerir `frappe.utils.escape` o `textContent`.
   - `| safe` o `{% autoescape false %}` en plantillas (incluye print formats y `website/`, `templates/`) → **ALTA**.
   - Secretos/tokens/keys hardcodeados en `public/js` → **ALTA** (se sirve al navegador).
   - Métodos llamados desde `www/` o JS público que requieren sesión pero existen → **MEDIA**.
3. **Consistencia front/back.** Cruza: cada `frappe.call({method: ...})` del front con los `@frappe.whitelist()` del back (y viceversa: métodos guest usados solo desde UI autenticada → sugerir quitar `allow_guest`). Métodos de la app llamados desde JS que no aparecen whitelisted → **MEDIA** (roto o move a otra app). UI que muestra campos/actions sin role-check server-side → **ALTA** (la UI no es control de acceso).
4. **Revisión LLM.** Para los 10 hallazgos de ALTA/MEDIA con más impacto, lee ~30 líneas de contexto y determina: ¿falso positivo? ¿explotable desde un role no-System? Corrige la severidad con justificación.
5. **Informe.** Markdown: resumen ejecutivo (3 líneas), tabla de hallazgos por severidad, y por cada uno: ubicación, snippet, riesgo y fix sugerido con código Frappe idiomático. Guarda en `auditoria-<app>-<fecha>.md`.

## Reglas

- Cita siempre `archivo:linea`; nunca inventes matches — verifica leyendo el archivo.
- Si el proyecto tiene el agente LangGraph `../auditor-frappe`, puedes usarlo para el primer barrido y luego profundizar tú.
- Idioma: español.
