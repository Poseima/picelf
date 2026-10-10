#!/usr/bin/env bash
set -euo pipefail
[[ -n "${PICELF_SIGNING_DIR:-}" && -d "$PICELF_SIGNING_DIR" ]] || exit 0
python3 - <<'PYCODE'
import json,os,pathlib,subprocess
p=pathlib.Path(os.environ['PICELF_SIGNING_DIR'])
if (p/'keychains.json').exists():
    subprocess.run(['security','list-keychains','-d','user','-s',*json.loads((p/'keychains.json').read_text())],check=False)
subprocess.run(['security','delete-keychain',str(p/'release.keychain-db')],check=False)
PYCODE
rm -rf "$PICELF_SIGNING_DIR"
