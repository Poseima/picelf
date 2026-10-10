import XCTest
import CryptoKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Picelf

final class RelayCryptoTests: XCTestCase {
    func testMutualProofEncryptionAndMatchingPairingCodes() throws {
        let mac = RelayHandshake(role: .mac, signingKey: .init())
        let pad = RelayHandshake(role: .iPad, signingKey: .init())
        try mac.verify(pad.proof(mac.hello), from: pad.hello)
        try pad.verify(mac.proof(pad.hello), from: mac.hello)
        XCTAssertEqual(try mac.code(pad.hello), try pad.code(mac.hello))
        let payload = Data("Private drawing".utf8)
        let sealed = try RelayHandshake.seal(payload, key: mac.sessionKey(pad.hello))
        XCTAssertEqual(try RelayHandshake.open(sealed, key: pad.sessionKey(mac.hello)), payload)
        var corrupted = sealed; corrupted[corrupted.count / 2] ^= 1
        XCTAssertThrowsError(try RelayHandshake.open(corrupted, key: pad.sessionKey(mac.hello)))
    }
    func testReplayedProofAndChangedIdentityAreRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let mac = RelayHandshake(role: .mac, signingKey: key)
        let pad = RelayHandshake(role: .iPad, signingKey: .init())
        let oldProof = try pad.proof(mac.hello)
        let reconnected = RelayHandshake(role: .mac, signingKey: key)
        XCTAssertThrowsError(try reconnected.verify(oldProof, from: pad.hello))
        var impostor = pad.hello
        impostor.identity = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        XCTAssertThrowsError(try mac.verify(oldProof, from: impostor))
        XCTAssertThrowsError(try mac.transcript(mac.hello))
    }
}

