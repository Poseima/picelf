import SwiftUI


struct RelayPairingCard: View {
    @Environment(\.colorScheme) private var scheme
    private var pairingAccent: Color { RelayPalette.accent(in: scheme) }
    @ObservedObject var transport: RelayTransport
    @ObservedObject var presentation: RelayPairingPresentation
    @AccessibilityFocusState private var titleFocused: Bool
    init(transport: RelayTransport) { self.transport = transport; presentation = transport.pairing }
    var body: some View {
        if let notice = presentation.notice {
            VStack(spacing: 20) {
                Image(systemName: notice.phase == .success ? "checkmark.circle.fill" : notice.phase == .failure ? "exclamationmark.circle" : "link")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(notice.phase == .failure ? .orange : pairingAccent)
                    .accessibilityHidden(true)
                Text(notice.phase == .success
                    ? L10n.localized("已连接", "Connected")
                    : notice.phase == .failure
                        ? L10n.localized("未能完成配对", "Pairing Failed")
                        : L10n.localized("确认设备配对", "Confirm Device Pairing"))
                    .font(.title2.bold()).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                Text(notice.peer).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let code = notice.code {
                    Text(code).font(.system(size: 38, weight: .semibold, design: .monospaced))
                        .tracking(5).minimumScaleFactor(0.7).lineLimit(1)
                        .accessibilityLabel(L10n.localized("配对码 \(code.map(String.init).joined(separator: " "))", "Pairing code \(code.map(String.init).joined(separator: " "))"))
                        .accessibilityIdentifier("relay.pairingCode")
                }
                if notice.phase != .success {
                    Text(notice.message).font(.body).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("relay.pairingStatus")
                }
                if notice.phase == .confirmation {
                    Button { transport.confirmPairing() } label: {
                        Text(notice.localConfirmed
                            ? L10n.localized("等待对方确认…", "Waiting for the other device…")
                            : L10n.localized("配对码相同，确认", "Codes Match, Confirm"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(RelayActionStyle(prominent: true)).disabled(notice.localConfirmed)
                        .accessibilityIdentifier("relay.confirmPairing")
                    Button { transport.rejectPairing() } label: {
                        Text(L10n.localized("取消配对", "Cancel Pairing")).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("relay.cancelPairing")
                } else if notice.phase == .failure {
                    Button { transport.retryPairing() } label: {
                        Text(L10n.localized("重新连接", "Reconnect")).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(RelayActionStyle(prominent: true)).accessibilityIdentifier("relay.retryPairing")
                    Button { transport.dismissPairingNotice() } label: {
                        Text(L10n.localized("关闭", "Close")).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(24).frame(maxWidth: .infinity).tint(pairingAccent)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("relay.pairingCard")
            .onAppear { titleFocused = true }
            .task(id: notice.phase == .success ? notice.id : nil) {
                if notice.phase == .success { await presentation.successWasShown(notice.id) }
            }
        }
    }
}

struct RelayDiscoveryBanner: View {
    @Environment(\.colorScheme) private var scheme
    private var pairingAccent: Color { RelayPalette.accent(in: scheme) }
    @ObservedObject var transport: RelayTransport
    var body: some View {
        if let toast = transport.pairing.connectionToast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(pairingAccent).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("relay.connectionToast")
        } else if transport.showsDiscovery {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(pairingAccent)
                Text(L10n.localized("发现附近的 \(transport.oppositeDeviceName)", "Nearby \(transport.oppositeDeviceName) found")).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if transport.devices.count == 1, let device = transport.devices.first {
                    Button { transport.connect(device) } label: {
                        Text(L10n.localized("连接", "Connect")).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("relay.connectDiscovered")
                } else {
                    Menu {
                        ForEach(transport.devices) { device in Button(device.name) { transport.connect(device) } }
                    } label: {
                        Text(L10n.localized("连接", "Connect")).frame(minWidth: 44, minHeight: 44)
                    }.accessibilityIdentifier("relay.connectDiscovered")
                }
                Button { transport.pairing.dismissDiscovery() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(L10n.localized("关闭发现设备提示", "Dismiss nearby device suggestion"))
            }.padding(.horizontal, 12).padding(.vertical, 4)
                .background(pairingAccent.opacity(0.08)).tint(pairingAccent)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("relay.discoveryBanner")
        }
    }
}
