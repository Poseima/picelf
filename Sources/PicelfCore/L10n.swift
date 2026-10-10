import Foundation

/// Centralized bilingual string table for Picelf (English / Chinese).
///
/// Usage: `Text(L10n.save)` — returns the localized string based on user preference.
/// Language supports: system / en / zh. Non-zh system locales fallback to English.
enum L10n {
    static var zh: Bool {
        switch AppLanguageOption.normalized(raw: AppPreferences.shared.appLanguage) {
        case .zh:
            return true
        case .en:
            return false
        case .system:
            guard let preferred = Locale.preferredLanguages.first?.lowercased() else {
                return false
            }
            return preferred.hasPrefix("zh")
        }
    }

    /// Keeps small, screen-specific copy bilingual without forcing every label
    /// into the shared table. Prefer named properties for text reused in more
    /// than one place.
    static func localized(_ chinese: String, _ english: String) -> String {
        zh ? chinese : english
    }

    // MARK: - Capture Toolbar

    static var scroll: String { zh ? "滚动截图" : "Scroll" }
    static var snap: String { zh ? "截图" : "Snap" }
    static var recording: String { zh ? "录制中" : "Recording" }
    static var done: String { zh ? "完成" : "Done" }
    static var stitchingLabel: String { zh ? "拼接中" : "Stitching" }
    static var cancel: String { zh ? "取消" : "Cancel" }
    static var dragHint: String { zh ? "拖动选择区域" : "Drag to select an area" }

    // MARK: - Editor Toolbar

    static var save: String { zh ? "保存" : "Save" }
    static var copy: String { zh ? "复制" : "Copy" }
    static var share: String { zh ? "分享" : "Share" }
    static var ocr: String { "OCR" }
    static var translate: String { zh ? "翻译" : "Translate" }
    static var exportTranslatedCopy: String { zh ? "导出翻译副本" : "Export Translated Copy" }
    static var extractSubject: String { zh ? "提取主体" : "Extract Subject" }
    static var extractingSubject: String { zh ? "提取中…" : "Extracting…" }
    static var removeBackground: String { zh ? "去除背景" : "Remove Background" }
    static var open: String { zh ? "打开" : "Open" }
    static var reveal: String { zh ? "在 Finder 中显示" : "Reveal" }
    static var retry: String { zh ? "重试" : "Retry" }
    static var remove: String { zh ? "移除" : "Remove" }
    static var removeFromPinLibrary: String { zh ? "移出贴图库" : "Remove from Pin Library" }
    static var custom: String { zh ? "自定义" : "Custom" }
    static var source: String { zh ? "来源" : "Source" }
    static var clipboard: String { zh ? "剪贴板" : "Clipboard" }
    static var droppedImage: String { zh ? "拖入图片" : "Dropped Image" }

    // MARK: - Inspector

