import Foundation
import AppKit
import os

private let webHintLog = Logger(subsystem: "com.picelf", category: "WebHint")

/// Chrome-specific DOM hint sampler used by web E2E capture.
///
/// Sampling is asynchronous and best-effort. Frame ingestion must never block on
/// AppleScript or JS execution.
final class ChromeDOMHintProvider {

    static let chromeBundleID = "com.google.Chrome"
    private static let scriptErrorPrefix = "__PICELF_ERROR__:"
    private static let maxConsecutiveFailuresBeforeDisable = 6

    private static let sampleTimeoutSeconds: TimeInterval = 0.40
    private static let minimumSampleIntervalSeconds: TimeInterval = 0.12

    private struct State {
        var sampleCount = 0
        var failureCount = 0
        var consecutiveFailures = 0
        var isDisabled = false
        var sessionActive = false
        var sampleInFlight = false
        var activeRequestID: UInt64 = 0
        var latestHint: WebFrameHint?
        var lastSampleStartAt: CFAbsoluteTime = 0
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: State())
    private let workerQueue = DispatchQueue(label: "com.picelf.webhint.worker", qos: .utility)

    func startSession() {
        stateLock.withLock { state in
            state.sampleCount = 0
            state.failureCount = 0
            state.consecutiveFailures = 0
            state.isDisabled = false
            state.sessionActive = true
            state.sampleInFlight = false
            state.latestHint = nil
            state.lastSampleStartAt = 0
            state.activeRequestID = 0
        }
    }

    func stopSession() {
        let summary = stateLock.withLock { state -> (samples: Int, failures: Int) in
            state.sessionActive = false
            state.sampleInFlight = false
            // Bump request ID so in-flight completions are ignored.
            state.activeRequestID &+= 1
            return (state.sampleCount, state.failureCount)
        }

        if summary.samples > 0 {
            webHintLog.info("WebHint session ended: samples=\(summary.samples), failures=\(summary.failures)")
        }
    }

