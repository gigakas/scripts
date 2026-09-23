# Frappe Generic Skills — Claude Code

Colección completa de skills genéricos para desarrollo con **Frappe Framework**, lista para cualquier proyecto Frappe estándar (apps custom, ERPNext, futuros proyectos). Fuente: [lubusIN/frappe-skills](https://github.com/lubusIN/frappe-skills) (licencia MIT, ver `LICENSE`).

## Cómo usar

Copia `.claude/` a la raíz del proyecto Frappe donde vayas a trabajar:

```bash
cp -r claude-code/.claude /ruta/a/tu/proyecto/
```

Claude Code detecta los skills automáticamente y los invoca cuando la tarea coincide con su descripción. No necesitas configuración adicional.

Incluye además hooks (`.claude/settings.json` + `.claude/hooks/post-edit.sh`): **changelog automático** — cada Edit/Write queda registrado en `changelog.md` en la raíz del proyecto (fecha, herramienta, archivo; el archivo se crea solo) —, formateo `ruff` de los `.py` editados y recordatorio de `bench migrate` al cambiar el JSON de un DocType.

**Consejo**: si un proyecto no va a usar frontend Vue o web forms, borra esos skills de la copia del proyecto — menos skills = mejor selección automática. Esta carpeta es la colección maestra; cada proyecto lleva su subconjunto.

## Skills incluidos (14)

| Skill | Cubre |
|---|---|
| `frappe-router` | Meta-skill: dirige la tarea al skill adecuado |
| `frappe-project-triage` | Identificar tipo de proyecto, apps instaladas y versiones |
| `frappe-app-development` | Scaffolding y arquitectura de apps custom |
| `frappe-doctype-development` | DocTypes: esquema, controladores, child tables, naming, virtual |
| `frappe-api-development` | APIs REST/RPC, autenticación, OAuth, rate limiting, webhooks |
| `frappe-desk-customization` | Form scripts y personalización de list views |
| `frappe-frontend-development` | Apps frontend con Vue 3 |
| `frappe-ui-patterns` | Patrones UI/UX de las apps oficiales |
| `frappe-printing-templates` | Print formats y plantillas de email |
| `frappe-reports` | Report Builder, Query Reports (SQL), Script Reports |
| `frappe-web-forms` | Formularios públicos sin acceso a Desk |
| `frappe-testing` | Tests unitarios/integración/UI y CI |
| `frappe-manager` | Entornos de desarrollo con Docker |
| `frappe-enterprise-patterns` | Patrones de producción |

Cada skill trae su `SKILL.md` (procedimiento) más un directorio `references/` con documentación detallada por tema.

> Los skills genéricos agnósticos de lenguaje (refactoring, design-patterns, testing, SOLID, changelog, audit) viven en su propia colección: `scripts/ClaudeCode-OpenCode/generic-skills/`.

## Relación con el kit ESRS

El kit del proyecto ESRS (`~/Documents/frappe-esrs-agent-kit/`) ya incluye un subconjunto de estos skills (los 5 más relevantes) junto a los skills de dominio ESRS/iXBRL propios. Esta carpeta es la colección genérica completa para reutilizar en proyectos nuevos.
