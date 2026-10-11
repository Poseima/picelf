# Releasing Picelf

Official releases contain a universal Mac DMG, an Ed25519-signed `appcast.xml`, and SHA-256 checksums for both files. iOS is source-only. The first published release with in-app updates is `1.0.2` (build 3); the earlier `1.0.0` candidate predates the updater.

## Credentials

Create a **Developer ID Application** certificate in your Apple Developer account. An Apple Development certificate is suitable for local testing, not official distribution.

Configure the GitHub Actions environment named `release` with these secrets:

- `DEVELOPER_ID_P12_BASE64`: base64-encoded Developer ID Application certificate and private key.
- `DEVELOPER_ID_P12_PASSWORD`: export password.
- `DEVELOPER_ID_IDENTITY`: exact signing identity, beginning with `Developer ID Application:`.
- `APPLE_TEAM_ID`: Apple development team identifier.
- `SPARKLE_PRIVATE_KEY`: the base64-encoded 32-byte Ed25519 private seed exported by Sparkle `generate_keys`; do not confuse this with the Apple signing certificate.

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
4. The workflow archives both architectures and exports the app with Developer ID signing, including Sparkle installation helpers. It notarizes/staples the app and DMG, validates Gatekeeper, then generates and verifies the signed update feed from the final DMG. It uploads the DMG, feed and checksums to a **draft** GitHub Release.
5. Download that exact candidate DMG and feed from the draft, verify their checksums and complete installation/upgrade acceptance on a clean test account. Publish the draft only after acceptance and explicitly mark it **Latest**. Never mark a preview or prerelease as Latest.

If a job fails, fix the cause and rerun the workflow; it never substitutes an unnotarized installer. The script checks version/tag agreement and overwrites only assets of an existing draft, never a published release.

## Application updates

Sparkle **2.10.0** is pinned in `project.yml` for the Mac target only. The fixed HTTPS feed is:

`https://github.com/Poseima/picelf-open/releases/latest/download/appcast.xml`

Every stable release must include that asset. Its enclosure points to that release's exact versioned DMG, never a latest-DMG redirect. Drafts and prereleases are not offered by this stable feed. The first integration supports full DMG updates only. Signed feeds, verification before extraction, and user-confirmed installation are required. The native Sparkle dialogs follow system language; Picelf's settings and menus follow the selected app language.

Generate a key once using the pinned tools in `.build/packages/artifacts/sparkle/Sparkle/bin`:

```bash
generate_keys --account com.picelf.open
generate_keys --account com.picelf.open -p
```

Embed the printed **public** key as `SUPublicEDKey` in the Mac Info.plist. Export the private key with `generate_keys --account com.picelf.open -x <private-backup-path>` to a protected location outside the repository (directory mode 700, file mode 600). Back it up securely and set `SPARKLE_PRIVATE_KEY` in the GitHub `release` environment using stdin/file input; never print the private key, pass it as a command-line argument, or commit it. Do not regenerate keys per release. The release script verifies that the secret matches the candidate's public key. Key rotation requires a separately reviewed migration.

Increment `CURRENT_PROJECT_VERSION` as a positive integer for every official build. The workflow rejects a version at or below any published stable version and a build number at or below the previous official app (inspected from its signed DMG, including legacy versions without Sparkle). Published assets must never be replaced. Recover from a defective release by issuing a higher version/build containing the correction or known-good code; automatic downgrades are not supported.

Ordinary Debug builds and XCTest hosts never start the updater. For a **signed** Debug build, an explicitly enabled test run can use an independent HTTPS feed:

```bash
PICELF_RUN_LIVE_UPDATE_TESTS=1 PICELF_UPDATE_TEST_FEED_URL=https://your-test-host.example/appcast.xml /path/to/Picelf.app/Contents/MacOS/Picelf
```

This override is ignored by Release builds. The test feed and update archive must pass the same signing checks as production. Use a dedicated account/installation and an isolated test feed for two notarized candidates with increasing build numbers; never publish high test build numbers into the stable feed. Do not disable TLS, Gatekeeper, signing, or sandbox protections for testing.

Upgrade acceptance must cover automatic/manual checks, skip/remind, offline/error/cancel paths, corrupted feed/archive rejection, read-only installation location, and preserved settings, history and permissions after replacement/relaunch. Test capture, recording, workbench jobs, live relay, editor/canvas windows and work starting during download: updating must not terminate unfinished work, and becoming idle must not resume installation without another click. Also verify minimized editor/canvas windows block installation.

The updater card exposes a Release download link if in-app updating fails. A version that predates Sparkle needs one manual overwrite installation; subsequent versions update in-app. Automatic checks default to daily, automatic downloads/installation are disabled, and system profiling is disabled.

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
