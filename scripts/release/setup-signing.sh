#!/usr/bin/env bash
set -euo pipefail
: "${RUNNER_TEMP:?Run this on a GitHub Actions runner}"
: "${GITHUB_ENV:?GitHub Actions environment file is required}"
: "${DEVELOPER_ID_P12_BASE64:?Missing certificate}"
: "${DEVELOPER_ID_P12_PASSWORD:?Missing certificate password}"
: "${DEVELOPER_ID_IDENTITY:?Missing signing identity}"
[[ "$DEVELOPER_ID_IDENTITY" == 'Developer ID Application:'* ]] || { echo 'Official distribution requires Developer ID Application' >&2; exit 1; }
signing_dir="$(mktemp -d "$RUNNER_TEMP/picelf-signing.XXXXXX")"
export PICELF_SIGNING_DIR="$signing_dir"
python3 - <<'PYCODE'
import base64,json,os,pathlib,secrets,shlex,subprocess
p=pathlib.Path(os.environ['PICELF_SIGNING_DIR'])
(p/'certificate.p12').write_bytes(base64.b64decode(os.environ['DEVELOPER_ID_P12_BASE64'],validate=True))
(p/'keychains.json').write_text(json.dumps(shlex.split(subprocess.check_output(['security','list-keychains','-d','user'],text=True))))
(p/'password').write_text(secrets.token_urlsafe(32))
for f in p.iterdir():f.chmod(0o600)
PYCODE
keychain="$signing_dir/release.keychain-db"
password="$(cat "$signing_dir/password")"
# Export the cleanup location before importing credentials so failures are also cleaned up.
printf 'PICELF_SIGNING_DIR=%s\n' "$signing_dir" >> "$GITHUB_ENV"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$signing_dir/certificate.p12" -P "$DEVELOPER_ID_P12_PASSWORD" -A -t cert -f pkcs12 -k "$keychain" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
python3 - <<'PYCODE'
import json,os,pathlib,subprocess
p=pathlib.Path(os.environ['PICELF_SIGNING_DIR'])
subprocess.check_call(['security','list-keychains','-d','user','-s',str(p/'release.keychain-db'),*json.loads((p/'keychains.json').read_text())])
PYCODE
rm "$signing_dir/certificate.p12" "$signing_dir/password"
