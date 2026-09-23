# Generic Skills — opencode

Skills genéricos agnósticos de lenguaje para **opencode**. Contenido idéntico a la variante de Claude Code; solo cambia el formato de cada herramienta.

## Cómo usar

Copia `.opencode/` a la raíz del proyecto:

```bash
cp -r opencode/.opencode /ruta/a/tu/proyecto/
```

opencode detecta los skills en `.opencode/skill/` (mismo formato `SKILL.md` con frontmatter que Claude Code). Si tu versión de opencode no soporta skills, referencia los archivos desde el `AGENTS.md` del proyecto como documentación.

## Skills incluidos (7)

| Skill | Cubre |
|---|---|
| `refactoring` | Code smells y técnicas de refactoring; umbrales de tamaño por lenguaje |
| `design-patterns` | Los 22 patrones GoF: creacionales, estructurales, de comportamiento |
| `test-driven-development` | TDD: ciclo red/green/refactor y tests de caracterización |
| `testing-patterns` | Estructura AAA, FIRST, test doubles y test smells |
| `solid-principles` | Principios SOLID (SRP, OCP, LSP, ISP, DIP) |
| `multi-agent-changelog` | Changelog multi-agente: `changelog.d/` + `changelog.md` |
| `code-audit` | Auditoría: `auditory.md` (deltas) + `track_auditory.md` (mejoras) |

## Nota

Esta colección **no incluye hooks** (los hooks de la colección Frappe son específicos: `ruff`, `bench migrate`). Si querés un changelog automático en tus proyectos, usá el skill `multi-agent-changelog`, que registra los cambios en `changelog.d/` y consolida en `changelog.md`.
