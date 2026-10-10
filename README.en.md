# Picelf

A free, open-source capture, scrolling screenshot and image editing app for Mac and iPhone/iPad.

**[Download for Mac](https://github.com/Poseima/picelf-open/releases/latest)** · [Installation](docs/installation.md) · [中文](README.md)

> Installers become available with the first published Release. GitHub Source code archives contain source, not an installable application.

## Features

- Mac window/region capture, scrolling screenshots, background stitching, screen recording and optional microphone audio.
- Annotations, text, stickers, cropping, subject extraction, configurable watermarks, OCR, image translation, desktop pins and canvas.
- iPhone/iPad image/video import, broadcast capture, frame extraction, stitching, editing and export.
- Local Mac/iPad pairing, live annotation, editable text and image return.
- Chinese and English interface; no application account required; all features are free.

Requires **macOS 14+**. Image translation requires **macOS 15+** and may download Apple's language packs on first use. iPhone/iPad source targets **iOS/iPadOS 16+**; build it yourself for now.

## Install

Download `Picelf-<version>-universal.dmg` from [Releases](https://github.com/Poseima/picelf-open/releases), open it and drag **Picelf** into **Applications**. One installer supports Apple Silicon and Intel.

Grant Screen Recording and Accessibility permissions when using capture, and Microphone permission only when recording microphone audio. Update by quitting the app and replacing it with the latest download; settings and history remain. See [installation and permissions](docs/installation.md).

## Build

Install Xcode 16+ with the macOS 15 SDK, Command Line Tools and XcodeGen:

```bash
brew install xcodegen
git clone https://github.com/Poseima/picelf-open.git
cd picelf-open
xcodegen generate
open Picelf.xcodeproj
```

Select the `Picelf` scheme, choose your development team in Signing & Capabilities, and run with Cmd+R. Use signed builds for privacy-permission testing; run `./scripts/ci/check.sh mac-build` for compilation only.

See [iOS device setup](docs/ios-build.md), [contributing](CONTRIBUTING.md), and [releasing](docs/releasing.md).

## Privacy and license

Captures and editing data stay local. Relay sends content only to paired devices on the local network. There are no analytics or advertising services. See [privacy](docs/privacy.md).

[MIT licensed](LICENSE), with [third-party notices](THIRD_PARTY_NOTICES.md). Report problems through [Issues](https://github.com/Poseima/picelf-open/issues).
