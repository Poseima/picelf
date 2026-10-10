import SwiftUI

enum EditorTooltipKey {
    case tool(EditorTool)
    case stickerPicker
    case stickerOption(String)
    case undo
    case redo
    case delete
    case fit
    case zoomOut
    case zoomIn
    case actualSize
    case zoomPercent
    case save
    case copy
    case share
    case translate
    case watermark
    case inspector
    case summaryTool
    case summaryAnnotations
    case summaryImage
    case strokeColor
    case fillColor
    case lineWidth
    case textSize
    case textWidth
    case replaceSticker
    case mosaicBlock
    case exportFormat
    case jpegQuality
    case ocr
    case translationTarget
    case translationOverlay
    case translationCopy
    case translationExport
    case statusZoom
    case statusCanvas
    case statusSelected
    // Pill toolbar (capture frame)
    case snap
    case scrollCapture
    case record
    case cancelCapture
    case pinToDesktop
    case extractSubject
    case snapConfirm
    case snapCancel
}

struct EditorTooltipProvider {
    static func text(for key: EditorTooltipKey) -> String {
        let raw: String
        let zh = L10n.zh
        switch key {
        case .tool(let tool):
            raw = toolText(tool, zh: zh)
        case .stickerPicker:
            raw = zh ? "贴图\n选择常用贴图并切换到贴图工具\n快捷键: T"
                     : "Sticker\nChoose a sticker and switch to the sticker tool\nShortcut: T"
        case .stickerOption(let sticker):
            raw = zh ? "贴图选项 \(sticker)\n将当前贴图替换为此样式"
                     : "Sticker \(sticker)\nReplace the current sticker with this one"
        case .undo:
            raw = zh ? "撤销\n回退上一步编辑\n快捷键: Command + Z"
                     : "Undo\nRevert the last edit\nShortcut: Command + Z"
        case .redo:
            raw = zh ? "重做\n恢复刚刚撤销的编辑\n快捷键: Shift + Command + Z"
                     : "Redo\nRestore the last undone edit\nShortcut: Shift + Command + Z"
        case .delete:
            raw = zh ? "删除\n删除当前选中的标注\n快捷键: Delete"
                     : "Delete\nRemove the selected annotation\nShortcut: Delete"
        case .fit:
            raw = zh ? "适应窗口\n让整张图片完整显示在可视区域\n快捷键: Command + 9"
                     : "Fit to Window\nScale the image to fit the viewport\nShortcut: Command + 9"
        case .zoomOut:
            raw = zh ? "缩小\n降低当前画布缩放比例\n快捷键: Command + -"
                     : "Zoom Out\nDecrease canvas zoom level\nShortcut: Command + -"
        case .zoomIn:
            raw = zh ? "放大\n提高当前画布缩放比例\n快捷键: Command + ="
                     : "Zoom In\nIncrease canvas zoom level\nShortcut: Command + ="
        case .actualSize:
            raw = zh ? "实际尺寸\n按 100% 显示原始像素\n快捷键: Command + 0"
                     : "Actual Size\nDisplay at 100% original pixels\nShortcut: Command + 0"
        case .zoomPercent:
            raw = zh ? "当前缩放比例\n显示画布实时缩放百分比"
                     : "Current Zoom\nShows the live canvas zoom percentage"
        case .save:
            raw = zh ? "保存\n覆盖当前图片（无源文件时弹出另存为）\n快捷键: Command + S"
                     : "Save\nOverwrite the current image (or Save As when no source exists)\nShortcut: Command + S"
        case .copy:
            raw = zh ? "复制\n复制当前合成结果到剪贴板\n快捷键: Command + C"
                     : "Copy\nCopy the current composition to clipboard\nShortcut: Command + C"
        case .share:
            raw = zh ? "分享\n通过系统分享面板发送当前合成结果"
                     : "Share\nSend the current composition via the system share panel"
        case .translate:
            raw = zh ? "翻译\n使用本机模型翻译图片文字\n快捷键: Shift + Command + L"
                     : "Translate\nTranslate recognized text on device\nShortcut: Shift + Command + L"
        case .watermark:
            raw = zh ? "水印\n打开水印设置并应用到导出结果"
                     : "Watermark\nOpen watermark settings and apply to exports"
        case .inspector:
            raw = zh ? "检查器\n查看并调整当前工具与对象属性"
                     : "Inspector\nView and adjust tool and object properties"
        case .summaryTool:
            raw = zh ? "当前工具\n显示当前正在使用的编辑工具"
                     : "Current Tool\nShows the active editing tool"
        case .summaryAnnotations:
            raw = zh ? "标注数量\n显示画布上的标注总数"
                     : "Annotation Count\nTotal number of annotations on the canvas"
        case .summaryImage:
            raw = zh ? "图像尺寸\n显示底图原始像素尺寸"
                     : "Image Size\nOriginal pixel dimensions of the base image"
        case .strokeColor:
            raw = zh ? "描边颜色\n设置线条或边框颜色"
                     : "Stroke Color\nSet the color for lines and borders"
        case .fillColor:
            raw = zh ? "填充颜色\n设置形状内部填充颜色"
                     : "Fill Color\nSet the interior fill color for shapes"
        case .lineWidth:
            raw = zh ? "线宽\n调整线条粗细（像素）"
                     : "Line Width\nAdjust the line thickness in pixels"
        case .textSize:
            raw = zh ? "文字大小\n调整文本或贴图字号"
                     : "Font Size\nAdjust the text or sticker font size"
        case .textWidth:
            raw = zh ? "文本宽度\n控制自动换行宽度，影响画布显示与导出"
                     : "Text Width\nControls wrap width for both canvas preview and export"
        case .replaceSticker:
            raw = zh ? "替换贴图\n为选中的贴图切换新样式"
                     : "Replace Sticker\nSwap the selected sticker for a new one"
        case .mosaicBlock:
            raw = zh ? "马赛克颗粒\n数值越大，像素块越粗"
                     : "Mosaic Block Size\nLarger values produce coarser pixelation"
        case .exportFormat:
            raw = zh ? "导出格式\n在 PNG 与 JPEG 之间切换"
                     : "Export Format\nSwitch between PNG and JPEG"
        case .jpegQuality:
            raw = zh ? "JPEG 质量\n值越高图像越清晰，文件越大"
                     : "JPEG Quality\nHigher values produce sharper images but larger files"
        case .ocr:
            raw = zh ? "文字识别\n提取图片中的文字内容\n快捷键: Shift + Command + T"
                     : "Text Recognition\nExtract text from the image\nShortcut: Shift + Command + T"
        case .translationTarget:
            raw = zh ? "目标语言\n选择译文要输出的语言"
                     : "Target Language\nChoose the language for translated output"
        case .translationOverlay:
            raw = zh ? "覆盖方式\n切换为关闭、悬停气泡或直接覆盖原文"
                     : "Overlay Mode\nSwitch between off, hover bubbles, and direct replacement"
        case .translationCopy:
            raw = zh ? "复制翻译\n将当前译文结果复制到剪贴板"
                     : "Copy Translation\nCopy the translated text to the clipboard"
        case .translationExport:
            raw = zh ? "导出翻译副本\n导出一张带译文覆盖层的新图片"
                     : "Export Translated Copy\nExport a new image with the translation overlay"
        case .statusZoom:
            raw = zh ? "缩放状态\n显示当前画布缩放百分比"
                     : "Zoom Status\nCurrent canvas zoom percentage"
        case .statusCanvas:
            raw = zh ? "画布尺寸\n显示底图像素宽高"
                     : "Canvas Size\nBase image pixel dimensions"
        case .statusSelected:
            raw = zh ? "选中数量\n显示当前选中的对象个数"
                     : "Selection Count\nNumber of currently selected objects"
        case .snap:
            raw = zh ? "截图\n捕获当前窗口截图\n快捷键: Return"
                     : "Snap\nCapture a screenshot of the current window\nShortcut: Return"
        case .scrollCapture:
            raw = zh ? "滚动截图\n自动滚动并拼接长截图"
                     : "Scroll Capture\nAuto-scroll and stitch a long screenshot"
        case .record:
            raw = zh ? "录屏\n录制当前窗口视频"
                     : "Record\nRecord video of the current window"
        case .cancelCapture:
            raw = zh ? "取消\n退出截图模式\n快捷键: Escape"
                     : "Cancel\nExit capture mode\nShortcut: Escape"
        case .pinToDesktop:
            raw = zh ? "贴到桌面\n将截图固定到桌面上"
                     : "Pin to Desktop\nPin the screenshot to the desktop"
        case .extractSubject:
            raw = zh ? "提取主体\n智能分离图片前景主体\n快捷键: Shift + Command + B"
                     : "Extract Subject\nIntelligently separate the foreground subject\nShortcut: Shift + Command + B"
        case .snapConfirm:
            raw = zh ? "确认\n完成编辑并保存\n快捷键: Return（编辑文本时仅换行）"
                     : "Confirm\nFinish editing and save\nShortcut: Return (text editing keeps Enter for new lines)"
        case .snapCancel:
            raw = zh ? "取消\n放弃编辑\n快捷键: Escape"
                     : "Cancel\nDiscard edits\nShortcut: Escape"
        }
        return compact(raw)
    }

