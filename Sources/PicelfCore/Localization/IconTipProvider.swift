import Foundation

enum IconTipKey: String, CaseIterable {
    case addImage
    case undo
    case redo
    case delete
    case zoomOut
    case zoomIn
    case fitToWindow
    case actualSize
    case save
    case copy
    case share
    case watermark
    case pinToDesktop
    case scrollCapture
    case record
    case ocr
    case translate
    case extractSubject
    case confirm
    case cancel
    case openResult
    case revealInFinder
    case retry
    case remove
    case keepCapture
    case unkeepCapture
    case showInspector
    case hideInspector
    case clearSearch
    case appFilter
    case importSticker
    case duplicate
    case stickerShadow
    case stickerFlipHorizontal
    case stickerFlipVertical
    case bringForward
    case sendBackward
    case lock
    case unlock
    case hideLayer
    case showLayer
    case chooseImageBackground
    case customBackgroundColor
    case recordPause
    case recordResume
    case recordStop
    case closePanel
    case openCanvas
}

struct IconTipProvider {
    static func text(for key: IconTipKey) -> String {
        accessibilityLabel(for: key)
    }

    static func accessibilityLabel(for key: IconTipKey) -> String {
        let descriptor = descriptor(for: key)
        var label = localized(en: descriptor.labelEN, zh: descriptor.labelZH)
        if let shortcut = descriptor.shortcut {
            label += " (\(shortcut))"
        }
        return label
    }

    static func accessibilityHint(for key: IconTipKey) -> String {
        let descriptor = descriptor(for: key)
        return localized(en: descriptor.hintEN, zh: descriptor.hintZH)
    }

