# Generic Skills — Claude Code

Skills genéricos agnósticos de lenguaje para **Claude Code**. Contenido idéntico a la variante de opencode; solo cambia el formato de cada herramienta.

## Cómo usar

Copia `.claude/` a la raíz del proyecto:

```bash
cp -r claude-code/.claude /ruta/a/tu/proyecto/
```

Claude Code detecta los skills automáticamente y los invoca cuando la tarea coincide con su `description`. No necesitas configuración adicional.

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
