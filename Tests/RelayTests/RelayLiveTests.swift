import XCTest
import CoreGraphics
@testable import Picelf

@MainActor
final class RelayLiveTests: XCTestCase {
    private var root: URL!
    private var mac: RelayCoordinator!
    private var pad: RelayCoordinator!
    private var id: UUID!
    private var packets: [(RelayRole, RelayPacket)] = []
    private var clipboardCount = 10
    private var copies: [Data] = []
    private func png(red: CGFloat = 0, alpha: CGFloat = 0) throws -> Data {
        let c = try XCTUnwrap(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.setFillColor(CGColor(red: red, green: 0.5, blue: 0.2, alpha: alpha)); c.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        return try RelayImage.png(XCTUnwrap(c.makeImage()))
    }
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RelayLiveTests-\(UUID())")
        let task = RelayTask(title: "Shared", origin: .mac, width: 64, height: 48); id = task.id
        for name in ["mac", "pad"] { try RelayStore(directory: root.appendingPathComponent(name)).save(task, base: png(red: 1, alpha: 1)) }
        mac = RelayCoordinator(role: .mac, directory: root.appendingPathComponent("mac"), startTransport: { _ in })
        pad = RelayCoordinator(role: .iPad, directory: root.appendingPathComponent("pad"), startTransport: { _ in })
        mac.collaboration.sendOverride = { [weak self] in self?.packets.append((.mac, $0)) }
        pad.collaboration.sendOverride = { [weak self] in self?.packets.append((.iPad, $0)) }
        mac.collaboration.clipboardChangeCount = { [weak self] in self?.clipboardCount ?? 0 }
        mac.copyImage = { [weak self] in self?.copies.append($0); self?.clipboardCount += 1 }
        mac.collaboration.discoveredPeer(); pad.collaboration.discoveredPeer()
    }
    override func tearDown() async throws {
        mac.collaboration.sendOverride = nil; pad.collaboration.sendOverride = nil
        await settle()
        mac = nil; pad = nil
        try? FileManager.default.removeItem(at: root)
    }
    private func pump() {
        var count = 0
        while !packets.isEmpty && count < 200 {
            let (sender, packet) = packets.removeFirst()
            (sender == .mac ? pad : mac)?.receive(packet); count += 1
        }
        XCTAssertLessThan(count, 200, "Protocol must not echo indefinitely")
    }
    private func settle(file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        repeat {
            pump()
            if packets.isEmpty && !mac.collaboration.hasPendingLocalWork && !pad.collaboration.hasPendingLocalWork {
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        } while ContinuousClock.now < deadline
        pump()
        XCTFail("Relay packets and local composition did not settle within 5 seconds", file: file, line: line)
    }
    private func startAndCommit() async throws {
        try mac.collaboration.start(id); pump()
        try mac.collaboration.commit(id, image: png(red: 1, alpha: 1), document: Data("Mac annotations".utf8))
        try pad.collaboration.commit(id, image: png(), document: Data("Pencil ink".utf8))
        await settle()
    }
    func testTextArchiveSynchronizesAndSurvivesNewVersion() async throws {
        mac.collaboration.discoveredPeer(textVersion: 1); pad.collaboration.discoveredPeer(textVersion: 1)
        try await startAndCommit()
        let document = RelayTextDocument(boxes: [.init(text: "中文 PPT\nReview", x: 2, y: 3, width: 50, fontSize: 12)])
        let archive = try document.encoded()
        pad.collaboration.markDirty(id)
        try pad.collaboration.commit(id, image: png(red: 1, alpha: 0.5), document: Data("editable ink".utf8), padText: archive)
        await settle()
        XCTAssertEqual(mac.collaboration.textData(id), archive)
        XCTAssertEqual(copies.count, 2)
        mac.collaboration.end(id); await settle()
        XCTAssertEqual(mac.task(id)?.state, .completed)
        XCTAssertEqual(try mac.data(id, RelayTextDocument.filename), archive)
        let next = try XCTUnwrap(mac.reopen(id))
        XCTAssertEqual(try mac.data(next, RelayTextDocument.filename), archive)
        XCTAssertEqual(try mac.data(id, RelayTextDocument.filename), archive)
    }
    func testContinueTextWorkOfflineCreatesDurableLiveVersion() async throws {
        mac.collaboration.discoveredPeer(textVersion: 1); pad.collaboration.discoveredPeer(textVersion: 1)
        try await startAndCommit()
        let archive = try RelayTextDocument(boxes: [.init(text: "保留文字", x: 2, y: 3, width: 50, fontSize: 12)]).encoded()
        try pad.collaboration.commit(id, image: png(), document: Data(), padText: archive); await settle()
        mac.collaboration.end(id); await settle()
        pad.collaboration.sendOverride = nil; pad.collaboration.connectionChanged(false)
        let next = try XCTUnwrap(pad.reopen(id))
        XCTAssertTrue(pad.collaboration.isLive(next))
        XCTAssertEqual(try pad.data(next, RelayTextDocument.filename), archive)
        XCTAssertNil(pad.errorMessage)
        XCTAssertEqual(pad.collaboration.status(next), L10n.localized("已保存，等待重连", "Saved. Waiting to Reconnect"))
    }
    func testTextDraftPersistsOfflineAndLegacyPeerDoesNotReceiveLayers() async throws {
        try await startAndCommit()
        pad.collaboration.connectionChanged(false)
        packets.removeAll()
        let archive = try RelayTextDocument(boxes: [.init(text: "Saved offline", x: 2, y: 3, width: 50, fontSize: 12)]).encoded()
        try pad.collaboration.commit(id, image: png(), document: Data(), padText: archive)
        XCTAssertEqual(pad.collaboration.textData(id), archive)
        XCTAssertTrue(packets.isEmpty)
        pad.collaboration.discoveredPeer()
        XCTAssertTrue(packets.isEmpty, "A legacy peer must not silently discard editable text")
        pad.collaboration.discoveredPeer(textVersion: 1); await settle()
        XCTAssertEqual(mac.collaboration.textData(id), archive)
    }
    func testBothLayersAutomaticallyCopyAndRemainEditable() async throws {
        try await startAndCommit()
        XCTAssertEqual(copies.count, 1)
        let result = try XCTUnwrap(copies.last)
        XCTAssertEqual(try RelayImage.pngDimensions(result).0, 64)
        XCTAssertEqual(mac.task(id)?.state, .editing)
        XCTAssertTrue(pad.collaboration.isLive(id))
        XCTAssertEqual(pad.collaboration.session(id)?.copiedPad, 1)
        mac.collaboration.markDirty(id); pad.collaboration.markDirty(id); pump()
        try pad.collaboration.commit(id, image: png(red: 0.4, alpha: 0.4), document: Data("ink v2".utf8))
        await settle()
        XCTAssertEqual(copies.count, 1, "Do not copy while Mac still has pending edits")
        try mac.collaboration.commit(id, image: png(red: 0.7, alpha: 1), document: Data("mac v2".utf8))
        await settle()
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(mac.collaboration.layerData(id, role: .iPad, document: true), Data("ink v2".utf8))
        XCTAssertEqual(pad.collaboration.layerData(id, role: .mac, document: true), Data("mac v2".utf8))
    }
    func testUnrelatedClipboardContentPausesUntilExplicitResume() async throws {
        try await startAndCommit()
        clipboardCount += 1
        pad.collaboration.markDirty(id)
        try pad.collaboration.commit(id, image: png(red: 1, alpha: 0.5), document: Data())
        await settle()
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(mac.collaboration.session(id)?.clipboardPaused, true)
        XCTAssertEqual(pad.collaboration.session(id)?.clipboardPaused, true)
        mac.collaboration.resumeClipboard(id); await settle()
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(mac.collaboration.session(id)?.clipboardPaused, false)
    }
    func testDuplicateAndReorderedLayersCannotOverwriteNewerInk() async throws {
        try await startAndCommit()
        pad.collaboration.markDirty(id)
        try pad.collaboration.commit(id, image: png(red: 0.2, alpha: 0.3), document: Data([2]))
        let older = try XCTUnwrap(packets.last(where: { $0.1.live?.action == "layer" })?.1)
        pump()
        pad.collaboration.markDirty(id)
        try pad.collaboration.commit(id, image: png(red: 0.8, alpha: 0.7), document: Data([3]))
        await settle()
        let count = copies.count
        mac.receive(older); mac.receive(older); await settle()
        XCTAssertEqual(mac.collaboration.layerData(id, role: .iPad, document: true), Data([3]))
        XCTAssertEqual(copies.count, count)
    }
    func testLateLayerDoesNotClearNewerDirtyState() async throws {
        try await startAndCommit()
        try pad.collaboration.commit(id, image: png(), document: Data([2]))
        let old = try XCTUnwrap(packets.last(where: { $0.1.live?.action == "layer" })?.1)
        packets.removeAll()
        pad.collaboration.markDirty(id); pump()
        mac.receive(old); await settle()
        XCTAssertEqual(mac.collaboration.session(id)?.padDirty, true)
        XCTAssertEqual(copies.count, 1)
    }
    func testEndWaitsForBothFlushesAndAcknowledgedLayers() async throws {
        try await startAndCommit()
        pad.collaboration.markDirty(id)
        pad.collaboration.flushLocal[id] = { [weak self] in
            guard let self else { return }
            try self.pad.collaboration.commit(self.id, image: self.png(red: 1, alpha: 0.4), document: Data([9]))
        }
        mac.collaboration.end(id)
        XCTAssertFalse(mac.collaboration.session(id)?.completed ?? true)
        await settle()
        XCTAssertEqual(mac.task(id)?.state, .completed)
        XCTAssertEqual(pad.task(id)?.state, .completed)
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(try pad.data(id, "result.png"), copies.last)
        XCTAssertEqual(mac.collaboration.layerData(id, role: .iPad, document: true), Data([9]))
    }
    func testRestartRestoresLayersAndPausesClipboard() async throws {
        try await startAndCommit()
        let restarted = RelayCoordinator(role: .mac, directory: root.appendingPathComponent("mac"), startTransport: { _ in })
        XCTAssertEqual(restarted.collaboration.activeID, id)
        XCTAssertEqual(restarted.collaboration.session(id)?.clipboardPaused, true)
        XCTAssertEqual(restarted.collaboration.layerData(id, role: .iPad, document: true), Data("Pencil ink".utf8))
    }
    func testCopyFailureRetainsResultAndExplicitRetryRecovers() async throws {
        mac.copyImage = { _ in throw RelayError.message("Test clipboard failure") }
        try await startAndCommit()
        XCTAssertNotNil(mac.collaboration.session(id)?.failure)
        XCTAssertNotNil(try? mac.data(id, "result.png"))
        mac.copyImage = { [weak self] in self?.copies.append($0); self?.clipboardCount += 1 }
        mac.collaboration.resumeClipboard(id); await settle()
        XCTAssertEqual(copies.count, 1)
        XCTAssertNil(mac.collaboration.session(id)?.failure)
    }
    func testOfflineEditsFromBothOwnersMergeOnReconnect() async throws {
        try await startAndCommit()
        mac.collaboration.sendOverride = nil; pad.collaboration.sendOverride = nil
        mac.collaboration.markDirty(id); pad.collaboration.markDirty(id)
        try mac.collaboration.commit(id, image: png(red: 0.4, alpha: 1), document: Data([11]))
        try pad.collaboration.commit(id, image: png(red: 0.7, alpha: 0.5), document: Data([22]))
        await settle(); XCTAssertEqual(copies.count, 1)
        mac.collaboration.sendOverride = { [weak self] in self?.packets.append((.mac, $0)) }
        pad.collaboration.sendOverride = { [weak self] in self?.packets.append((.iPad, $0)) }
        mac.collaboration.synchronize(); pad.collaboration.synchronize(); await settle()
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(mac.collaboration.layerData(id, role: .iPad, document: true), Data([22]))
        XCTAssertEqual(pad.collaboration.layerData(id, role: .mac, document: true), Data([11]))
    }
    func testCommittedLayerRejectsLatePreviewAndKeepsNewestPreview() async throws {
        try await startAndCommit()
        try pad.collaboration.commit(id, image: png(), document: Data([2]), editRevision: 10)
        pump()
        pad.collaboration.preview(id, revision: 9, image: try png(red: 1, alpha: 1)); pump()
        XCTAssertNil(mac.collaboration.layerPreviews[id])
        pad.collaboration.preview(id, revision: 11, image: try png(red: 0.4, alpha: 1)); pump()
        XCTAssertNotNil(mac.collaboration.layerPreviews[id])
        await settle()
    }
    func testFailedLayerSaveDoesNotCommitMetadataOrCopy() async throws {
        try await startAndCommit()
        let url = try XCTUnwrap(mac.fileURL(id, "collaboration.json"))
        let saved = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertThrowsError(try mac.collaboration.commit(id, image: png(), document: Data([9])))
        XCTAssertEqual(mac.collaboration.session(id)?.mac?.revision, 1)
        XCTAssertEqual(copies.count, 1)
        try FileManager.default.removeItem(at: url); try saved.write(to: url)
        try mac.collaboration.commit(id, image: png(), document: Data([9])); await settle()
        XCTAssertEqual(copies.count, 2)
    }
    func testConcurrentOffersForSameImageUseMacSessionWithoutLosingPadLayer() async throws {
        try mac.collaboration.start(id)
        let macSession = try XCTUnwrap(mac.collaboration.session(id)?.id)
        try pad.collaboration.start(id)
        try pad.collaboration.commit(id, image: png(), document: Data([42]))
        pump()
        mac.collaboration.synchronize(); pad.collaboration.synchronize(); await settle()
        XCTAssertEqual(pad.collaboration.session(id)?.id, macSession)
        XCTAssertEqual(mac.collaboration.layerData(id, role: .iPad, document: true), Data([42]))
    }
    func testClipboardPauseIsVisibleBeforeAnotherEdit() async throws {
        try await startAndCommit()
        clipboardCount += 1
        mac.collaboration.synchronize(); await settle()
        XCTAssertEqual(mac.collaboration.session(id)?.clipboardPaused, true)
        XCTAssertEqual(pad.collaboration.session(id)?.clipboardPaused, true)
        XCTAssertEqual(copies.count, 1)
    }
    func testCompletedResultCanBeCopiedOfflineAfterRestart() async throws {
        try await startAndCommit(); mac.collaboration.end(id); await settle()
        let restarted = RelayCoordinator(role: .mac, directory: root.appendingPathComponent("mac"), startTransport: { _ in })
        var count = 0
        restarted.copyImage = { _ in count += 1 }
        restarted.copyAgain(id)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(restarted.collaboration.session(id)?.clipboardPaused, false)
    }
    func testPadContinuePersistsMacArchiveBeforePublishingNewTask() async throws {
        try await startAndCommit(); mac.collaboration.end(id); await settle()
        let oldID = try XCTUnwrap(id)
        var publishedArchive: Data?
        pad.onShowPreview = { [weak self] in
            guard let self, let newID = self.pad.focusedTaskID else { return }
            publishedArchive = try? self.pad.data(newID, "mac-draft.json")
        }
        let newID = try XCTUnwrap(pad.reopen(oldID))
        XCTAssertNotEqual(newID, oldID)
        XCTAssertEqual(publishedArchive, Data("Mac annotations".utf8), "Initial task publication must already include the inherited Mac archive")
        XCTAssertEqual(try pad.data(newID, "ink.drawing"), Data("Pencil ink".utf8))
        XCTAssertEqual(pad.task(oldID)?.state, .completed)
        pad.transport.stop()
    }
    func testOnlyOneSessionAndLegacyCapabilityGate() async throws {
        mac.collaboration.connectionChanged(false)
        XCTAssertThrowsError(try mac.collaboration.start(id))
        mac.collaboration.discoveredPeer()
        try await startAndCommit()
        let another = RelayTask(title: "Queue", origin: .iPad, width: 64, height: 48)
        mac.receive(.init(kind: .task, taskID: another.id, task: another, image: try png()))
        XCTAssertThrowsError(try mac.collaboration.start(another.id))
        XCTAssertEqual(mac.activeTask?.id, id)
        mac.cancel(id); XCTAssertEqual(mac.task(id)?.state, .editing)
    }
}
