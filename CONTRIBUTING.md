# Contributing / 参与贡献

欢迎通过 Issues 报告问题，通过 Pull Request 提交改进。请描述复现步骤、系统版本和处理结果；分享截图或录屏前请自行移除个人信息。

Welcome bug reports and pull requests. Include reproduction steps, OS version and expected/actual results. Remove personal information from attachments.

## Build and test

Install Xcode 16+ and XcodeGen, then run `xcodegen generate`. The generated Xcode project is ignored; edit `project.yml` instead. Signing is configured with your own team in Xcode or build arguments.

```bash
./scripts/ci/check.sh mac-build
./scripts/ci/check.sh mac-test
./scripts/ci/check.sh ios-build
./scripts/ci/check.sh ios-test
```

The mobile app and broadcast extension target iPad only; `ios-test` selects an available iPad simulator by default. For a specific iPad simulator set `IOS_TEST_DESTINATION='platform=iOS Simulator,id=<device-id>'`. CI compilation/testing disables signing with all three flags: `CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`. These artifacts are not installers.

Live desktop tests are opt-in: set `PICELF_RUN_LIVE_TESTS=1`, grant Screen Recording and Accessibility to a signed test host, and run the selected test from Xcode. Such tests can open/close Preview or Chrome and change scroll positions. Generate anonymous PDF content using `swift scripts/dev/generate-test-pdf.swift`, or supply `PICELF_TEST_PDF_PATH`. Optional video/cache/reference fixtures are provided through the environment variables documented in their tests; they are not committed.

Use synthetic fixtures for ordinary tests. Keep Chinese and English text aligned, preserve local data and existing relay compatibility, and include regression coverage when changing capture or rendering behavior. No analytics, ads, accounts or feature-unlock mechanisms should be introduced.

Release checks and manual acceptance are listed in [docs/releasing.md](docs/releasing.md).

## Workbench clipboard and Downloads checks

Workbench clipboard tests use unique pasteboards, isolated preferences and temporary export directories. Run `scripts/ci/check.sh mac-test` for pixel, alpha, paste ordering, PNG/JPEG, collision, cleanup and update-installation protection checks.

`WorkbenchUITests` requires a signed Debug test scheme with `PICELF_RUN_LIVE_TESTS=1`. It launches `--uitest-open-workbench` with isolated preferences/history and checks real Command-C/Command-V, native search text operations, external image imports, context-menu export targets and Chinese/English feedback. Live tests write synthetic exports to Downloads and remove their own exported fixture files. Do not replace an installed stable release with the test build; use a separate Bundle ID for local manual validation.

`DesktopCaptureTests` uses injected window/display snapshots and synthetic screen pixels; it does not capture the real desktop or write to the system clipboard. `DesktopCaptureLiveTests` additionally requires `PICELF_RUN_DESKTOP_CAPTURE_TESTS=1`, a developer-signed Debug test host, and existing Screen Recording access. It briefly hides and restores applications, tests an empty desktop and a minimized fixture window, checks a visible fixture window, and moves/restores the pointer for multi-display checks (skipped when only one display is connected). It verifies PNG dimensions and pixels in memory without requesting permissions or saving desktop images. In Xcode enable both environment variables on the test action and run only this suite.
