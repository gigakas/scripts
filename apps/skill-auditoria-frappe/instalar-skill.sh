#!/usr/bin/env bash
# Instala la skill "auditoria-frappe" para Claude Code y/o opencode.
set -euo pipefail
cd "$(dirname "$0")"
ORIG="$(pwd)/skill/auditoria-frappe"

destinos=()
[[ -d "$HOME/.claude/skills" ]] && destinos+=("$HOME/.claude/skills/auditoria-frappe")
[[ -d "$HOME/.config/opencode" ]] && destinos+=("$HOME/.config/opencode/skill/auditoria-frappe")

if [[ ${#destinos[@]} -eq 0 ]]; then
  echo "No encontré ~/.claude/skills ni ~/.config/opencode — crea uno y re-corre."
  exit 1
fi

for d in "${destinos[@]}"; do
  mkdir -p "$(dirname "$d")"
  rm -rf "$d"
  cp -r "$ORIG" "$d"
  echo "==> instalada en $d"
done
