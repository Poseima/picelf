import Foundation
import Combine
import CryptoKit
@preconcurrency import MultipeerConnectivity

@MainActor
final class RelayTransport: NSObject, ObservableObject {
    struct Device: Identifiable { let peer: MCPeerID; var id: String { peer.displayName }; var name: String { peer.displayName } }
    private struct Wire: Codable {
        enum Kind: String, Codable { case hello, proof, confirm, packet }
        var kind: Kind
        var data: Data
    }
    @Published private(set) var devices: [Device] = []
    @Published private var statusMessage = (chinese: "未连接", english: "Not Connected")
    var status: String { L10n.localized(statusMessage.chinese, statusMessage.english) }

    private func setStatus(_ chinese: String, _ english: String) {
        statusMessage = (chinese, english)
    }
    @Published private(set) var pairingCode: String?
    @Published private(set) var connected = false
    @Published private(set) var confirmedLocally = false
    @Published private(set) var remoteConfirmed = false
    @Published private(set) var peerName: String?
    @Published private(set) var hasTrustedPeer = false
    let pairing = RelayPairingPresentation()
    private var pairingObservation: AnyCancellable?
    private var retryDevice: Device?
    private var connectionTimeout: Task<Void, Never>?
    var oppositeDeviceName: String { role == .mac ? "iPad" : "Mac" }
    var showsDiscovery: Bool { !hasTrustedPeer && !connected && !pairing.connecting && pairing.notice == nil && !pairing.discoveryDismissed && !devices.isEmpty }
    var onPacket: ((RelayPacket) -> Void)?
    var onConnection: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    private let role: RelayRole
    private let peer: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    private var handshake: RelayHandshake?
    private var remoteHello: RelayHello?
    private var key: SymmetricKey?
    private var remotePeer: MCPeerID?
    private var verified = false
    private var running = false
    private var trustedIdentity: Data?
    private var connectingPeer: MCPeerID?
    private var retryTargetName: String?
    private var generation = UUID()
    private var outgoing: [(RelayPacket, Bool)] = []
    private var resourceSending = false
    private let service = "picelf-relay"

