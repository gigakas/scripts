# Generic Skills — Agnósticos de lenguaje

Colección de skills **genéricos y agnósticos de lenguaje**, aplicables a cualquier proyecto (Python, JavaScript/TypeScript, Java, C#, Go, Ruby, Rust, PHP, etc.) independientemente del framework. No dependen de Frappe ni de ningún dominio específico.

Dos variantes con el **mismo contenido**, una por herramienta:

- `opencode/` — skills para **opencode** (`.opencode/skill/`)
- `claude-code/` — skills para **Claude Code** (`.claude/skills/`)

## Skills incluidos (7)

| Skill | Cubre |
|---|---|
| `refactoring` | Code smells (23 en 6 grupos) y 60+ técnicas de refactoring; umbrales de tamaño/responsabilidad por lenguaje |
| `design-patterns` | Los 22 patrones GoF: creacionales, estructurales, de comportamiento |
| `test-driven-development` | TDD: ciclo red/green/refactor y tests de caracterización |
| `testing-patterns` | Estructura AAA, principios FIRST, test doubles y test smells |
| `solid-principles` | Principios SOLID (SRP, OCP, LSP, ISP, DIP) |
| `multi-agent-changelog` | Changelog multi-agente: reporte incremental en `changelog.d/` + consolidación en `changelog.md` |
| `code-audit` | Auditoría de código: `auditory.md` (historial con deltas) + `track_auditory.md` (mejoras con importancia) |

Cada skill trae su `SKILL.md` (procedimiento) y, según el caso, un directorio `references/` con documentación detallada.

## Cómo usar

Copia la variante de tu herramienta a la raíz del proyecto donde vayas a trabajar:

```bash
# opencode
cp -r generic-skills/opencode/.opencode /ruta/a/tu/proyecto/

# Claude Code
cp -r generic-skills/claude-code/.claude /ruta/a/tu/proyecto/
```

Ambas herramientas detectan los skills automáticamente y los invocan cuando la tarea coincide con su `description`. No se necesita configuración adicional.

## Relación con los skills de Frappe

Estos skills son independientes del dominio. Los skills específicos de **Frappe Framework** viven en otra colección: `frappe/ClaudeCode-OpenCode/frappe-generic-skills/`.

## Notas

- **Detección de agente**: los skills que registran historial (`multi-agent-changelog`, `code-audit`) detectan automáticamente si corren bajo opencode (`OC`) o Claude Code (`AC`).
- **Licencia**: contenido elaborado a partir de las referencias públicas de [refactoring.guru](https://refactoring.guru) y conocimiento estándar de ingeniería de software. Revisa su [Content Usage Policy](https://refactoring.guru/content-usage-policy) si vas a redistribuir.
