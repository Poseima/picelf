#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${VERSION:?Set VERSION to a v-prefixed semantic version}"
: "${DEVELOPER_ID_IDENTITY:?Missing Developer ID identity}"
: "${APPLE_TEAM_ID:?Missing Apple team ID}"
if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  notary_mode=apple-id
  : "${PICELF_SIGNING_DIR:?Import the release certificate before notarization}"
  [[ -f "$PICELF_SIGNING_DIR/release.keychain-db" ]] || { echo 'Missing temporary release keychain' >&2; exit 1; }
elif [[ -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" && -n "${APP_STORE_CONNECT_PRIVATE_KEY:-}" ]]; then
  notary_mode=api-key
else
  echo 'Configure APPLE_ID and APPLE_APP_SPECIFIC_PASSWORD, or all three App Store Connect API key secrets' >&2
  exit 1
fi
: "${GITHUB_REPOSITORY:?Missing repository}"
: "${GH_TOKEN:?Missing release token}"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected vMAJOR.MINOR.PATCH' >&2; exit 1; }
[[ "$DEVELOPER_ID_IDENTITY" == 'Developer ID Application:'* ]] || { echo 'Developer ID Application identity required' >&2; exit 1; }
version="${VERSION#v}"
notes="docs/releases/$version.md"
[[ -f "$notes" ]] || { echo "Missing bilingual release notes $notes" >&2; exit 1; }
# Published releases must never be silently replaced during a rerun.
if gh release view "$VERSION" --repo "$GITHUB_REPOSITORY" --json isDraft --jq '.isDraft' > .build-release-status 2>/dev/null; then
  [[ "$(cat .build-release-status)" == true ]] || { rm .build-release-status; echo 'Refusing to modify a published release' >&2; exit 1; }
fi
rm -f .build-release-status
python3 scripts/ci/verify-distribution.py
xcodegen generate
archive_path="$PWD/.build/release/PicelfOpen.xcarchive"
[[ ! -e "$archive_path" ]] || { echo 'Release archive already exists; use a clean workspace' >&2; exit 1; }
xcodebuild archive -project Picelf.xcodeproj -scheme Picelf -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive_path" \
  -clonedSourcePackagesDirPath .build/packages ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
app_path="$archive_path/Products/Applications/Picelf.app"
plist="$app_path/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$version" ]] || { echo 'Release tag and app version disagree' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == com.picelf.open.app ]] || exit 1
xcrun lipo "$app_path/Contents/MacOS/Picelf" -verify_arch arm64 x86_64
for notice in LICENSE licenses/KeyboardShortcuts.txt licenses/SnapshotTesting.txt; do
  [[ -s "$app_path/Contents/Resources/$notice" ]] || { echo "Missing bundled license: $notice" >&2; exit 1; }
done
codesign --verify --deep --strict --verbose=2 "$app_path"
signing_details="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
[[ "$signing_details" == *'Authority=Developer ID Application:'* && "$signing_details" == *"TeamIdentifier=$APPLE_TEAM_ID"* && "$signing_details" == *'(runtime)'* ]] || { echo 'Invalid release signing identity/runtime' >&2; exit 1; }
key_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/picelf-notary.XXXXXX")"
trap 'rm -rf "$key_dir"' EXIT
if [[ "$notary_mode" == apple-id ]]; then
  # Store once in the temporary signing keychain; cleanup-signing.sh removes it.
  xcrun notarytool store-credentials picelf-release \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --keychain "$PICELF_SIGNING_DIR/release.keychain-db" >/dev/null
  notary_args=(--keychain-profile picelf-release --keychain "$PICELF_SIGNING_DIR/release.keychain-db" --wait)
else
  key_file="$key_dir/AuthKey.p8"
  printf '%s' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$key_file"
  chmod 600 "$key_file"
  notary_args=(--key "$key_file" --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID" --wait)
fi
mkdir -p dist
zip_path="$key_dir/PicelfOpen.zip"
ditto -c -k --keepParent "$app_path" "$zip_path"
xcrun notarytool submit "$zip_path" "${notary_args[@]}"
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
dmg_path="dist/Picelf-$version-universal.dmg"
./scripts/release/package-dmg.sh "$app_path" "$dmg_path"
codesign --sign "$DEVELOPER_ID_IDENTITY" --timestamp "$dmg_path"
xcrun notarytool submit "$dmg_path" "${notary_args[@]}"
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
codesign --verify --strict "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
(cd dist && shasum -a 256 "$(basename "$dmg_path")" > SHA256SUMS.txt)
if ! gh release view "$VERSION" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  gh release create "$VERSION" --repo "$GITHUB_REPOSITORY" --verify-tag --draft --title "Picelf $version" --notes-file "$notes"
fi
[[ "$(gh release view "$VERSION" --repo "$GITHUB_REPOSITORY" --json isDraft --jq '.isDraft')" == true ]] || { echo 'Refusing to upload to a published release' >&2; exit 1; }
gh release upload "$VERSION" "$dmg_path" dist/SHA256SUMS.txt --repo "$GITHUB_REPOSITORY" --clobber
