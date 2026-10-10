import AppKit
import SwiftUI

@MainActor
final class IconTipHUDController {
    static let shared = IconTipHUDController()

    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?

    private init() {
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }
    }

    deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
    }

    func show(text: String, at mouseLocation: CGPoint) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hide()
            return
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            hide()
            return
        }

        let hostingView = NSHostingView(rootView: IconHoverTipBubble(text: trimmed))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let fittingSize = hostingView.fittingSize
        let tipSize = CGSize(width: max(1, ceil(fittingSize.width)), height: max(1, ceil(fittingSize.height)))
        let origin = IconTipHUDGeometryResolver.resolve(
            mouseLocation: mouseLocation,
            tipSize: tipSize,
            screenVisibleFrame: screen.visibleFrame
        )

        let panel = ensurePanel()
        let ownerWindow = topmostWindow(at: mouseLocation, excluding: panel)
        panel.level = IconTipHUDLevelResolver.resolveLevel(ownerWindowRawLevel: ownerWindow?.level.rawValue)
        panel.contentView = hostingView
        panel.setFrame(NSRect(origin: origin, size: tipSize), display: false)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = IconTipHUDLevelResolver.fallbackLevel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true

        self.panel = panel
        return panel
    }

    private func topmostWindow(at mouseLocation: CGPoint, excluding tipPanel: NSPanel) -> NSWindow? {
        NSApp.windows
            .filter { window in
                window !== tipPanel
                    && window.isVisible
                    && !window.isMiniaturized
                    && window.frame.contains(mouseLocation)
            }
            .max { lhs, rhs in
                let lhsPriority = (
                    lhs.level.rawValue,
                    lhs.isKeyWindow ? 1 : 0,
                    lhs.isMainWindow ? 1 : 0,
                    lhs.windowNumber
                )
                let rhsPriority = (
                    rhs.level.rawValue,
                    rhs.isKeyWindow ? 1 : 0,
                    rhs.isMainWindow ? 1 : 0,
                    rhs.windowNumber
                )
                return lhsPriority < rhsPriority
            }
    }
}

struct IconTipHUDLevelResolver {
    static let fallbackLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)

    static func resolveLevel(ownerWindowRawLevel: Int?) -> NSWindow.Level {
        NSWindow.Level(rawValue: resolveRawLevel(ownerWindowRawLevel: ownerWindowRawLevel))
    }

    static func resolveRawLevel(
        ownerWindowRawLevel: Int?,
        fallbackRawLevel: Int = fallbackLevel.rawValue
    ) -> Int {
        guard let ownerWindowRawLevel else { return fallbackRawLevel }
        let elevatedRaw = ownerWindowRawLevel >= Int.max - 1
            ? ownerWindowRawLevel
            : ownerWindowRawLevel + 1
        return max(fallbackRawLevel, elevatedRaw)
    }
}

struct IconTipHUDGeometryResolver {
    static func resolve(
        mouseLocation: CGPoint,
        tipSize: CGSize,
        screenVisibleFrame: CGRect,
        pointerGap: CGFloat = 12,
        edgeInset: CGFloat = 4
    ) -> CGPoint {
        let minX = screenVisibleFrame.minX + edgeInset
        let maxX = screenVisibleFrame.maxX - tipSize.width - edgeInset
        let minY = screenVisibleFrame.minY + edgeInset
        let maxY = screenVisibleFrame.maxY - tipSize.height - edgeInset

        let x: CGFloat
        if maxX < minX {
            x = screenVisibleFrame.midX - tipSize.width / 2
        } else {
            let preferRight = mouseLocation.x + pointerGap
            let preferLeft = mouseLocation.x - tipSize.width - pointerGap
            let rawX = preferRight <= maxX ? preferRight : preferLeft
            x = min(max(minX, rawX), maxX)
        }

        let y: CGFloat
        if maxY < minY {
            y = screenVisibleFrame.midY - tipSize.height / 2
        } else {
            let preferAbove = mouseLocation.y + pointerGap
            let preferBelow = mouseLocation.y - tipSize.height - pointerGap
            let rawY = preferAbove <= maxY ? preferAbove : preferBelow
            y = min(max(minY, rawY), maxY)
        }

        return CGPoint(x: x, y: y)
    }
}

extension View {
    func iconTip(_ key: IconTipKey) -> some View {
        let tip = IconTipProvider.text(for: key)
        let label = IconTipProvider.accessibilityLabel(for: key)
        let hint = IconTipProvider.accessibilityHint(for: key)
        return self.modifier(
            IconHoverTipModifier(
                text: tip,
                accessibilityLabel: label,
                accessibilityHint: hint
            )
        )
    }

    func iconTipText(
        _ text: String,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil
    ) -> some View {
        let title = IconHoverTipModifier.compactTitle(from: text)
        return self.modifier(
            IconHoverTipModifier(
                text: title,
                accessibilityLabel: accessibilityLabel ?? title,
                accessibilityHint: accessibilityHint ?? text
            )
        )
    }
}

private struct IconHoverTipModifier: ViewModifier {
    let text: String
    let accessibilityLabel: String
    let accessibilityHint: String

    @State private var isHovering = false
    @State private var showTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                showTask?.cancel()

                if hovering {
                    guard !text.isEmpty else { return }
                    showTask = Task {
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            guard isHovering else { return }
                            IconTipHUDController.shared.show(text: text, at: NSEvent.mouseLocation)
                        }
                    }
                } else {
                    IconTipHUDController.shared.hide()
                }
            }
            .onDisappear {
                showTask?.cancel()
                showTask = nil
                IconTipHUDController.shared.hide()
            }
            .help(text)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
    }

    static func compactTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return trimmed.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
    }
}

private struct IconHoverTipBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    var body: some View {
        let isDark = colorScheme == .dark
        let textColor = isDark ? Color.white.opacity(0.94) : Color.black.opacity(0.88)
        let backgroundColor = isDark ? Color.black.opacity(0.9) : Color.white.opacity(0.96)
        let borderColor = isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.16)
        let shadowColor = Color.black.opacity(isDark ? 0.35 : 0.2)

        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(textColor)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 6, y: 2)
    }
}
