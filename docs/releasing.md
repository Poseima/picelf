# Releasing Picelf

Official releases contain a universal Mac DMG and SHA-256 checksums. iOS is source-only. The first version is `1.0.0`.

## Credentials

Create a **Developer ID Application** certificate in your Apple Developer account. An Apple Development certificate is suitable for local testing, not official distribution.

Configure the GitHub Actions environment named `release` with these secrets:

- `DEVELOPER_ID_P12_BASE64`: base64-encoded Developer ID Application certificate and private key.
- `DEVELOPER_ID_P12_PASSWORD`: export password.
- `DEVELOPER_ID_IDENTITY`: exact signing identity, beginning with `Developer ID Application:`.
- `APPLE_TEAM_ID`: Apple development team identifier.

For notarization, configure **one** of these authentication methods:

- `APPLE_ID` and `APPLE_APP_SPECIFIC_PASSWORD`: your developer Apple Account and an app-specific password generated at [account.apple.com](https://account.apple.com/) under Sign-In and Security → App-Specific Passwords. Use a dedicated label such as `Picelf GitHub Release`. Never use your primary Apple Account password. This method does not require generating an App Store Connect API key.
- Alternatively, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_PRIVATE_KEY`: a team App Store Connect API key supporting notarization; the private key is the `.p8` contents.

If both methods are configured, the Apple Account method takes precedence. Apple may still require account verification before allowing notarization; validate the credentials before releasing. See [Apple's notarization authentication documentation](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).

Do not commit credentials. The workflow imports the certificate into a temporary keychain, stores notarization credentials in that keychain or in runner temporary storage, and removes them at the end. Fork PRs receive no publishing secrets. Changing the primary Apple Account password revokes its app-specific passwords; update the release secret if this happens. No unsigned fallback is published when credentials or notarization are missing.

With Apple Account authentication configured, manually run **Check release credentials** from the Actions tab on `main`. It imports the certificate, checks the signing identity and validates access to notarization history without displaying history, submitting software or creating a release. A successful check verifies authentication; the candidate installer must still pass notarization and installation acceptance.

## Release procedure

1. Update all application/extension `MARKETING_VERSION` values and increment build numbers in `project.yml`. Prepare bilingual notes under `docs/releases/<version>.md`.
2. Run CI build/tests and the manual checks below. Have the user test and explicitly confirm changes before committing/pushing.
3. Commit, push and tag that reviewed commit as `v<version>`. Push the tag.
4. The workflow builds both architectures, signs the app, notarizes and staples it, packages/notarizes/staples the DMG, validates Gatekeeper and uploads the DMG and checksums to a **draft** GitHub Release.
5. Download that exact candidate DMG from the draft, verify its checksum and install/open it on a clean test account. Publish the draft only after acceptance.

If a job fails, fix the cause and rerun the workflow; it never substitutes an unnotarized installer. The script checks version/tag agreement and overwrites only assets of an existing draft, never a published release.

## Manual acceptance

- Browser download → DMG → drag to Applications → first launch without bypassing Gatekeeper.
- Apple Silicon and Intel binaries present; signed app and DMG notarization tickets valid. Check launch on both hardware types before first public release.
- Screen Recording and Accessibility authorization; window/region capture, auto scrolling, workbench and saved history.
- Long screenshot inspected for repeated/missing content and seams; compare synthetic source and stitched output.
- Editing, pins/canvas, stickers, user watermark, OCR; translation on macOS 15+ after language-pack preparation.
- Recording with/without microphone, pause/stop and playable export.
- Real iPad pairing, live image/text annotations and returned image; real iOS broadcast capture and shared App Group delivery.
- Chinese/English settings; quit/reinstall/upgrade retains data; usage continues offline and after 7 days.

## Internal preview package

For a locally built signed Debug app:

```bash
./scripts/release/package-dmg.sh '/path/to/Picelf.app' dist/Picelf-preview.dmg
```

This creates an **internal preview**, not a notarized official release. Do not upload it as a formal download. Use it for local smoke testing until release credentials are ready.