    private static func descriptor(for key: IconTipKey) -> IconTipDescriptor {
        switch key {
        case .addImage:
            return .init("Add Image", "添加图片", "Import image files into canvas", "将图片文件导入到画布", nil)
        case .undo:
            return .init("Undo", "撤销", "Revert the last action", "撤销上一步操作", "⌘Z")
        case .redo:
            return .init("Redo", "重做", "Restore the most recently undone action", "恢复刚刚撤销的操作", "⇧⌘Z")
        case .delete:
            return .init("Delete", "删除", "Delete selected item", "删除当前选中对象", "Delete")
        case .zoomOut:
            return .init("Zoom Out", "缩小", "Decrease zoom level", "降低缩放比例", "⌘-")
        case .zoomIn:
            return .init("Zoom In", "放大", "Increase zoom level", "提高缩放比例", "⌘=")
        case .fitToWindow:
            return .init("Fit to Window", "适应窗口", "Fit content into current viewport", "让内容适应当前可视区域", "⌘9")
        case .actualSize:
            return .init("Actual Size", "实际尺寸", "Display content at 100 percent", "按 100% 原始尺寸显示", "⌘0")
        case .save:
            return .init("Save", "保存", "Save current result", "保存当前结果", "⌘S")
        case .copy:
            return .init("Copy", "复制", "Copy current result to clipboard", "复制当前结果到剪贴板", "⌘C")
        case .share:
            return .init("Share", "分享", "Open system share panel", "打开系统分享面板", nil)
        case .watermark:
            return .init("Watermark", "水印", "Open watermark settings", "打开水印设置", nil)
        case .pinToDesktop:
            return .init("Pin to Desktop", "贴到桌面", "Pin image to desktop", "将图像固定到桌面", nil)
        case .scrollCapture:
            return .init("Scroll Capture", "滚动截图", "Capture and stitch scrolling content", "捕获并拼接滚动内容", nil)
        case .record:
            return .init("Record", "录屏", "Start recording current target", "开始录制当前目标", nil)
        case .ocr:
            return .init("OCR", "文字识别", "Extract text from image", "提取图像中的文字", "⇧⌘T")
        case .translate:
            return .init("Translate", "翻译", "Translate recognized text on device", "使用本机模型翻译识别出的文字", "⇧⌘L")
        case .extractSubject:
            return .init("Extract Subject", "提取主体", "Separate the foreground subject", "智能分离前景主体", "⇧⌘B")
        case .confirm:
            return .init("Confirm", "确认", "Confirm current operation", "确认当前操作", "Return")
        case .cancel:
            return .init("Cancel", "取消", "Cancel current operation", "取消当前操作", "Esc")
        case .openResult:
            return .init("Open", "打开", "Open generated output", "打开生成结果", nil)
        case .revealInFinder:
            return .init("Reveal", "在 Finder 中显示", "Reveal output file in Finder", "在 Finder 中定位输出文件", nil)
        case .retry:
            return .init("Retry", "重试", "Retry this failed capture", "重试该失败捕获", nil)
        case .remove:
            return .init("Remove", "移除", "Remove this item from list", "将该项从列表移除", nil)
        case .keepCapture:
            return .init("Keep", "保留", "Prevent this capture from expiry", "防止该捕获被自动过期", nil)
        case .unkeepCapture:
            return .init("Unkeep", "取消保留", "Allow this capture to expire", "允许该捕获参与自动过期", nil)
        case .showInspector:
            return .init("Show Inspector", "显示检查器", "Open inspector panel", "展开检查器面板", nil)
        case .hideInspector:
            return .init("Hide Inspector", "隐藏检查器", "Collapse inspector panel", "折叠检查器面板", nil)
        case .clearSearch:
            return .init("Clear Search", "清空搜索", "Clear current search query", "清空当前搜索关键词", nil)
        case .appFilter:
            return .init("App Filter", "应用筛选", "Open quick app filter list", "打开应用筛选列表", nil)
        case .importSticker:
            return .init("Import Sticker", "导入贴图", "Import image as sticker", "将图片导入为贴图", nil)
        case .duplicate:
            return .init("Duplicate", "复制", "Duplicate current selection", "复制当前选中对象", "⌘D")
        case .stickerShadow:
            return .init("Shadow", "阴影", "Toggle shadow for selected sticker", "切换选中贴图的阴影效果", nil)
        case .stickerFlipHorizontal:
            return .init("Flip Horizontal", "水平翻转", "Flip selected item horizontally", "将选中对象水平翻转", nil)
        case .stickerFlipVertical:
            return .init("Flip Vertical", "垂直翻转", "Flip selected item vertically", "将选中对象垂直翻转", nil)
        case .bringForward:
            return .init("Bring Forward", "上移", "Move selected layer one step forward", "将选中图层上移一层", nil)
        case .sendBackward:
            return .init("Send Backward", "下移", "Move selected layer one step backward", "将选中图层下移一层", nil)
        case .lock:
            return .init("Lock", "锁定", "Lock current layer", "锁定当前图层", nil)
        case .unlock:
            return .init("Unlock", "解锁", "Unlock current layer", "解锁当前图层", nil)
        case .hideLayer:
            return .init("Hide", "隐藏", "Hide current layer", "隐藏当前图层", nil)
        case .showLayer:
            return .init("Show", "显示", "Show current layer", "显示当前图层", nil)
        case .chooseImageBackground:
            return .init("Image Background", "图片背景", "Choose an image as canvas background", "选择图片作为画布背景", nil)
        case .customBackgroundColor:
            return .init("Custom Color", "自定义颜色", "Pick custom canvas background color", "选择自定义画布背景颜色", nil)
        case .recordPause:
            return .init("Pause Recording", "暂停录制", "Pause current recording session", "暂停当前录制会话", nil)
        case .recordResume:
            return .init("Resume Recording", "继续录制", "Resume paused recording session", "继续已暂停的录制会话", nil)
        case .recordStop:
            return .init("Stop Recording", "停止录制", "Stop and finalize recording", "停止并完成录制", "Esc")
        case .closePanel:
            return .init("Close", "关闭", "Close this panel", "关闭当前面板", nil)
        case .openCanvas:
            return .init("Canvas", "画布", "Open canvas workspace", "打开画布工作区", nil)
        }
    }

    private static func localized(en: String, zh: String) -> String {
        prefersChinese ? zh : en
    }

    private static var prefersChinese: Bool {
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
}

private struct IconTipDescriptor {
    let labelEN: String
    let labelZH: String
    let hintEN: String
    let hintZH: String
    let shortcut: String?

    init(_ labelEN: String, _ labelZH: String, _ hintEN: String, _ hintZH: String, _ shortcut: String?) {
        self.labelEN = labelEN
        self.labelZH = labelZH
        self.hintEN = hintEN
        self.hintZH = hintZH
        self.shortcut = shortcut
    }
}