    static var inspector: String { zh ? "检查器" : "Inspector" }
    static var summary: String { zh ? "概要" : "Summary" }
    static var tool: String { zh ? "工具" : "Tool" }
    static var annotations: String { zh ? "标注" : "Annotations" }
    static var image: String { zh ? "图像" : "Image" }
    static var style: String { zh ? "样式" : "Style" }
    static var stroke: String { zh ? "描边" : "Stroke" }
    static var fill: String { zh ? "填充" : "Fill" }
    static var line: String { zh ? "线宽" : "Line" }
    static var textSection: String { zh ? "文本" : "Text" }
    static var size: String { zh ? "大小" : "Size" }
    static var width: String { zh ? "宽度" : "Width" }
    static var replace: String { zh ? "替换" : "Replace" }
    static var choose: String { zh ? "选择" : "Choose" }
    static var mosaicSection: String { zh ? "马赛克" : "Mosaic" }
    static var block: String { zh ? "颗粒" : "Block" }
    static var export: String { zh ? "导出" : "Export" }
    static var quality: String { zh ? "质量" : "Quality" }
    static var translation: String { zh ? "翻译" : "Translation" }
    static var sourceLanguage: String { zh ? "源语言" : "Source" }
    static var targetLanguage: String { zh ? "目标语言" : "Target" }
    static var overlayMode: String { zh ? "覆盖方式" : "Overlay" }
    static var translationOverlayOff: String { zh ? "关闭" : "Off" }
    static var translationOverlayHover: String { zh ? "悬停" : "Hover" }
    static var translationOverlayReplace: String { zh ? "替换" : "Replace" }
    static var copyTranslation: String { zh ? "复制翻译" : "Copy Translation" }
    static var translationReady: String { zh ? "翻译已就绪" : "Translation ready" }
    static var translationRunningOCR: String { zh ? "正在识别文字..." : "Recognizing text..." }
    static var translating: String { zh ? "正在翻译..." : "Translating..." }
    static var translationUnsupportedSystem: String {
        zh ? "仅支持 macOS 15 及以上的本机离线翻译。" : "On-device translation requires macOS 15 or later."
    }
    static var translationUnsupportedPair: String {
        zh ? "当前语言组合暂不支持本机翻译。" : "This language pair is not available for on-device translation."
    }
    static var translationNoText: String { zh ? "这张图片里没有可翻译的文字。" : "No translatable text was found in this image." }
    static var translationFailed: String { zh ? "翻译失败，请重试。" : "Translation failed. Try again." }
    static var translationRawOCR: String { zh ? "原始 OCR" : "Raw OCR" }
    static var translationPreviewHint: String {
        zh ? "悬停查看译文，或切换到替换模式覆盖原文。" : "Hover for translated bubbles or switch to Replace to overlay the image."
    }
    static var textRecognition: String { zh ? "文字识别" : "Text Recognition" }
    static var recognizing: String { zh ? "识别中..." : "Recognizing..." }
    static var copyAll: String { zh ? "全部复制" : "Copy All" }
    static var recognizeText: String { zh ? "识别文字" : "Recognize Text" }
    static var layers: String { zh ? "图层" : "Layers" }

    // MARK: - Sticker Library

    static var stickerLibrary: String { zh ? "贴图库" : "Sticker Library" }
    static var stickerAll: String { zh ? "全部" : "All" }
    static var stickerFavorites: String { zh ? "收藏" : "Favorites" }
    static var stickerRecents: String { zh ? "最近" : "Recents" }
    static var stickerEmoji: String { zh ? "表情" : "Emoji" }
    static var stickerImport: String { zh ? "导入" : "Import" }
    static var stickerNoItems: String { zh ? "暂无贴图" : "No stickers yet" }
    static var stickerImportPrompt: String { zh ? "点击 + 或拖入图片" : "Click + or drop images" }
    static var stickerDelete: String { zh ? "删除" : "Delete" }
    static var stickerFavorite: String { zh ? "收藏" : "Favorite" }
    static var stickerUnfavorite: String { zh ? "取消收藏" : "Unfavorite" }
    static var stickerOpacity: String { zh ? "透明度" : "Opacity" }
    static var stickerShadow: String { zh ? "阴影" : "Shadow" }
    static var stickerFlipH: String { zh ? "水平翻转" : "Flip H" }
    static var stickerFlipV: String { zh ? "垂直翻转" : "Flip V" }
    static var stickerBringForward: String { zh ? "上移" : "Forward" }
    static var stickerSendBack: String { zh ? "下移" : "Back" }
    static var stickerDuplicate: String { zh ? "复制" : "Duplicate" }

    // MARK: - Layer Panel

    static var layerRectangle: String { zh ? "矩形" : "Rectangle" }
    static var layerEllipse: String { zh ? "椭圆" : "Ellipse" }
    static var layerLine: String { zh ? "直线" : "Line" }
    static var layerArrow: String { zh ? "箭头" : "Arrow" }
    static var layerPencil: String { zh ? "铅笔" : "Pencil" }
    static var layerMosaic: String { zh ? "马赛克" : "Mosaic" }
    static var layerText: String { zh ? "文本" : "Text" }
    static var layerStep: String { zh ? "步骤" : "Step" }
    static var layerHighlight: String { zh ? "高亮" : "Highlight" }
    static var layerSticker: String { zh ? "贴图" : "Sticker" }

    // MARK: - Status Bar

