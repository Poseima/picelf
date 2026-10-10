import Foundation

// Protocol and persistence are shared source, compiled into each application target.
enum RelayRole: String, Codable { case mac, iPad }
enum RelayTaskState: String, Codable {
    case queued, editing, returning, copying, completed, copyFailed, cancelled
    var isHistory: Bool { self == .completed || self == .cancelled }
}
struct RelayTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var origin: RelayRole
    var width: Int
    var height: Int
    var createdAt = Date()
    var updatedAt = Date()
    var revision = 0
    var state: RelayTaskState = .queued
    var receiptRevision: Int?
    var copyFailureMessage: String?
}
struct RelayPacket: Codable {
    enum Kind: String, Codable { case task, accepted, preview, previewAck, final, receipt, cancel, live }
    var kind: Kind
    var taskID: UUID
    var revision: Int = 0
    var task: RelayTask?
    var image: Data?
    var ink: Data?
    var success: Bool?
    var message: String?
    var macDocument: Data?
    var liveVersion: Int?
    var live: RelayLiveMessage?
    var padText: Data?
    var textVersion: Int?
}
enum RelayError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum RelayLimits {
    static let maxPixels = 24_000_000
    static let maxEdge = 16_384
    static let maxResourceBytes = 160 * 1024 * 1024
    static let maxPreviewBytes = 4 * 1024 * 1024
    static let historyCount = 30
    static let historyBytes = 1_024 * 1_024 * 1_024
    static func validate(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= maxEdge, height <= maxEdge,
              width <= maxPixels / height else {
            throw RelayError.message(L10n.localized("图片过大：接力画板支持最多 2400 万像素、单边 16384 像素。请先裁剪或缩小。", "The image is too large. Relay Canvas supports up to 24 million pixels and 16,384 pixels per side. Crop or resize it first."))
        }
    }
}
extension RelayTaskState {
    var relayLabel: String {
        switch self {
        case .queued: return L10n.localized("等待标注", "Waiting for Edits")
        case .editing: return L10n.localized("正在标注", "Editing")
        case .returning: return L10n.localized("等待 Mac 复制确认", "Waiting for Mac to Confirm Copy")
        case .copying: return L10n.localized("正在复制", "Copying")
        case .completed: return L10n.localized("Mac 已复制", "Copied on Mac")
        case .copyFailed: return L10n.localized("图片已收到，复制失败", "Image Received, Copy Failed")
        case .cancelled: return L10n.localized("已保留草稿", "Draft Kept")
        }
    }
}

// Presentation is derived from this task, never from another task's last event.
struct RelayTaskPresentation {
    let title: String
    let symbol: String
    let isWaiting: Bool
    let isFailure: Bool
    init(task: RelayTask, role: RelayRole, connected: Bool) {
        isFailure = task.copyFailureMessage != nil || task.state == .copyFailed
        isWaiting = !isFailure && (task.state == .returning || task.state == .copying)
        if isFailure {
            title = role == .iPad
                ? L10n.localized("Mac 已收到，请在 Mac 重试复制", "Received on Mac. Try copying again on Mac")
                : L10n.localized("复制失败，请重试", "Copy failed. Try again")
            symbol = "exclamationmark.circle"
        } else {
            switch task.state {
            case .completed:
                title = role == .mac
                    ? L10n.localized("已复制，按 ⌘V 粘贴", "Copied. Press ⌘V to paste")
                    : L10n.localized("已到 Mac，直接粘贴", "Ready to paste on Mac")
                symbol = "checkmark.circle.fill"
            case .returning, .copying:
                title = connected
                    ? L10n.localized("正在回传，等待 Mac 确认", "Sending back. Waiting for Mac")
                    : L10n.localized("画作已保存，等待重连回传", "Saved. Waiting to reconnect and send")
                symbol = "arrow.up.circle"
            case .queued, .editing:
                title = connected
                    ? (role == .mac
                        ? (task.state == .queued
                            ? L10n.localized("等待 iPad 标注", "Waiting for iPad edits")
                            : L10n.localized("iPad 正在标注", "Editing on iPad"))
                        : L10n.localized("笔迹自动保存", "Edits save automatically"))
                    : L10n.localized("草稿已保存，等待重连", "Draft saved. Waiting to reconnect")
                symbol = connected ? "pencil.tip" : "wifi.slash"
            case .cancelled:
                title = L10n.localized("草稿已保留", "Draft Kept"); symbol = "doc"
            case .copyFailed:
                title = L10n.localized("复制失败，请重试", "Copy failed. Try again"); symbol = "exclamationmark.circle"
            }
        }
    }
}
