#!/usr/bin/env bash
set -euo pipefail
root="${PICELF_DERIVED_DATA_ROOT:-${HOME}/Library/Developer/Xcode/DerivedData}"
latest_app=""
while IFS= read -r candidate; do
  details="$(codesign -dv "$candidate" 2>&1 || true)"
  if [[ "$details" == *'TeamIdentifier='* && "$details" != *'TeamIdentifier=not set'* ]] && codesign --verify --strict "$candidate" 2>/dev/null; then
    latest_app="$candidate"
    break
  fi
done < <(find "$root" -path '*/Build/Products/Debug/Picelf.app' -prune -type d -print 2>/dev/null | while IFS= read -r path; do stat -f '%m %N' "$path"; done | sort -rn | cut -d' ' -f2-)
[[ -n "$latest_app" ]] || { echo 'No developer-signed Debug Picelf.app found. Run scheme Picelf from Xcode using your own team first.' >&2; exit 1; }
printf 'Opening signed Debug app: %s\n' "$latest_app"
open "$latest_app"