    static func zoom(_ pct: Int) -> String { zh ? "缩放 \(pct)%" : "Zoom \(pct)%" }
    static func canvas(_ w: Int, _ h: Int) -> String { zh ? "画布 \(w) × \(h)" : "Canvas \(w) × \(h)" }
    static func selected(_ n: Int) -> String { zh ? "已选 \(n)" : "Selected \(n)" }

    // MARK: - Preferences

    static var general: String { zh ? "通用" : "General" }
    static var shortcuts: String { zh ? "快捷键" : "Shortcuts" }
    static var capture: String { zh ? "捕获" : "Capture" }
    static var translationTab: String { zh ? "翻译" : "Translation" }
    static var language: String { zh ? "语言:" : "Language:" }
    static var languageSystem: String { zh ? "跟随系统" : "System" }
    static var launchAtLogin: String { zh ? "开机启动" : "Launch at login" }
    static var defaultSaveLocation: String { zh ? "默认保存位置:" : "Default save location:" }
    static var askEachTime: String { zh ? "每次询问" : "Ask each time" }
    static var chooseFolder: String { zh ? "选择..." : "Choose..." }
    static var defaultFormat: String { zh ? "默认格式:" : "Default format:" }
    static var jpegQuality: String { zh ? "JPEG 质量:" : "JPEG quality:" }
    static var startCapture: String { zh ? "开始捕获" : "Start Capture" }
    static var notSet: String { zh ? "未设置" : "Not Set" }
    static func startCaptureWithShortcut(_ shortcut: String) -> String {
        zh ? "开始捕获（\(shortcut)）" : "Start Capture (\(shortcut))"
    }
    static var enterSelectionMode: String { zh ? "进入窗口选取模式" : "Enter window selection mode" }
    static var sendToIPad: String { zh ? "发送图片到 iPad" : "Send Image to iPad" }
    static var sendToIPadDescription: String {
        zh ? "将剪贴板图片发送到已配对 iPad 的接力画板" : "Send the clipboard image to the paired iPad canvas"
    }
    static var resetToDefaults: String { zh ? "恢复默认" : "Reset to Defaults" }
    static var autoSnap: String { zh ? "自动吸附窗口" : "Auto-snap to windows" }
    static var cacheFrames: String { zh ? "缓存原始帧" : "Cache raw frames" }
    static var captureRetention: String { zh ? "自动过期" : "Auto-expire" }
    static var retentionSeconds: String { zh ? "秒" : "Seconds" }
    static var retentionHours: String { zh ? "小时" : "Hours" }
    static var retentionDays: String { zh ? "天" : "Days" }
    static var captureRetentionHint: String {
        zh ? "默认 10 天。置顶/保留的捕获不会自动删除。"
           : "Default is 10 days. Kept captures never auto-delete."
    }
    static var translationDefaultTarget: String { zh ? "默认目标语言" : "Default target" }
    static var translationTargetFollowApp: String { zh ? "跟随应用语言" : "Follow App Language" }
    static var translationTargetLastUsed: String { zh ? "上次使用" : "Last Used" }
    static var translationDefaultOverlay: String { zh ? "默认覆盖方式" : "Default overlay" }
    static var translationAutoRunFromSnapEditLabel: String {
        zh ? "截图编辑后自动翻译" : "Translate after quick edit"
    }
    static var translationExportFormat: String { zh ? "翻译副本格式" : "Translated copy format" }
    static var translationExportMatchSource: String { zh ? "跟随原图" : "Match Original" }
    static var translationPrivacyNote: String {
        zh ? "翻译仅使用系统本机模型，文字不会离开你的设备。" : "Translation uses Apple's on-device models only. Text never leaves your Mac."
    }
    static var regionPresets: String { zh ? "区域预设" : "Region Presets" }
    static var noPresets: String { zh ? "暂无预设" : "No presets saved" }

    // MARK: - Alerts

