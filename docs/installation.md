# 安装与权限 / Installation and permissions

## 安装 / Install

1. 从 [最新 Release](https://github.com/Poseima/picelf-open/releases/latest) 下载 `Picelf-<版本>-universal.dmg`。首个正式 Release 发布前，此入口尚无安装包。
2. 打开 DMG，将 **Picelf** 拖到 **Applications**，从 Applications 启动。
3. 首次打开可能出现系统的“从互联网下载”确认。官方正式安装包使用 Developer ID 签名及 Apple 公证。

Download the universal DMG from the latest Release, drag Picelf to Applications and launch it there. Official releases are Developer ID signed and Apple notarized. They support both Apple Silicon and Intel on macOS 14+.

## 按需授权 / Permissions

- **屏幕录制 / Screen Recording**：截取窗口、区域和录屏时需要。在 System Settings → Privacy & Security → Screen Recording（部分系统显示 Screen & System Audio Recording）启用 Picelf，按系统提示重启应用。
- **辅助功能 / Accessibility**：自动滚动及相关窗口操作需要。允许后重新尝试截图。
- **麦克风 / Microphone**：只有开启麦克风音频时需要；拒绝后仍可不带麦克风录制。
- **本地网络 / Local Network**：Mac/iPad 联动时需要。两端连接同一网络，使用配对码确认设备。
- **照片 / Photos（iOS）**：导入照片或保存结果时按需请求。

Grant only the permissions needed for your selected feature. If capture is blank, check Screen Recording first. If automatic scrolling fails, check Accessibility. If pairing fails, check both devices' Local Network permission and network connection.

## 翻译 / Translation

需要 macOS 15+；首次使用某个语言组合可能由系统请求下载语言包。已安装语言包后支持设备端翻译。macOS 14 的其他功能继续可用。

Image translation needs macOS 15+ and may request language-pack downloads. Other features remain available on macOS 14.

## 更新与卸载 / Update and uninstall

正式版本可在应用菜单、菜单栏右键菜单或「设置 → 通用 → 软件更新」中检查更新。默认每天自动检查一次，由你确认下载和安装，随后应用替换并重启。录屏、捕获、工作台任务或编辑尚未完成时，请先完成工作，再点击继续更新。

不含更新器的旧版需要先退出应用，下载新 DMG，覆盖 Applications 中的 Picelf 一次；无需提前删除旧 App。之后即可在应用内更新。更新失败时仍可通过 Release 下载页面覆盖安装。保留应用标识与签名团队的官方更新会继续使用现有设置和历史记录，无需重新导入。

Use Check for Updates in the app menu, status menu, or Settings → General → Software updates. Official builds check daily; downloading and installing require your choice. Finish capture, recording, relay, pending tasks and editing before continuing installation. Legacy builds without an updater need one manual overwrite installation; you do not need to delete the old app first. Release downloads remain available if updating fails. To uninstall, quit and move the app to Trash. Captures exported to your chosen folders remain yours. Application data is stored under the app's container/Application Support directory for `com.picelf.open.app`; delete it separately only if you want to remove history and settings.

自行构建的版本可能因签名变化需要重新授予权限。项目不提供关闭 Gatekeeper 或全局移除系统安全检查的安装步骤。