    init(role: RelayRole) {
        self.role = role
        let deviceID = UserDefaults.standard.string(forKey: "relay.deviceNameSuffix") ?? String(UUID().uuidString.prefix(4))
        UserDefaults.standard.set(deviceID, forKey: "relay.deviceNameSuffix")
        peer = MCPeerID(displayName: "Picelf \(role == .mac ? "Mac" : "iPad") · \(deviceID)")
        super.init()
        pairingObservation = pairing.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    func start() {
        guard !running else { return }
        do {
            trustedIdentity = try RelayKeychain.read("trusted-peer")
            hasTrustedPeer = trustedIdentity != nil
            _ = try RelayKeychain.signingKey()
            session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
            session.delegate = self
            advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["role": role.rawValue], serviceType: service)
            advertiser.delegate = self
            browser = MCNearbyServiceBrowser(peer: peer, serviceType: service)
            browser.delegate = self
            running = true
            setStatus("正在寻找附近设备…", "Looking for nearby devices…")
            advertiser.startAdvertisingPeer()
            browser.startBrowsingForPeers()
        } catch { fail(error) }
    }
    func stop() {
        running = false
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        resetConnection()
        devices = []
        setStatus("未连接，打开两端接力画板即可重连", "Not connected. Open Relay Canvas on both devices to reconnect")
    }
    func connect(_ device: Device) {
        guard running, !connected, remotePeer == nil, connectingPeer == nil else { return }
        retryTargetName = nil
        beginAttempt(device)
        connectingPeer = device.peer
        setStatus("正在连接 \(device.name)…", "Connecting to \(device.name)…")
        browser.invitePeer(device.peer, to: session, withContext: nil, timeout: 15)
    }
    func confirmPairing() {
        guard verified, key != nil, !confirmedLocally else { return }
        confirmedLocally = true
        pairing.confirm(generation, local: true, remote: remoteConfirmed)
        do { try sendWire(.init(kind: .confirm, data: RelayHandshake.seal(Data("confirmed".utf8), key: key!))); try finishPairing() }
        catch { fail(error); session?.disconnect(); resetConnection() }
    }
    func rejectPairing() {
        pairing.dismiss(generation)
        if let notice = pairing.notice { pairing.dismiss(notice.id) }
        session?.disconnect(); resetConnection(); setStatus("已取消配对", "Pairing Cancelled")
    }
    func dismissPairingNotice() {
        guard let notice = pairing.notice else { return }
        if notice.phase == .confirmation { rejectPairing() }
        else { pairing.dismiss(notice.id) }
    }
    func retryPairing() {
        let device = retryDevice
        rejectPairing()
        start()
        guard let device else { return }
        // Keep the browser's discovery mapping. A newly started browser cannot
        // invite a retained MCPeerID until it has discovered that peer again.
        if let available = devices.first(where: { $0.name == device.name }) {
            connect(available)
        } else {
            retryTargetName = device.name
            beginAttempt(device)
            setStatus("正在重新寻找 \(device.name)…", "Looking for \(device.name) again…")
        }
    }
    private func beginAttempt(_ device: Device) {
        // A fresh session makes late callbacks from a cancelled attempt inert.
        session?.delegate = nil; session?.disconnect()
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        generation = UUID(); retryDevice = device
        pairing.begin(generation, peer: device.name)
        let token = generation
        connectionTimeout?.cancel()
        connectionTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, self.generation == token, !self.connected,
                  self.pairingCode == nil else { return }
            self.fail(RelayError.message(L10n.localized("连接超时。请确认两端接力画板已打开，并连接 Wi-Fi。", "Connection timed out. Make sure Relay Canvas is open on both devices and both are connected to Wi-Fi.")))
            self.session?.disconnect(); self.resetConnection()
        }
    }
    func forgetPairing() {
        do { try RelayKeychain.forgetPeer(); trustedIdentity = nil; hasTrustedPeer = false; rejectPairing() }
        catch { fail(error) }
    }
    func send(_ packet: RelayPacket, resource: Bool = false) {
        guard connected else { return }
        if resource {
            if let live = packet.live {
                outgoing.removeAll { $0.0.taskID == packet.taskID && $0.0.live?.session.id == live.session.id && $0.0.live?.action == live.action }
            }
            outgoing.append((packet, true)); drainResources()
        }
        else {
            do {
                guard let key else { return }
                let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
                try sendWire(.init(kind: .packet, data: RelayHandshake.seal(encoder.encode(packet), key: key)))
            } catch { fail(error) }
        }
    }
    private func drainResources() {
        guard connected, !resourceSending, !outgoing.isEmpty, let remotePeer, let key else { return }
        let item = outgoing.removeFirst().0
        let token = generation
        do {
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            let data = try RelayHandshake.seal(encoder.encode(item), key: key)
            guard data.count <= RelayLimits.maxResourceBytes else { throw RelayError.message(L10n.localized("传输内容过大，请缩小图片。", "The transfer is too large. Resize the image first.")) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("picelf-relay-\(UUID().uuidString).enc")
            try data.write(to: url, options: .atomic)
            resourceSending = true
            session.sendResource(at: url, withName: "relay-\(UUID().uuidString)", toPeer: remotePeer) { [weak self] error in
                try? FileManager.default.removeItem(at: url)
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.resourceSending = false
                    if let error { self.fail(error) }
                    self.drainResources()
                }
            }
        } catch { resourceSending = false; fail(error); drainResources() }
    }
    private func sendWire(_ wire: Wire) throws {
        guard let remotePeer else { throw RelayError.message(L10n.localized("设备尚未连接。", "The device is not connected.")) }
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        try session.send(encoder.encode(wire), toPeers: [remotePeer], with: .reliable)
    }
    private func receive(_ data: Data, from peer: MCPeerID, resource: Bool = false) {
        guard peer == remotePeer else { return }
        do {
            if resource {
                guard connected, let key else { return }
                let packet = try PropertyListDecoder().decode(RelayPacket.self, from: RelayHandshake.open(data, key: key))
                onPacket?(packet)
                return
            }
            guard data.count <= RelayLimits.maxPreviewBytes + 65_536 else { throw RelayError.message(L10n.localized("设备消息超出限制。", "The device message exceeds the size limit.")) }
            let wire = try PropertyListDecoder().decode(Wire.self, from: data)
            switch wire.kind {
            case .hello:
                guard remoteHello == nil, let handshake else { throw RelayError.message(L10n.localized("重复握手。", "Duplicate handshake.")) }
                let hello = try PropertyListDecoder().decode(RelayHello.self, from: wire.data)
                _ = try handshake.transcript(hello)
                if let trustedIdentity, trustedIdentity != hello.identity {
                    throw RelayError.message(L10n.localized("这不是已配对的设备。更换设备前请先解除配对。", "This is not the paired device. Unpair before switching devices."))
                }
                remoteHello = hello
                key = try handshake.sessionKey(hello)
                try sendWire(.init(kind: .proof, data: handshake.proof(hello)))
            case .proof:
                guard !verified, let handshake, let remoteHello else { throw RelayError.message(L10n.localized("配对顺序错误。", "The pairing steps arrived out of order.")) }
                try handshake.verify(wire.data, from: remoteHello)
                verified = true
                // The transport handshake is complete. Human confirmation on
                // either device must not be cut off by its 20-second deadline.
                connectionTimeout?.cancel()
                if trustedIdentity == remoteHello.identity {
                    confirmPairing()
                    pairing.showCodeWhileWaitingForPeer(generation, code: try handshake.code(remoteHello))
                }
                else {
                    let code = try handshake.code(remoteHello)
                    pairingCode = code; setStatus("请核对两端配对码", "Check the pairing code on both devices")
                    pairing.request(generation, code: code)
                }
            case .confirm:
                guard verified, let key,
                      try RelayHandshake.open(wire.data, key: key) == Data("confirmed".utf8) else { throw RelayError.message(L10n.localized("配对确认无效。", "The pairing confirmation is invalid.")) }
                remoteConfirmed = true
                pairing.confirm(generation, local: confirmedLocally, remote: true)
                try finishPairing()
            case .packet:
                guard connected, let key else { return }
                let packet = try PropertyListDecoder().decode(RelayPacket.self, from: RelayHandshake.open(wire.data, key: key))
                onPacket?(packet)
            }
        } catch {
            fail(error)
            if !connected { session?.disconnect(); resetConnection() }
        }
    }
    private func finishPairing() throws {
        guard verified, confirmedLocally, remoteConfirmed, !connected, let remoteHello else { return }
        try RelayKeychain.write(remoteHello.identity, account: "trusted-peer")
        trustedIdentity = remoteHello.identity
        UserDefaults.standard.set(remotePeer?.displayName, forKey: "relay.lastPeerName")
        hasTrustedPeer = true
        pairingCode = nil
        connected = true
        connectionTimeout?.cancel()
        pairing.connected(generation)
        setStatus("已连接 · \(peerName ?? "设备")", "Connected · \(peerName ?? "Device")")
        onConnection?(true)
    }
    private func resetConnection() {
        retryTargetName = nil
        connectionTimeout?.cancel()
        pairing.disconnected(generation)
        generation = UUID()
        connected = false; confirmedLocally = false; remoteConfirmed = false; verified = false
        remotePeer = nil; connectingPeer = nil; remoteHello = nil; handshake = nil; key = nil; pairingCode = nil
        resourceSending = false; outgoing.removeAll()
        onConnection?(false)
    }
    private func fail(_ error: Error) {
        setStatus(error.localizedDescription, error.localizedDescription)
        if !connected, retryDevice != nil { pairing.failed(generation, message: error.localizedDescription) }
        if pairing.notice?.phase != .failure { onError?(error.localizedDescription) }
    }
}
extension RelayTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            guard session === self.session, self.running else { return }
            switch state {
            case .connected:
                guard self.remotePeer == nil, self.connectingPeer == peerID else { return }
                self.remotePeer = peerID; self.connectingPeer = nil; self.peerName = peerID.displayName
                do {
                    let handshake = try RelayHandshake(role: self.role, signingKey: RelayKeychain.signingKey())
                    self.handshake = handshake
                    try self.sendWire(.init(kind: .hello, data: PropertyListEncoder().encode(handshake.hello)))
                } catch { self.fail(error) }
            case .notConnected:
                if self.remotePeer == peerID || self.connectingPeer == peerID {
                    self.resetConnection(); self.setStatus("连接已断开，草稿已保留，正在等待重连…", "Disconnected. Draft saved; waiting to reconnect…")
                    // Discovery can retain a peer through brief disconnection. Retry without waiting for foundPeer.
                    let reconnectGeneration = self.generation
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        guard let self, self.generation == reconnectGeneration, self.running, self.role == .mac, self.hasTrustedPeer,
                              self.pairing.notice?.phase != .failure,
                              // A relaunched iPad has a new MCPeerID even though its saved name is unchanged.
                              let device = self.devices.last(where: { $0.name == peerID.displayName }) else { return }
                        self.connect(device)
                    }
                }
            case .connecting: break
            @unknown default: break
            }
        }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in guard session === self.session else { return }; self.receive(data, from: peerID) }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        if progress.totalUnitCount > RelayLimits.maxResourceBytes { progress.cancel() }
    }
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // MPC owns localURL only for the duration of this callback.
        guard error == nil, let localURL,
              let size = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size]) as? NSNumber,
              size.intValue <= RelayLimits.maxResourceBytes,
              let data = try? Data(contentsOf: localURL) else {
            Task { @MainActor in self.onError?(L10n.localized("图片传输中断，重连后将重新发送。", "Image transfer was interrupted and will resume after reconnecting.")) }; return
        }
        Task { @MainActor in guard session === self.session else { return }; self.receive(data, from: peerID, resource: true) }
    }
}
extension RelayTransport: MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard browser === self.browser, info?["role"] != self.role.rawValue else { return }
            if !self.devices.contains(where: { $0.peer == peerID }) { self.devices.append(Device(peer: peerID)) }
            if self.retryTargetName == peerID.displayName {
                self.connect(Device(peer: peerID)); return
            }
            if self.role == .mac, self.hasTrustedPeer, self.pairing.notice?.phase != .failure,
               peerID.displayName == UserDefaults.standard.string(forKey: "relay.lastPeerName") {
                self.connect(Device(peer: peerID))
            }
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in guard browser === self.browser else { return }; self.devices.removeAll { $0.peer == peerID } }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.fail(error) }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in self.fail(error) }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            let accepts = advertiser === self.advertiser && self.running && self.remotePeer == nil && self.connectingPeer == nil
            if accepts { self.beginAttempt(Device(peer: peerID)); self.connectingPeer = peerID; self.setStatus("正在连接 \(peerID.displayName)…", "Connecting to \(peerID.displayName)…") }
            invitationHandler(accepts, accepts ? self.session : nil)
        }
    }
}