    /// Schedule a non-blocking hint sample if one is not already running.
    func enqueueSample() {
        let requestID: UInt64?

        requestID = stateLock.withLock { state in
            guard state.sessionActive, !state.isDisabled else { return nil }
            guard !state.sampleInFlight else { return nil }

            let now = CFAbsoluteTimeGetCurrent()
            if state.lastSampleStartAt > 0,
               now - state.lastSampleStartAt < Self.minimumSampleIntervalSeconds {
                return nil
            }

            state.sampleInFlight = true
            state.sampleCount += 1
            state.activeRequestID &+= 1
            state.lastSampleStartAt = now
            return state.activeRequestID
        }

        guard let requestID else { return }

        workerQueue.async { [weak self] in
            guard let self else { return }
            let hint = self.sampleHintSynchronously()
            self.finishSample(requestID: requestID, hint: hint)
        }

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.sampleTimeoutSeconds
        ) { [weak self] in
            self?.handleTimeoutIfNeeded(requestID: requestID)
        }
    }

    /// Returns the latest successfully sampled hint (if any).
    func latestHintSnapshot() -> WebFrameHint? {
        stateLock.withLock { state in
            state.latestHint
        }
    }

    // MARK: - Sampling internals

    private func finishSample(requestID: UInt64, hint: WebFrameHint?) {
        stateLock.withLock { state in
            guard state.sessionActive,
                  state.sampleInFlight,
                  state.activeRequestID == requestID else {
                return
            }

            state.sampleInFlight = false

            if let hint {
                state.latestHint = hint
                state.consecutiveFailures = 0
                return
            }

            state.failureCount += 1
            state.consecutiveFailures += 1
            if !state.isDisabled,
               state.consecutiveFailures >= Self.maxConsecutiveFailuresBeforeDisable {
                state.isDisabled = true
                webHintLog.warning("Chrome DOM hints auto-disabled after \(Self.maxConsecutiveFailuresBeforeDisable) consecutive failures")
            }
        }
    }

    private func handleTimeoutIfNeeded(requestID: UInt64) {
        stateLock.withLock { state in
            guard state.sessionActive,
                  state.sampleInFlight,
                  state.activeRequestID == requestID else {
                return
            }

            state.sampleInFlight = false
            state.failureCount += 1
            state.consecutiveFailures += 1
            // Invalidate stale completion from a hung AppleScript execution.
            state.activeRequestID &+= 1

            webHintLog.debug("Chrome DOM hint sample timed out")

            if !state.isDisabled,
               state.consecutiveFailures >= Self.maxConsecutiveFailuresBeforeDisable {
                state.isDisabled = true
                webHintLog.warning("Chrome DOM hints auto-disabled after \(Self.maxConsecutiveFailuresBeforeDisable) consecutive failures")
            }
        }
    }

    private func sampleHintSynchronously() -> WebFrameHint? {
        guard let payload = executeChromeJavaScript(Self.domProbeJavaScript),
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        guard let scrollY = Self.readDouble(json["scrollY"]),
              let viewportHeight = Self.readDouble(json["viewportHeight"]),
              let documentHeight = Self.readDouble(json["scrollHeight"]),
              let dpr = Self.readDouble(json["devicePixelRatio"])
        else {
            return nil
        }

        let url = (json["url"] as? String) ?? ""
        let hint = WebFrameHint(
            timestamp: Date().timeIntervalSince1970,
            scrollY: scrollY,
            viewportHeight: viewportHeight,
            documentHeight: documentHeight,
            devicePixelRatio: dpr,
            url: url
        )

        return hint.isUsableForHeightEstimation ? hint : nil
    }

    // MARK: - AppleScript bridge

    private func executeChromeJavaScript(_ javaScript: String) -> String? {
        let escaped = Self.escapeForAppleScript(javaScript)
        let source = """
        tell application "Google Chrome"
            if not running then return ""
            if (count of windows) = 0 then return ""
            try
                set payload to execute front window's active tab javascript "\(escaped)"
                if payload is missing value then
                    return ""
                end if
                return payload as text
            on error errMsg number errNum
                return "\(Self.scriptErrorPrefix)" & (errNum as text) & ":" & errMsg
            end try
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            return nil
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let rawMessage = (error[NSAppleScript.errorMessage] as? String)
                ?? error.description

            if Self.isJavaScriptFromAppleEventsDisabledMessage(rawMessage) {
                stateLock.withLock { state in
                    state.isDisabled = true
                }
                webHintLog.warning("Chrome DOM hints disabled: enable Chrome setting 'Allow JavaScript from Apple Events' in View > Developer")
            } else {
                webHintLog.debug("AppleScript error: \(String(describing: error))")
            }
            return nil
        }

        let output = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty else {
            return nil
        }

        if output.hasPrefix(Self.scriptErrorPrefix) {
            let errorMessage = String(output.dropFirst(Self.scriptErrorPrefix.count))
            if Self.isJavaScriptFromAppleEventsDisabledMessage(errorMessage) {
                stateLock.withLock { state in
                    state.isDisabled = true
                }
                webHintLog.warning("Chrome DOM hints disabled: enable Chrome setting 'Allow JavaScript from Apple Events' in View > Developer")
            } else {
                webHintLog.debug("Chrome script error: \(errorMessage)")
            }
            return nil
        }

        return output
    }

    private static func escapeForAppleScript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func readDouble(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func isJavaScriptFromAppleEventsDisabledMessage(_ rawMessage: String) -> Bool {
        let message = rawMessage.lowercased()

        let mentionsAppleAutomation =
            message.contains("apple event")
            || message.contains("apple events")
            || message.contains("apple 事件")
            || message.contains("applescript")

        let mentionsDisabled =
            message.contains("disable")
            || message.contains("disabled")
            || message.contains("关闭")
            || message.contains("已关闭")

        if message.contains("javascript")
            && mentionsAppleAutomation
            && mentionsDisabled {
            return true
        }

        if (message.contains("allow javascript") && mentionsAppleAutomation)
            || message.contains("allow javascript from apple events")
            || message.contains("允许 apple 事件中的 javascript") {
            return true
        }

        return false
    }

    private static let domProbeJavaScript = """
    (() => {
      const doc = document.documentElement || {};
      const body = document.body || {};
      const scrollY = Number(window.scrollY || window.pageYOffset || 0);
      const viewportHeight = Number(window.innerHeight || doc.clientHeight || 0);
      const scrollHeight = Number(Math.max(
        doc.scrollHeight || 0,
        body.scrollHeight || 0,
        doc.offsetHeight || 0,
        body.offsetHeight || 0,
        doc.clientHeight || 0,
        body.clientHeight || 0
      ));
      const devicePixelRatio = Number(window.devicePixelRatio || 1);
      return JSON.stringify({
        scrollY,
        viewportHeight,
        scrollHeight,
        devicePixelRatio,
        url: String(location.href || "")
      });
    })();
    """
}