    static var screenRecordingRequired: String {
        zh ? "需要屏幕录制权限" : "Screen Recording Permission Required"
    }
    static var microphonePermissionRequired: String {
        zh ? "需要麦克风权限" : "Microphone Permission Required"
    }
    static var microphonePermissionTestingRequiresSignedBuild: String {
        zh ? "需要签名构建来验证麦克风权限" : "A Signed Build Is Required for Microphone Permission Testing"
    }
    static var screenRecordingBody: String {
        zh ? "Picelf 需要屏幕录制权限才能捕获窗口。\n\n步骤：\n1. 点击下方「打开系统设置」\n2. 找到「Picelf」并开启\n   （如果列表中没有，点击 + 添加）\n3. 授权后重启 Picelf"
           : "Picelf needs Screen Recording access to capture windows.\n\nSteps:\n1. Click \"Open System Settings\" below\n2. Find \"Picelf\" and toggle it ON\n   (If Picelf isn't listed, click + and add it)\n3. Restart Picelf after granting access"
    }
    static var microphonePermissionBody: String {
        zh ? "Picelf 仅在你启用录屏麦克风时才会使用麦克风。\n\n步骤：\n1. 点击下方「打开系统设置」\n2. 在“隐私与安全性 > 麦克风”中找到“Picelf”并开启\n3. 返回 Picelf 后再次启用麦克风"
           : "Picelf uses the microphone only when you enable microphone audio for screen recording.\n\nSteps:\n1. Click \"Open System Settings\" below\n2. Find \"Picelf\" in Privacy & Security > Microphone and toggle it ON\n3. Return to Picelf and enable Microphone again"
    }
    static var microphonePermissionInlineBody: String {
        zh ? "麦克风权限未授予。你仍然可以继续录制，但不会包含麦克风音频。\n\n如果要启用麦克风，请打开系统设置并在“隐私与安全性 > 麦克风”中允许 Picelf。"
           : "Microphone access wasn't granted. You can keep recording without microphone audio.\n\nTo enable microphone audio, open System Settings and allow Picelf in Privacy & Security > Microphone."
    }
    static var openSystemSettings: String { zh ? "打开系统设置" : "Open System Settings" }
    static var exitAndOpenSystemSettings: String {
        zh ? "退出并打开系统设置" : "Exit and Open System Settings"
    }
    static var noWindowsFound: String { zh ? "未找到窗口" : "No Windows Found" }
    static var noWindowsBody: String {
        zh ? "Picelf 找不到可捕获的窗口。\n\n请确保至少有一个应用窗口打开且可见。\n\n如果问题持续，请在系统设置 > 隐私与安全性 > 屏幕录制中关闭再开启 Picelf，然后重启。"
           : "Picelf could not find any capturable windows.\n\nMake sure you have at least one application window open and visible.\n\nIf the issue persists, try toggling Picelf off and on in System Settings > Privacy & Security > Screen Recording, then restart Picelf."
    }
    static var ok: String { "OK" }
    static var invalidCaptureArea: String { zh ? "无效的捕获区域" : "Invalid Capture Area" }
    static var invalidCaptureAreaBody1: String {
        zh ? "选定的区域超出了目标窗口范围。请移动选框使其与窗口重叠后重试。"
           : "The selected frame is outside the chosen window. Move the frame so it overlaps the window, then try again."
    }
    static var invalidCaptureAreaBody2: String {
        zh ? "无法将选定区域转换为捕获范围。"
           : "Could not convert the selected frame into a capture region."
    }
    static var notEnoughFrames: String { zh ? "帧数不足" : "Not Enough Frames" }
    static var noFramesCaptured: String {
        zh ? "未捕获到任何帧。请确保目标窗口可见后重试。"
           : "No frames were captured. Make sure the target window is visible and try again."
    }
    static var onlyOneFrame: String {
        zh ? "仅捕获到 1 帧。请在录制时尝试滚动窗口。"
           : "Only 1 unique frame was captured. Try scrolling the window while recording."
    }
    static var stitchingFailed: String { zh ? "拼接失败" : "Stitching Failed" }
    static var framesIdentical: String {
        zh ? "所有帧完全相同——内容未滚动。请尝试更慢地滚动。"
           : "All captured frames were identical — the content didn't scroll. Try scrolling more slowly while recording."
    }
    static var stitchCancelledOrTimeout: String {
        zh ? "拼接被取消或超时。请尝试捕获更少的帧。"
           : "Stitching was cancelled or timed out. Try capturing fewer frames."
    }
    static var overlapFailed: String {
        zh ? "无法对齐捕获的帧。帧间内容变化可能过大。"
           : "Could not align the captured frames. The content may have changed too much between frames."
    }

