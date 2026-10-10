# iPhone / iPad build guide

iOS/iPadOS 16+ source is included. There is currently no hosted iOS installer, App Store or TestFlight channel.

iPhone/iPad 目前提供完整源码，需要使用 Xcode 自行构建。先安装 Xcode 16+ 和 XcodeGen，再运行 `xcodegen generate`，打开 `Picelf.xcodeproj` 并选择 `PicelfIOS` scheme。

## Simulator

Run `./scripts/ci/check.sh ios-build` for compilation. In Xcode choose an iPhone or iPad simulator and run. Test image/video import and relay UI there; Control Center broadcast recording and final local-network validation require physical devices.

## Physical device / 真机

1. Connect the device, trust the Mac and enable Developer Mode when requested.
2. Select your team for **both PicelfIOS and PicelfBroadcastUpload** in Signing & Capabilities. A membership supporting App Groups/provisioning is required for cross-app broadcast capture.
3. Register unique bundle identifiers if the defaults are unavailable to your account. Change the corresponding `PRODUCT_BUNDLE_IDENTIFIER` values in `project.yml` and regenerate the project.
4. Register one App Group and enable it for both targets. Default: `group.com.picelf.open.shared`. If you change it, update **both entitlement files**, `BroadcastFrameRelay.appGroupID` and `SampleHandler.Constants.appGroupID` to the same value.
5. If the extension bundle identifier changes, update `BroadcastPickerView.preferredExtension`. Default: `com.picelf.open.ios.broadcast-upload`.
6. Regenerate the project, select the device and run. Verify provisioning, then test Control Center → Screen Recording → Picelf. Grant Photos and Local Network permissions when needed.

主应用和扩展必须使用同一团队、同一个 App Group，广播选择器必须匹配扩展 Bundle ID。模拟器构建不需要官方维护者的签名证书。

## Relay

Run Picelf on the Mac and iPad on the same local network, open Relay Canvas and pair using the displayed code. Test image transfer, live drawing/text and return/export. Relay service identifiers and packet format are shared across both app targets.
