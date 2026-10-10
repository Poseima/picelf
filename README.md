# Picelf

免费的开源截图、长图拼接和编辑工具，支持 Mac 与 iPhone/iPad。

**[下载 Mac 版](https://github.com/Poseima/picelf-open/releases/latest)** · [安装与权限](docs/installation.md) · [English](README.en.md)

> 正式安装包将在首个 Release 发布后提供。GitHub 的 Source code 压缩包是源码，不能直接安装。

## 功能

- Mac：窗口/区域截图、滚动长截图、后台拼接工作台、屏幕录制与可选麦克风音频。
- 图片编辑：标注、文本、贴纸、裁剪、抠图、可配置水印、OCR、图片翻译、桌面贴图与画布。
- iPhone/iPad：导入图片与视频、广播录屏提帧、拼接、编辑及导出。
- Mac/iPad：本地网络配对、实时接力标注、可编辑文字与图片回传。
- 中英文界面；无需应用账号，全部功能免费使用。

Mac 需要 **macOS 14+**；图片翻译需要 **macOS 15+**，首次使用可能需要下载系统语言包。iPhone/iPad 源码支持 **iOS/iPadOS 16+**，目前需要自行构建安装。

## 下载与安装

在 [Releases](https://github.com/Poseima/picelf-open/releases) 下载 `Picelf-<版本>-universal.dmg`，打开后将 **Picelf** 拖入 **Applications**。同一个安装包支持 Apple Silicon 和 Intel。

根据实际使用授予屏幕录制、辅助功能及可选麦克风权限。新版本从同一下载入口获取，退出应用后覆盖安装；设置与历史记录保留。详见[安装说明](docs/installation.md)。

## 从源码构建

需要 Xcode 16+（包含 macOS 15 SDK）、Command Line Tools 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
git clone https://github.com/Poseima/picelf-open.git
cd picelf-open
xcodegen generate
open Picelf.xcodeproj
```

选择 `Picelf` scheme，在 Signing & Capabilities 设置自己的开发团队，再按 Cmd+R。签名构建适合稳定测试系统权限。纯编译检查可以运行 `./scripts/ci/check.sh mac-build`。

iPhone/iPad 真机、广播扩展和 App Group 配置详见 [iOS 构建指南](docs/ios-build.md)。测试和发布见 [贡献指南](CONTRIBUTING.md) 与 [发布指南](docs/releasing.md)。

## 隐私与许可

截图、视频和编辑数据保存在本地；跨设备联动仅在配对设备间传输。应用不集成分析或广告服务。详见[隐私说明](docs/privacy.md)。

项目采用 [MIT](LICENSE) 许可，第三方声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。问题和建议欢迎提交到 [Issues](https://github.com/Poseima/picelf-open/issues)。