    // MARK: - Menu Bar

    static var workbench: String { zh ? "工作台" : "Workbench" }
    static var preferences: String { zh ? "偏好设置..." : "Preferences..." }
    static var quit: String { zh ? "退出 Picelf" : "Quit Picelf" }
    static func workbenchStatus(_ running: Int, _ queued: Int) -> String {
        zh ? "工作台（\(running) 运行中，\(queued) 排队中）"
           : "Workbench (\(running) running, \(queued) queued)"
    }
    static func appStatus(_ running: Int, _ queued: Int) -> String {
        zh ? "Picelf — \(running) 运行中，\(queued) 排队中"
           : "Picelf — \(running) running, \(queued) queued"
    }

    // MARK: - Workbench Phases

    static var phaseQueued: String { zh ? "排队中" : "Queued" }
    static var phasePreparing: String { zh ? "准备中" : "Preparing" }
    static var phaseSaving: String { zh ? "保存中" : "Saving" }
    static var phaseDone: String { zh ? "完成" : "Done" }
    static var phaseCancelled: String { zh ? "已取消" : "Cancelled" }
    static var phaseFailed: String { zh ? "失败" : "Failed" }
    static var phaseDedup: String { zh ? "去重" : "De-duplication" }
    static var phaseOverlap: String { zh ? "重叠检测" : "Overlap detection" }
    static var phaseOutlier: String { zh ? "异常值处理" : "Outlier cleanup" }
    static var phaseAudit: String { zh ? "一致性审计" : "Validation audit" }
    static var phaseProgressGuard: String { zh ? "进度守护" : "Progress guard" }
    static var phaseComposite: String { zh ? "合成" : "Compositing" }
    static var phaseWebTrunc: String { zh ? "网页截断" : "Web truncation" }
    static var phaseProcessing: String { zh ? "处理中" : "Processing" }

    // MARK: - Workbench UI

