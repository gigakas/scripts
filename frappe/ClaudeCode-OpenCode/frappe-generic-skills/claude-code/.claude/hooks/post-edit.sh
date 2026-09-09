#!/usr/bin/env bash
# PostToolUse hook (Edit|Write):
#  1. registra cada cambio hecho por IA en changelog.md (raíz del proyecto)
#  2. formatea con ruff los .py editados
#  3. recuerda ejecutar `bench migrate` tras cambiar el JSON de un DocType
set -euo pipefail

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
[ -z "$FILE" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CHANGELOG="$ROOT/changelog.md"

# --- 1. changelog automático (excluye el propio changelog para no auto-loguearse)
case "$FILE" in
  "$CHANGELOG" | */changelog.md) : ;;
  *)
    TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // "Edit"')"
    if [ ! -f "$CHANGELOG" ]; then
      printf '# Changelog\n\nRegistro de cambios realizados por IA en este proyecto.\nLas líneas con hora las genera un hook automático; los resúmenes por tarea los añade el agente.\n\n' > "$CHANGELOG"
    fi
    printf -- '- %s · %s · `%s`\n' "$(date '+%Y-%m-%d %H:%M')" "$TOOL" "${FILE#"$ROOT"/}" >> "$CHANGELOG"
    ;;
esac

# --- 2. formateo Python
case "$FILE" in
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      ruff format "$FILE" >/dev/null 2>&1 || true
    fi
    ;;
esac

# --- 3. recordatorio de migrate en cambios de esquema
case "$FILE" in
  */doctype/*.json)
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"DocType schema changed (%s). Run: bench --site <site> migrate && bench --site <site> clear-cache"}}\n' "$FILE"
    ;;
esac
exit 0