    private static func toolText(_ tool: EditorTool, zh: Bool) -> String {
        switch tool {
        case .rectangle:
            return zh ? "矩形\n绘制矩形标注\n快捷键: 1" : "Rectangle\nDraw a rectangle annotation\nShortcut: 1"
        case .ellipse:
            return zh ? "椭圆\n绘制椭圆标注\n快捷键: 2" : "Ellipse\nDraw an ellipse annotation\nShortcut: 2"
        case .line:
            return zh ? "直线\n绘制直线标注\n快捷键: 3" : "Line\nDraw a straight line\nShortcut: 3"
        case .arrow:
            return zh ? "箭头\n绘制箭头标注\n快捷键: 4" : "Arrow\nDraw an arrow annotation\nShortcut: 4"
        case .pencil:
            return zh ? "铅笔\n自由绘制路径\n快捷键: 5" : "Pencil\nFreehand drawing\nShortcut: 5"
        case .mosaic:
            return zh ? "马赛克\n覆盖敏感区域\n快捷键: 6" : "Mosaic\nPixelate sensitive areas\nShortcut: 6"
        case .text:
            return zh ? "文本\n点击创建文本框\n快捷键: 7" : "Text\nClick to create a text box\nShortcut: 7"
        case .step:
            return zh ? "步骤标注\n添加编号步骤点\n快捷键: 8" : "Step\nAdd numbered step markers\nShortcut: 8"
        case .highlight:
            return zh ? "高亮\n绘制半透明高亮区域\n快捷键: 9" : "Highlight\nDraw a translucent highlight\nShortcut: 9"
        case .sticker:
            return zh ? "贴图\n插入贴纸标记\n快捷键: T" : "Sticker\nInsert a sticker marker\nShortcut: T"
        }
    }

    private static func compact(_ text: String) -> String {
        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let first = lines.first else { return "" }

        var title = first
        var detail: String?

        for line in lines.dropFirst() {
            if let shortcut = shortcutValue(from: line) {
                title += " (\(shortcut))"
                continue
            }
            if detail == nil {
                detail = line
            }
        }

        if let detail {
            return "\(title) · \(detail)"
        }
        return title
    }

    private static func shortcutValue(from line: String) -> String? {
        let zhPrefix = "快捷键:"
        let enPrefix = "Shortcut:"
        if line.hasPrefix(zhPrefix) {
            return line.dropFirst(zhPrefix.count).trimmingCharacters(in: .whitespaces)
        }
        if line.hasPrefix(enPrefix) {
            return line.dropFirst(enPrefix.count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
