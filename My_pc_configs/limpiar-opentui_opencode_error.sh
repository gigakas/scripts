#!/usr/bin/env bash

set -u

removed=0

for file in /tmp/.*.so; do
  [[ -f "$file" ]] || continue
  [[ "$(stat -c %u "$file" 2>/dev/null)" == "$(id -u)" ]] || continue
  readelf -d "$file" 2>/dev/null | grep -q 'Library soname: \[libopentui\.so\]' || continue

  if rm -- "$file"; then
    printf 'Eliminado: %s\n' "$file"
    ((removed += 1))
  fi
done

printf 'Limpieza terminada: %d archivo(s) eliminado(s).\n' "$removed"