@MainActor
final class RelayCoreTests: XCTestCase {
    private var root: URL!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RelayTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: root) }
    private func fixture(_ width: Int = 32, _ height: Int = 24) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5)); ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return try RelayImage.png(XCTUnwrap(ctx.makeImage()))
    }
    func testLimitsAndInvalidImageAreRejectedBeforeDecode() throws {
        try RelayLimits.validate(width: 6000, height: 4000)
        XCTAssertThrowsError(try RelayLimits.validate(width: 6000, height: 4001))
        XCTAssertThrowsError(try RelayLimits.validate(width: Int.max, height: Int.max))
        XCTAssertThrowsError(try RelayLimits.validate(width: 100, height: 0))
        XCTAssertThrowsError(try RelayImage.normalize(Data("not an image".utf8)))
        let png = try fixture()
        let result = try RelayImage.normalize(png)
        XCTAssertEqual(result.1, 32); XCTAssertEqual(result.2, 24)
        let cg = try XCTUnwrap(RelayImage.thumbnail(result.0))
        XCTAssertNotEqual(cg.alphaInfo, .none)
    }
    func testEXIFRotationIsNormalizedToSourcePixelDimensions() throws {
        let png = try fixture(32, 24)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try RelayImage.normalize(data as Data)
        XCTAssertEqual(result.1, 24); XCTAssertEqual(result.2, 32)
    }
    func testFinalCopyIsAcknowledgedOnlyOnceAcrossRestart() throws {
        let png = try fixture()
        let store = try RelayStore(directory: root)
        let original = RelayTask(title: "Mac image", origin: .mac, width: 32, height: 24)
        try store.save(original, base: png)
        let hub = RelayCoordinator(role: .mac, directory: root, startTransport: { _ in })
        var copies = 0
        hub.copyImage = { data in copies += 1; XCTAssertEqual(data, png) }
        let text = try RelayTextDocument(boxes: [.init(text: "备注", x: 1, y: 1, width: 28, fontSize: 8)]).encoded()
        let final = RelayPacket(kind: .final, taskID: original.id, revision: 3, image: png, ink: Data([1, 2, 3]), padText: text, textVersion: 1)
        hub.receive(final); hub.receive(final)
        XCTAssertEqual(copies, 1)
        XCTAssertEqual(hub.task(original.id)?.state, .completed)
        XCTAssertEqual(try hub.data(original.id, "result.png"), png)
        let restarted = RelayCoordinator(role: .mac, directory: root, startTransport: { _ in })
        restarted.copyImage = { _ in XCTFail("Duplicate completion must not overwrite clipboard") }
        restarted.receive(final)
        XCTAssertEqual(restarted.task(original.id)?.state, .completed)
        XCTAssertEqual(try restarted.data(original.id, RelayTextDocument.filename), text)
    }
    func testCopyFailurePreservesImageAndRequiresExplicitRetry() throws {
        let store = try RelayStore(directory: root)
        let task = RelayTask(title: "iPad image", origin: .iPad, width: 32, height: 24)
        let png = try fixture(); try store.save(task, base: png)
        let hub = RelayCoordinator(role: .mac, directory: root, startTransport: { _ in })
        var calls = 0
        hub.copyImage = { _ in calls += 1; throw RelayError.message("Clipboard unavailable") }
        let final = RelayPacket(kind: .final, taskID: task.id, revision: 7, image: png, ink: Data())
        hub.receive(final); hub.receive(final)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(hub.task(task.id)?.state, .copyFailed)
        XCTAssertEqual(try hub.data(task.id, "result.png"), png)
        hub.copyImage = { _ in calls += 1 }
        hub.copyAgain(task.id)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(hub.task(task.id)?.state, .completed)
    }
    func testDeletedCompletedImageCannotBeCopiedAgainByOldRetry() throws {
        let png = try fixture()
        let task = RelayTask(title: "Old iPad image", origin: .iPad, width: 32, height: 24)
        let base = RelayPacket(kind: .task, taskID: task.id, task: task, image: png)
        let final = RelayPacket(kind: .final, taskID: task.id, revision: 3, image: png, ink: Data())
        let hub = RelayCoordinator(role: .mac, directory: root, startTransport: { _ in })
        var copies = 0
        hub.copyImage = { _ in copies += 1 }
        hub.receive(base); hub.receive(final); hub.remove(task.id)
        XCTAssertEqual(copies, 1)
        let restarted = RelayCoordinator(role: .mac, directory: root, startTransport: { _ in })
        restarted.copyImage = { _ in XCTFail("Pruned history must retain its receipt") }
        restarted.receive(base); restarted.receive(final)
        XCTAssertNil(restarted.task(task.id))
        XCTAssertEqual(try RelayStore(directory: root).completedRevisions[task.id], 3)
    }
    func testInterruptedClipboardAttemptIsNotAutomaticallyRepeated() throws {
        let store = try RelayStore(directory: root)
        var task = RelayTask(title: "Interrupted", origin: .mac, width: 32, height: 24)
        task.state = .copying; task.receiptRevision = 2; task.revision = 2
        let png = try fixture(); try store.save(task, base: png, result: png)
        let hub = RelayCoordinator(role: .mac, directory: root, startTransport: { _ in })
        hub.copyImage = { _ in XCTFail("Crash recovery must not write clipboard automatically") }
        hub.receive(.init(kind: .final, taskID: task.id, revision: 2, image: png, ink: Data()))
        XCTAssertEqual(hub.task(task.id)?.state, .copyFailed)
    }
    func testDuplicateTaskCannotOverwriteInkAndNewImageDoesNotReplaceActive() throws {
        let png = try fixture()
        let hub = RelayCoordinator(role: .iPad, directory: root, startTransport: { _ in })
        let first = RelayTask(title: "First", origin: .mac, width: 32, height: 24)
        var second = RelayTask(title: "Second", origin: .mac, width: 32, height: 24)
        second.createdAt = Date().addingTimeInterval(-600) // Clock skew must not replace the current canvas.
        let packet = RelayPacket(kind: .task, taskID: first.id, task: first, image: png)
        hub.receive(packet); hub.beginEditing(first.id)
        try hub.saveDrawing(first.id, ink: Data([4, 5]), revision: 4)
        hub.receive(packet)
        hub.receive(.init(kind: .task, taskID: second.id, task: second, image: png))
        XCTAssertEqual(hub.activeTask?.id, first.id)
        XCTAssertEqual(try hub.data(first.id, "ink.drawing"), Data([4, 5]))
        hub.cancel(first.id)
        XCTAssertEqual(hub.activeTask?.id, second.id)
    }
    func testCancelledAndDeletedTaskCannotResurrectAfterReconnect() throws {
        let png = try fixture()
        let hub = RelayCoordinator(role: .iPad, directory: root, startTransport: { _ in })
        let task = RelayTask(title: "Deleted", origin: .mac, width: 32, height: 24)
        let packet = RelayPacket(kind: .task, taskID: task.id, task: task, image: png)
        hub.receive(packet); hub.cancel(task.id); hub.remove(task.id)
        let restarted = RelayCoordinator(role: .iPad, directory: root, startTransport: { _ in })
        restarted.receive(packet)
        XCTAssertNil(restarted.task(task.id))
    }
    func testHistoryPruningNeverDeletesUnfinishedOrCancelledDrafts() throws {
        let store = try RelayStore(directory: root)
        for index in 0..<35 {
            var task = RelayTask(title: "Finished \(index)", origin: .mac, width: 32, height: 24)
            task.state = .completed; try store.save(task)
        }
        var draft = RelayTask(title: "Draft", origin: .iPad, width: 32, height: 24)
        draft.state = .cancelled; try store.save(draft, ink: Data([7]))
        let waiting = RelayTask(title: "Pending", origin: .mac, width: 32, height: 24)
        try store.save(waiting)
        try store.prune()
        XCTAssertEqual(store.tasks.filter { $0.state == .completed }.count, 30)
        XCTAssertNotNil(store.task(draft.id)); XCTAssertNotNil(store.task(waiting.id))
    }
    func testFailedReceiptSurvivesRestartAndOnlyMatchingSuccessClearsIt() throws {
        let store = try RelayStore(directory: root)
        var task = RelayTask(title: "Return", origin: .mac, width: 32, height: 24)
        task.state = .returning; task.revision = 4
        try store.save(task, base: fixture(), result: fixture())
        let hub = RelayCoordinator(role: .iPad, directory: root, startTransport: { _ in })
        hub.receive(.init(kind: .receipt, taskID: task.id, revision: 4, success: false, message: "Clipboard busy"))
        let restarted = RelayCoordinator(role: .iPad, directory: root, startTransport: { _ in })
        let failed = try XCTUnwrap(restarted.task(task.id))
        XCTAssertEqual(failed.copyFailureMessage, "Clipboard busy")
        XCTAssertFalse(RelayTaskPresentation(task: failed, role: .iPad, connected: true).isWaiting)
        restarted.receive(.init(kind: .receipt, taskID: task.id, revision: 3, success: true))
        XCTAssertNotNil(restarted.task(task.id)?.copyFailureMessage)
        restarted.receive(.init(kind: .receipt, taskID: task.id, revision: 4, success: true))
        XCTAssertEqual(restarted.task(task.id)?.state, .completed)
        XCTAssertNil(restarted.task(task.id)?.copyFailureMessage)
        let newID = try XCTUnwrap(restarted.reopen(task.id))
        XCTAssertNotEqual(newID, task.id)
        XCTAssertEqual(restarted.task(task.id)?.state, .completed)
        XCTAssertNil(restarted.task(newID)?.copyFailureMessage)
    }
    func testWrongDimensionsAndStaleReceiptDoNotCompleteTask() throws {
        let store = try RelayStore(directory: root)
        var task = RelayTask(title: "Pending", origin: .mac, width: 32, height: 24)
        task.state = .returning; task.revision = 8; try store.save(task)
        let mac = RelayCoordinator(role: .mac, directory: root, startTransport: { _ in })
        mac.copyImage = { _ in XCTFail("Wrong size must not be copied") }
        mac.receive(.init(kind: .final, taskID: task.id, revision: 8, image: try fixture(24, 32), ink: Data()))
        XCTAssertNotNil(mac.errorMessage)
        let pad = RelayCoordinator(role: .iPad, directory: root, startTransport: { _ in })
        pad.receive(.init(kind: .receipt, taskID: task.id, revision: 7, success: true))
        XCTAssertEqual(pad.task(task.id)?.state, .returning)
        pad.receive(.init(kind: .receipt, taskID: task.id, revision: 8, success: true))
        XCTAssertEqual(pad.task(task.id)?.state, .completed)
    }
}