    static var captureStudio: String { zh ? "精灵工作室" : "Elf Studio" }
    static var searchPlaceholder: String { zh ? "搜索应用或窗口标题..." : "Search apps or window titles..." }
    static var allApps: String { zh ? "全部" : "All" }
    static var filterType: String { zh ? "类型" : "Type" }
    static var filterTime: String { zh ? "时间" : "Time" }
    static var filterToday: String { zh ? "今天" : "Today" }
    static var filterThisWeek: String { zh ? "本周" : "This Week" }
    static var filterThisMonth: String { zh ? "本月" : "This Month" }
    static var filterAllTypes: String { zh ? "全部类型" : "All Types" }
    static var filterAllTime: String { zh ? "全部时间" : "All Time" }
    static var showInspector: String { zh ? "显示检查器" : "Show Inspector" }
    static var hideInspector: String { zh ? "隐藏检查器" : "Hide Inspector" }
    static var running: String { zh ? "运行中" : "Running" }
    static var queued: String { zh ? "排队中" : "Queued" }
    static var completed: String { zh ? "已完成" : "Completed" }
    static var failed: String { zh ? "失败" : "Failed" }
    static var confidence: String { zh ? "置信度" : "Confidence" }
    static var clearFinished: String { zh ? "清除已完成" : "Clear Finished" }
    static var liveStage: String { zh ? "实时阶段" : "Live Stage" }
    static var noActiveSessions: String { zh ? "无活跃会话" : "No active sessions" }
    static var noActiveSessionsSubtitle: String {
        zh ? "新的捕获将在这里显示实时进度和置信度数据。"
           : "New captures appear here with live phase tracks and confidence telemetry."
    }
    static var gallery: String { zh ? "图库" : "Gallery" }
    static var noGalleryItems: String { zh ? "无图库项目" : "No gallery items" }
    static var noGalleryItemsSubtitle: String {
        zh ? "完成的会话将在这里显示视觉置信度和快速审查操作。"
           : "Completed sessions land here with visual confidence and quick review actions."
    }
    static var dropToImport: String { zh ? "松手即可导入到 Workbench" : "Drop to import into Workbench" }
    static var dropToImportSubtitle: String {
        zh ? "支持图片、视频和 Finder 文件。" : "Supports images, videos, and Finder files."
    }
    static var chronicle: String { zh ? "时间线" : "Chronicle" }
    static var nothingToChronicle: String { zh ? "暂无记录" : "Nothing to chronicle" }
    static var nothingToChronicleSubtitle: String {
        zh ? "切换到 Mosaic 或运行捕获来构建时间线叙事。"
           : "Switch to Mosaic or run captures to build a time-ordered narrative."
    }
    static var loadMore: String { zh ? "加载更多" : "Load More" }
    static var noSelection: String { zh ? "未选中" : "No selection" }
    static var noSelectionSubtitle: String {
        zh ? "选择任意实时会话或图库项来查看质量和运行时详情。"
           : "Select any live session or gallery tile to inspect quality and runtime details."
    }
    static var frames: String { zh ? "帧数" : "Frames" }
    static var riskBadges: String { zh ? "风险标签" : "Risk Badges" }
    static var app: String { zh ? "应用" : "App" }
    static var captureLabel: String { zh ? "捕获" : "Capture" }
    static var captureTypeLabel: String { zh ? "类型" : "Type" }
    static var output: String { zh ? "输出" : "Output" }
    static var renderingPreview: String { zh ? "渲染预览中" : "Rendering Preview" }
    static var noPreview: String { zh ? "无预览" : "No Preview" }
    static var rect: String { zh ? "区域" : "Rect" }
    static var livePrefix: String { zh ? "进行中" : "Live" }
    static func summaryRunning(_ running: Int, _ queued: Int) -> String {
        zh ? "\(running) 运行中 · \(queued) 排队中" : "\(running) running · \(queued) queued"
    }
    static func summaryIdle(_ count: Int) -> String {
        zh ? "\(count) 个捕获在工作室中" : "\(count) captures in studio"
    }

    // MARK: - Risk Badges

    static var riskFailure: String { zh ? "失败" : "Failure" }
    static var riskCancelled: String { zh ? "已取消" : "Cancelled" }
    static var riskDup: String { zh ? "重复" : "Dup" }
    static var riskLoss: String { zh ? "丢失" : "Loss" }
    static var riskSeam: String { zh ? "接缝" : "Seam" }

    // MARK: - Workbench Filters

    static var filterAll: String { zh ? "全部" : "All" }
    static var filterLive: String { zh ? "实时" : "Live" }
    static var filterHighConfidence: String { zh ? "高置信度" : "High Confidence" }
    static var filterNeedsReview: String { zh ? "待审查" : "Needs Review" }
    static var filterFailed: String { zh ? "失败" : "Failed" }
    static var modeMosaic: String { zh ? "马赛克" : "Mosaic" }
    static var modeChronicle: String { zh ? "时间线" : "Chronicle" }

    // MARK: - Recording

