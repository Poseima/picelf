import XCTest
@testable import Picelf

@MainActor
final class RelayPairingTests: XCTestCase {
    func testTrustedSideShowsMatchingCodeWhenPeerNeedsConfirmation() async {
        let model = RelayPairingPresentation(), id = UUID()
        model.begin(id, peer: "iPad")
        model.showCodeWhileWaitingForPeer(id, code: "246810")
        XCTAssertNil(model.notice, "Normal reconnections should not flash a card")
        try? await Task.sleep(nanoseconds: 1_700_000_000)
        XCTAssertEqual(model.notice?.code, "246810")
        XCTAssertEqual(model.notice?.localConfirmed, true)
        XCTAssertEqual(model.notice?.remoteConfirmed, false)
        model.connected(id)
        XCTAssertEqual(model.notice?.phase, .success)
    }
    func testDelayedConfirmationCannotReplaceSuccessCancellationOrNewAttempt() async {
        let connected = RelayPairingPresentation(), cancelled = RelayPairingPresentation(), replaced = RelayPairingPresentation()
        let id = UUID(), next = UUID()
        for model in [connected, cancelled, replaced] {
            model.begin(id, peer: "iPad")
            model.showCodeWhileWaitingForPeer(id, code: "111111")
        }
        connected.connected(id)
        cancelled.dismiss(id)
        replaced.begin(next, peer: "Mac"); replaced.request(next, code: "222222")
        try? await Task.sleep(nanoseconds: 1_700_000_000)
        XCTAssertNil(connected.notice)
        XCTAssertNil(cancelled.notice)
        XCTAssertEqual(replaced.notice?.code, "222222")
        XCTAssertEqual(replaced.notice?.localConfirmed, false)
    }
    func testDuplicateRequestPreservesBothConfirmationOrders() {
        for localFirst in [true, false] {
            let model = RelayPairingPresentation(), id = UUID()
            model.begin(id, peer: "iPad"); model.request(id, code: "123456")
            model.confirm(id, local: localFirst, remote: !localFirst)
            XCTAssertEqual(model.notice?.message, localFirst
                ? L10n.localized("等待另一台设备确认", "Waiting for the other device")
                : L10n.localized("对方已确认，请核对配对码", "The other device confirmed. Check the pairing code"))
            model.request(id, code: "999999")
            XCTAssertEqual(model.notice?.code, "123456")
            model.confirm(id, local: true, remote: true)
            XCTAssertEqual(model.notice?.localConfirmed, true)
            XCTAssertEqual(model.notice?.remoteConfirmed, true)
            model.connected(id)
            XCTAssertEqual(model.notice?.phase, .success)
            XCTAssertNil(model.notice?.code)
        }
    }
    func testCancelledAndOldAttemptsCannotResurrectCard() {
        let model = RelayPairingPresentation(), old = UUID(), current = UUID()
        model.begin(old, peer: "old"); model.request(old, code: "123456")
        model.dismiss(old); model.request(old, code: "123456")
        XCTAssertNil(model.notice)
        model.begin(current, peer: "current"); model.request(current, code: "654321")
        model.confirm(old, local: true, remote: true)
        model.failed(old, message: "old failure"); model.connected(old); model.dismiss(old)
        XCTAssertEqual(model.notice?.id, current)
        XCTAssertEqual(model.notice?.code, "654321")
        XCTAssertEqual(model.notice?.localConfirmed, false)
    }
    func testFailureSurvivesDisconnectAndClearsForRetry() {
        let model = RelayPairingPresentation(), id = UUID()
        model.begin(id, peer: "Mac"); model.request(id, code: "123456")
        model.failed(id, message: "specific error"); model.disconnected(id)
        XCTAssertEqual(model.notice?.error, "specific error")
        model.request(id, code: "987654")
        XCTAssertEqual(model.notice?.phase, .failure)
        let retry = UUID(); model.begin(retry, peer: "Mac")
        XCTAssertNil(model.notice); XCTAssertTrue(model.connecting)
        model.request(retry, code: "234567")
        XCTAssertEqual(model.notice?.id, retry)
    }
    func testPendingConnectionInterruptedBeforeCodeShowsRecovery() {
        let model = RelayPairingPresentation(), id = UUID()
        model.begin(id, peer: "Mac"); model.disconnected(id)
        XCTAssertEqual(model.notice?.phase, .failure)
        XCTAssertFalse(model.connecting)
    }
    func testTrustedReconnectUsesToastAndDiscoveryDismissalSurvivesAttempts() {
        let model = RelayPairingPresentation(), id = UUID()
        model.dismissDiscovery(); model.begin(id, peer: "Mac"); model.connected(id)
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.connectionToast, L10n.localized("已连接 · Mac", "Connected · Mac"))
        model.disconnected(id)
        XCTAssertNil(model.connectionToast)
        model.begin(UUID(), peer: "Mac")
        XCTAssertTrue(model.discoveryDismissed)
        model.disconnected(id)
        XCTAssertTrue(model.connecting, "An old disconnect must not clear a newer attempt")
    }
    func testDeferredSuccessOnlyExpiresOnceActuallyPresented() async {
        let model = RelayPairingPresentation(), id = UUID()
        model.begin(id, peer: "Mac"); model.request(id, code: "123456"); model.connected(id)
        XCTAssertEqual(model.notice?.phase, .success)
        await model.successWasShown(id)
        XCTAssertNil(model.notice)
        let current = UUID(); model.begin(current, peer: "Mac"); model.request(current, code: "654321")
        await model.successWasShown(id)
        XCTAssertEqual(model.notice?.id, current)
    }
}
