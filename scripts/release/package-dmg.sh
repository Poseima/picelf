#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 2 || ! -d "$1" || "$1" != *.app ]]; then
  echo "Usage: $0 /path/to/application.app /path/to/output.dmg" >&2
  exit 2
fi
app_path="$1"
output_path="$2"
[[ ! -e "$output_path" ]] || { echo "Refusing to overwrite an existing DMG" >&2; exit 1; }
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/picelf-open-dmg.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
mkdir -p "$(dirname "$output_path")"
ditto "$app_path" "$staging_dir/$(basename "$app_path")"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname 'Picelf' -srcfolder "$staging_dir" -format UDZO -ov "$output_path"