    static var record: String { zh ? "录屏" : "Record" }
    static var play: String { zh ? "播放" : "Play" }
    static var pause: String { zh ? "暂停" : "Pause" }
    static var resume: String { zh ? "继续" : "Resume" }
    static var stop: String { zh ? "停止" : "Stop" }
    static var recordingConfig: String { zh ? "录屏设置" : "Recording Settings" }
    static var format: String { zh ? "格式" : "Format" }
    static var resolution: String { zh ? "分辨率" : "Resolution" }
    static var frameRate: String { zh ? "帧率" : "Frame Rate" }
    static var showCursor: String { zh ? "显示光标" : "Show Cursor" }
    static var countdown: String { zh ? "倒计时" : "Countdown" }
    static var systemAudio: String { zh ? "系统声音" : "System Audio" }
    static var microphone: String { zh ? "麦克风" : "Microphone" }
    static var durationLimit: String { zh ? "时长限制" : "Duration Limit" }
    static var unlimited: String { zh ? "无限制" : "Unlimited" }
    static var noCountdown: String { zh ? "不倒计时" : "No countdown" }
    static var videoSection: String { zh ? "视频" : "Video" }
    static var audioSection: String { zh ? "音频" : "Audio" }
    static var timingSection: String { zh ? "时间" : "Timing" }
    static var startRecording: String { zh ? "开始录制" : "Start Recording" }
    static var continueWithoutMicrophone: String {
        zh ? "继续录制但不使用麦克风" : "Continue Without Microphone"
    }
    static var phaseFinalizingVideo: String { zh ? "视频处理中" : "Finalizing video" }
    static var recordingStartFailed: String { zh ? "无法开始录制" : "Unable to Start Recording" }
    static var recordingSaveFailed: String { zh ? "无法保存录屏" : "Unable to Save Recording" }
    static var microphoneDisabledForThisRecording: String {
        zh ? "此次录制将不使用麦克风" : "Microphone Disabled for This Recording"
    }
    static var microphoneDisabledForThisRecordingBody: String {
        zh ? "Picelf 当前无法使用麦克风，因此已为这次录制关闭麦克风。\n\n你可以继续录制但不包含麦克风音频，或者前往系统设置授予权限后再试。"
           : "Picelf couldn't use the microphone, so microphone audio has been turned off for this recording.\n\nYou can continue recording without microphone audio, or open System Settings and grant access first."
    }
    static var recordingSaveFailedBody: String {
        zh ? "录屏已结束，但 Picelf 无法完成视频保存。请重试。"
           : "The recording finished, but Picelf could not finalize and save the video. Please try again."
    }
    static var recordingStartNoTargetBody: String {
        zh ? "未定位到可录制的目标。请重新框选窗口或桌面区域后再试。"
           : "No recording target could be resolved. Reframe the window or desktop region and try again."
    }
    static var recordingStartWindowUnavailableBody: String {
        zh ? "目标窗口当前不可用，可能已关闭或已切换。请重新框选后再试。"
           : "The target window is unavailable (closed or changed). Please reframe and try again."
    }
    static var recordingStartDisplayUnavailableBody: String {
        zh ? "目标显示器当前不可用。请确认选框仍在可见桌面上后重试。"
           : "The target display is unavailable. Make sure the frame is still on a visible desktop and try again."
    }
    static func elapsed(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    static func secondsLabel(_ n: Int) -> String { zh ? "\(n) 秒" : "\(n)s" }

    // MARK: - Workbench Job Status

    static var statusQueued: String { zh ? "排队中" : "Queued" }
    static var statusProcessing: String { zh ? "处理中" : "Processing" }
    static var statusCompleted: String { zh ? "已完成" : "Completed" }
    static var statusFailed: String { zh ? "失败" : "Failed" }
    static var statusCancelled: String { zh ? "已取消" : "Cancelled" }

    // MARK: - Canvas (贴图)

    static var canvasLabel: String { zh ? "贴图" : "Canvas" }
    static var openInCanvas: String { zh ? "打开贴图" : "Open in Canvas" }
    static var addToCanvas: String { zh ? "添加到贴图" : "Add to Canvas" }
    static var canvasAddImage: String { zh ? "添加图片" : "Add Image" }
    static var canvasAddSticker: String { zh ? "添加贴图" : "Add Sticker" }
    static var canvasBackground: String { zh ? "背景" : "Background" }
    static var canvasWhite: String { zh ? "白色" : "White" }
    static var canvasTransparent: String { zh ? "透明" : "Transparent" }
    static var canvasCustomColor: String { zh ? "自定义颜色" : "Custom Color" }
    static var canvasProperties: String { zh ? "属性" : "Properties" }
    static var canvasStickers: String { zh ? "贴图库" : "Stickers" }
    static var canvasItemInfo: String { zh ? "元素信息" : "Item Info" }
    static var canvasCornerRadius: String { zh ? "圆角" : "Corner Radius" }
    static var canvasLayer: String { zh ? "图层" : "Layer" }
    static var canvasSize: String { zh ? "画布大小" : "Canvas Size" }
    static var canvasFitContent: String { zh ? "适应内容" : "Fit Content" }
    static var canvasItems: String { zh ? "个元素" : "items" }
    static var canvasNoSelection: String { zh ? "未选中任何元素" : "No item selected" }
    static var canvasNoStickers: String { zh ? "暂无贴图" : "No stickers yet" }
    static var canvasImageBackground: String { zh ? "图片背景" : "Image Background" }
    static var canvasApplySize: String { zh ? "应用" : "Apply" }

    // MARK: - Pin to Desktop (贴图)

    static var pinToDesktop: String { zh ? "贴图" : "Pin" }
    static var keepCapture: String { zh ? "保留" : "Keep" }
    static var unkeepCapture: String { zh ? "取消保留" : "Unkeep" }
    static var keptCapture: String { zh ? "已保留" : "Kept" }
    static var keepFromExpiry: String { zh ? "保留防过期" : "Keep from expiry" }
    static var pinEdit: String { zh ? "编辑" : "Edit" }
    static var pinSaveAs: String { zh ? "另存为..." : "Save As..." }
    static var pinOpacity: String { zh ? "透明度" : "Opacity" }
    static var pinClose: String { zh ? "关闭" : "Close" }
    static var pinOpenEditor: String { zh ? "打开编辑器" : "Open Editor" }
    static var pinLibrary: String { zh ? "贴图库" : "Pin Library" }
    static var pinMaxReached: String { zh ? "最多同时贴图 20 张" : "Maximum 20 pins reached" }
    static var pinCanvasLabel: String { zh ? "贴图画布" : "Canvas" }
    static var filterPinned: String { zh ? "贴图库" : "Pin Library" }
    static var snapEditTitle: String { zh ? "截图编辑" : "Snap Edit" }

    // MARK: - Privacy

    static var privacyPolicy: String { zh ? "隐私政策" : "Privacy Policy" }
    static var scrollHint: String { zh ? "请滚动目标窗口，完成后点击\"完成\"" : "Scroll the target window, then click Done" }

    // MARK: - Pin Binding

    static var pinBindTo: String { zh ? "绑定到..." : "Bind to..." }
    static var pinAllDesktops: String { zh ? "所有桌面" : "All Desktops" }
    static var pinCurrentDesktop: String { zh ? "仅当前桌面" : "Current Desktop Only" }
    static var pinDesktop: String { zh ? "桌面" : "Desktop" }
    static func pinScreen(_ name: String) -> String { zh ? "屏幕: \(name)" : "Screen: \(name)" }
    static func pinWindow(_ app: String, _ title: String) -> String {
        let t = title.isEmpty ? app : "\(app) — \(title)"
        return zh ? "窗口: \(t)" : "Window: \(t)"
    }

    // MARK: - Watermark

    static var watermark: String { zh ? "水印" : "Watermark" }
    static var watermarkEnabled: String { zh ? "启用水印" : "Enable Watermark" }
    static var watermarkContent: String { zh ? "内容" : "Content" }
    static var watermarkText: String { zh ? "文本" : "Text" }
    static var watermarkTextPlaceholder: String { zh ? "输入水印文字…" : "Enter watermark text…" }
    static var watermarkPosition: String { zh ? "位置" : "Position" }
    static var watermarkStyle: String { zh ? "样式" : "Style" }
    static var watermarkFontSize: String { zh ? "字号" : "Size" }
    static var watermarkColor: String { zh ? "颜色" : "Color" }
    static var watermarkOpacity: String { zh ? "透明度" : "Opacity" }
    static var watermarkShadow: String { zh ? "阴影" : "Shadow" }
    static var watermarkRotation: String { zh ? "旋转" : "Rotation" }
    static var watermarkPreview: String { zh ? "预览" : "Preview" }
    static var watermarkTiled: String { zh ? "平铺" : "Tiled" }
    static var watermarkTiledEnabled: String { zh ? "启用平铺" : "Enable Tiled" }
    static var watermarkTiledAngle: String { zh ? "角度" : "Angle" }
    static var watermarkTiledSpacing: String { zh ? "间距" : "Spacing" }
    static var watermarkShadowRadius: String { zh ? "阴影半径" : "Shadow Radius" }
    static var watermarkFont: String { zh ? "字体" : "Font" }
}
