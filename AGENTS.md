# Picelf

Swift 5.9 application with macOS 14+ and iOS 16+ targets. It appears in the Mac Dock and menu bar. Apple image translation requires macOS 15+.

## Build

`project.yml` is the source of truth. Run `xcodegen generate` after adding/removing files or changing build settings. Keep the `Picelf` and `PicelfIOS` target names and the `Picelf` Swift module name: tests import that module directly. PicelfCore is compiled into each application, not a separate module.

Use `scripts/ci/check.sh` for unsigned build and deterministic test checks. For permission-sensitive runs, use Xcode with your own development team and a signed Debug build. Do not grant system permissions to unsigned CLI outputs.

## Architecture

- App layers: `Sources/Picelf` (Mac), `Sources/PicelfIOS` (iOS), `Sources/PicelfBroadcastUpload` (iOS extension).
- Shared capture models, stitching, OCR, translation, preferences and relay live in `Sources/PicelfCore`.
- StitchingCoordinator uses incremental SSD template matching and PixelCanvas compositing for both preview and final results. Keep changes focused; verify duplication, missing content and seams with synthetic fixtures and signed live capture.
- Relay discovery/service identifiers and wire format must stay compatible; main iOS app and extension App Group values must agree.

## Conventions

- All features are available without an account or time limit. Keep Chinese and English strings aligned.
- Preserve third-party license notices in application resources and the repository.
- Use `NSPanel.orderOut(nil)` rather than `close()` in teardown to avoid autorelease crashes.
- The newest WorkbenchStore job is `.first`; jobs are inserted at index zero.
- Live desktop tests require explicit opt-in and can control Preview/Chrome; deterministic CI tests must not require private data or service accounts.
- Do not commit or push until tests pass and the user has tested and explicitly confirmed the changes.

See CONTRIBUTING.md and docs/releasing.md for validation and distribution.
