import Foundation
import Combine

struct RelayPairingNotice: Identifiable, Equatable {
    enum Phase: Equatable { case confirmation, success, failure }
    let id: UUID
    let peer: String
    var code: String?
    var phase: Phase = .confirmation
    var localConfirmed = false
    var remoteConfirmed = false
    var error: String?
    var message: String {
        if phase == .success { return L10n.localized("已连接", "Connected") }
        if phase == .failure { return error ?? L10n.localized("配对已中断，请重新连接。", "Pairing was interrupted. Reconnect to try again.") }
        if localConfirmed { return L10n.localized("等待另一台设备确认", "Waiting for the other device") }
        if remoteConfirmed { return L10n.localized("对方已确认，请核对配对码", "The other device confirmed. Check the pairing code") }
        return L10n.localized("请核对两端的配对码，然后分别确认。", "Check that both devices show the same code, then confirm on each device.")
    }
}

/// UI lifetime is separate from the encrypted connection lifetime. In particular,
/// a failure remains reviewable after the transport discards its handshake keys.
@MainActor
final class RelayPairingPresentation: ObservableObject {
    @Published private(set) var notice: RelayPairingNotice?
    @Published private(set) var connecting = false
    @Published private(set) var connectionToast: String?
    @Published private(set) var discoveryDismissed = false
    private var attempt: UUID?
    private var peer = L10n.localized("设备", "Device")
    private var dismissed = Set<UUID>()
    private var toastWork: Task<Void, Never>?
    private var confirmationWork: Task<Void, Never>?

    func begin(_ id: UUID, peer: String) {
        guard id != attempt else { return }
        attempt = id; self.peer = peer; notice = nil; connecting = true
        confirmationWork?.cancel()
        toastWork?.cancel(); connectionToast = nil
    }
    // One device may have forgotten its trust while the other still remembers it.
    // Normal trusted reconnections stay quiet; a peer waiting for human approval
    // must have a matching code visible on this device as well.
    func showCodeWhileWaitingForPeer(_ id: UUID, code: String) {
        guard id == attempt, connecting, notice == nil else { return }
        confirmationWork?.cancel()
        confirmationWork = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self, self.attempt == id, self.connecting else { return }
            self.request(id, code: code)
            self.confirm(id, local: true, remote: false)
        }
    }
    func request(_ id: UUID, code: String) {
        guard id == attempt, !dismissed.contains(id), notice == nil else { return }
        connecting = false
        notice = RelayPairingNotice(id: id, peer: peer, code: code)
    }
    func confirm(_ id: UUID, local: Bool, remote: Bool) {
        guard id == attempt, var value = notice, value.id == id, value.phase == .confirmation else { return }
        value.localConfirmed = value.localConfirmed || local
        value.remoteConfirmed = value.remoteConfirmed || remote
        notice = value
    }
    func connected(_ id: UUID) {
        guard id == attempt else { return }
        confirmationWork?.cancel()
        connecting = false
        if var value = notice, value.id == id, value.phase == .confirmation {
            value.phase = .success; value.code = nil; notice = value
        } else if notice == nil, !dismissed.contains(id) {
            connectionToast = L10n.localized("已连接 · \(peer)", "Connected · \(peer)")
            toastWork?.cancel()
            toastWork = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled, self?.attempt == id else { return }
                self?.connectionToast = nil
            }
        }
    }
    func failed(_ id: UUID, message: String) {
        guard id == attempt, !dismissed.contains(id), notice?.phase != .success,
              notice?.phase != .failure else { return }
        connecting = false
        confirmationWork?.cancel()
        notice = RelayPairingNotice(id: id, peer: peer, code: nil, phase: .failure, error: message)
    }
    func disconnected(_ id: UUID) {
        guard id == attempt else { return }
        confirmationWork?.cancel()
        toastWork?.cancel(); connectionToast = nil
        if connecting || notice?.phase == .confirmation {
            failed(id, message: L10n.localized("连接已中断，画作已保留。请重新连接。", "The connection was interrupted. Your work was saved. Reconnect to continue."))
        }
        connecting = false
    }
    func dismiss(_ id: UUID) {
        guard notice?.id == id || attempt == id else { return }
        confirmationWork?.cancel()
        dismissed.insert(id); notice = nil; connecting = false
    }
    func dismissDiscovery() { discoveryDismissed = true }
    func successWasShown(_ id: UUID) async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard !Task.isCancelled, notice?.id == id, notice?.phase == .success else { return }
        dismiss(id)
    }
}
