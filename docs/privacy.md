# Privacy / 隐私说明

Updated: October 10, 2026 / 更新日期：2026 年 10 月 10 日

Picelf has no application account, analytics, advertising or tracking SDK. The application does not send captures to a hosted processing service.

Picelf 无需应用账号，不集成统计、广告或跟踪 SDK，不把截图发送到服务器处理。

## Captures and local storage / 本地数据

Screenshots, recordings, imported media, OCR results and editing documents are processed and stored on your device. Exports go to your selected location. Settings, history and temporary/cache files use the application container and Application Support directories. Retention follows your configured capture-retention settings; manually exported files are not removed by uninstalling the app.

截图、视频、导入文件、OCR 和编辑文档在设备上处理。临时帧、翻译缓存和历史记录可能保存在本地；应用按配置执行保留期限。导出的文件由你自行管理。

## Local relay / 本地联动

When you enable Mac/iPad relay and confirm pairing, the app discovers peers and transfers selected images, text and editing state over the local network. This intentionally shares content with the paired device. It does not use a hosted relay service. Stop the connection to end synchronization.

开启联动并确认配对后，选择的图片、文字和编辑状态会通过本地网络传给配对设备。断开连接即可停止同步。

## Translation and network / 翻译与网络

OCR uses Apple's Vision framework. Image translation on macOS 15+ uses Apple's Translation framework; the system may contact Apple to download language packs. Translation runs on device after the required packs are available. Browser-assisted capture can connect to a locally enabled Chrome debugging interface to obtain page-layout hints.

OCR 使用系统 Vision；翻译使用系统 Translation，首次使用可能由系统联网下载语言包。浏览器辅助截图可连接本机启用的 Chrome 调试接口取得布局提示。打开应用中的文档链接时，你的浏览器会连接 GitHub；其隐私政策另行适用。

Opening documentation/download links connects your browser to GitHub, subject to GitHub's privacy policy. Capture and editing do not require an application service account.

## Permissions / 权限

Screen Recording is used during capture/recording you initiate. Accessibility supports scrolling and window interactions. Microphone is optional and used only if enabled for recording. iOS photo access is requested for import/export; Local Network is used for device pairing and relay.

屏幕录制用于你启动的截屏或录屏；辅助功能用于滚动与窗口操作；麦克风音频可选；照片权限用于导入导出；本地网络权限用于联动。

Do not include private screenshots, recordings or logs in public issue reports. For concerns, use [GitHub Issues](https://github.com/Poseima/picelf-open/issues) without attaching personal data.
