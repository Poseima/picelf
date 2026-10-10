import AVFoundation
import ScreenCaptureKit
import os

private let log = Logger(subsystem: "com.picelf", category: "ScreenRecorder")

@MainActor
final class ScreenRecorder: NSObject {
    struct ResolvedRecordingGeometry: Equatable {
        let sourceRect: CGRect?
        let outputWidth: Int
        let outputHeight: Int
    }

    enum CaptureTarget {
        case window(SCWindow, requestedSourceRect: CGRect?)
        case display(SCDisplay, requestedSourceRect: CGRect?)

        var requestedSourceRect: CGRect? {
            switch self {
            case .window(_, let requestedSourceRect), .display(_, let requestedSourceRect):
                return requestedSourceRect
            }
        }
    }

    let configuration: RecordingConfiguration

    private var stream: SCStream?
    // nonisolated(unsafe) because these are set once on MainActor in startRecording(),
    // then read from the sampleQueue in SCStreamOutput. The gate lock ensures ordering.
    nonisolated(unsafe) private var writer: AVAssetWriter!
    nonisolated(unsafe) private var videoInput: AVAssetWriterInput!
    nonisolated(unsafe) private var audioInput: AVAssetWriterInput?
    nonisolated(unsafe) private var micInput: AVAssetWriterInput?
    nonisolated(unsafe) private var tempURL: URL!
    nonisolated(unsafe) private var activeGeometry: ResolvedRecordingGeometry?

    // Microphone capture session
    private var micSession: AVCaptureSession?

    // MARK: - Thread-safe gate state

    private struct RecorderGateState {
        var isRecording = false
        var isPaused = false
        var totalPauseDuration: CMTime = .zero
        var pauseStartPTS: CMTime = .zero
        var lastReceivedPTS: CMTime = .zero
        var pendingResume = false
        var sessionStartPTS: CMTime = .invalid
        var hasWrittenFirstSample = false
        var hasWrittenVideoSample = false
        var appendFailureReason: String?
        var didInspectFirstVideoSample = false
    }

    private let gate = OSAllocatedUnfairLock(initialState: RecorderGateState())
    private let sampleQueue = DispatchQueue(label: "com.picelf.recording", qos: .userInteractive)

    // MARK: - Elapsed time (wall-clock anchored)

    @Published private(set) var elapsedSeconds: TimeInterval = 0
    private var startDate: Date?
    private var totalWallPauseDuration: TimeInterval = 0
    private var pauseStartDate: Date?
    private var elapsedTimer: Timer?
    private let microphoneAuthorizationStatusProvider: () -> AVAuthorizationStatus

    // MARK: - Callbacks

    var onUnexpectedStop: ((_ videoURL: URL, _ elapsed: TimeInterval, _ error: Error) -> Void)?

    // MARK: - Init

    init(
        configuration: RecordingConfiguration,
        microphoneAuthorizationStatusProvider: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        }
    ) {
        self.configuration = configuration
        self.microphoneAuthorizationStatusProvider = microphoneAuthorizationStatusProvider
        super.init()
    }

    #if DEBUG
    deinit {
        elapsedTimer?.invalidate()
        log.debug("ScreenRecorder deinit")
    }
    #endif

    // MARK: - Sample action

    private enum SampleAction {
        case drop
        case startSessionAndAppend(sessionTime: CMTime)
        case append(offset: CMTime)
        case durationLimitReached
    }

    // MARK: - Start

    func startRecording(target: CaptureTarget) async throws {
        let filter: SCContentFilter
        let fallbackContentRect: CGRect
        switch target {
        case .window(let window, _):
            filter = SCContentFilter(desktopIndependentWindow: window)
            fallbackContentRect = window.frame
        case .display(let display, _):
            let excludedApplications = await Self.currentApplicationsForDisplayCaptureExclusion()
            filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
            fallbackContentRect = display.frame
        }

        let filterContentRect = filter.contentRect
        let contentRect = Self.resolveContentRect(
            preferred: filterContentRect,
            fallback: fallbackContentRect,
            requestedSourceRect: target.requestedSourceRect
        )
        let filterScale = CGFloat(filter.pointPixelScale)
        let scaleFactor = filterScale > 0 ? filterScale : CGFloat(max(1, configuration.scaleFactor))

        guard let resolved = Self.resolveGeometry(
            contentRect: contentRect,
            requestedSourceRect: target.requestedSourceRect,
            scaleFactor: scaleFactor,
            resolution: configuration.resolution
        ) else {
            throw RecordingError.writerCreationFailed("Invalid recording geometry")
        }
        activeGeometry = resolved
        let ext = configuration.format.fileExtension
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("picelf-rec-\(UUID().uuidString.prefix(8)).\(ext)")

        // AVAssetWriter
        writer = try AVAssetWriter(outputURL: tempURL, fileType: configuration.format.avFileType)

        // Video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: resolved.outputWidth,
            AVVideoHeightKey: resolved.outputHeight
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)

        // System audio input
        if configuration.captureSystemAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInput = input
        }

        // Microphone input and capture session
        if let micID = configuration.microphoneDeviceID {
            try validateMicrophoneAccessIfNeeded()

            let micSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            micInput = input

            // Start microphone capture session
            startMicrophoneCapture(deviceID: micID)
            log.info("Microphone enabled: \(micID)")
        }

        writer.startWriting()

        // SCStream configuration
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = resolved.outputWidth
        streamConfig.height = resolved.outputHeight
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.frameRate))
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.showsCursor = configuration.showsCursor
        streamConfig.capturesAudio = configuration.captureSystemAudio
        streamConfig.queueDepth = 8
        streamConfig.destinationRect = CGRect(x: 0, y: 0, width: resolved.outputWidth, height: resolved.outputHeight)

        if let sourceRect = resolved.sourceRect {
            streamConfig.sourceRect = sourceRect
        }

        stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        guard let stream else { throw RecordingError.writerCreationFailed("SCStream init failed") }

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if configuration.captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }

        gate.withLock { $0.isRecording = true }

        try await stream.startCapture()
        let targetDescription: String
        switch target {
        case .window(let window, _):
            targetDescription = "window:\(window.windowID)"
        case .display(let display, _):
            targetDescription = "display:\(display.displayID)"
        }
        let sourceRectDescription = resolved.sourceRect?.debugDescription ?? "full"
        let requestedSourceRectDescription = target.requestedSourceRect?.debugDescription ?? "full"
        log.info(
            "Recording geometry target=\(targetDescription, privacy: .public) contentRect=\(contentRect.debugDescription, privacy: .public) requestedSourceRect=\(requestedSourceRectDescription, privacy: .public) resolvedSourceRect=\(sourceRectDescription, privacy: .public) scale=\(scaleFactor, privacy: .public) size=\(resolved.outputWidth)x\(resolved.outputHeight)"
        )
        log.info(
            "Recording started target=\(targetDescription, privacy: .public) size=\(resolved.outputWidth)x\(resolved.outputHeight) sourceRect=\(sourceRectDescription, privacy: .public) @ \(self.configuration.frameRate)fps"
        )

        // Start elapsed timer
        startDate = Date()
        totalWallPauseDuration = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
    }

    // MARK: - Pause / Resume

    func pauseRecording() {
        gate.withLock { state in
            state.isPaused = true
            state.pauseStartPTS = state.lastReceivedPTS
        }
        pauseStartDate = Date()
        elapsedTimer?.invalidate()
        log.info("Recording paused")
    }

    func resumeRecording() {
        gate.withLock { state in
            state.isPaused = false
            state.pendingResume = true
        }
        if let pauseStart = pauseStartDate {
            totalWallPauseDuration += Date().timeIntervalSince(pauseStart)
        }
        pauseStartDate = nil
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
        log.info("Recording resumed")
    }

    // MARK: - Stop

    func stopRecording() async throws -> (url: URL, duration: TimeInterval) {
        elapsedTimer?.invalidate()
        elapsedTimer = nil

        // 1. Stop accepting new samples immediately.
        gate.withLock { state in state.isRecording = false }

        // 2. Stop stream first (stops delivery), then drain the sample queue so late callbacks
        // can't append after inputs are marked finished.
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        await drainSampleQueue()

        // 3. Stop microphone capture and drain again because AVCapture callbacks use the same queue.
        stopMicrophoneCapture()
        await drainSampleQueue()

        let snapshot = gate.withLock { state in
            (
                hasWrittenFirstSample: state.hasWrittenFirstSample,
                hasWrittenVideoSample: state.hasWrittenVideoSample,
                appendFailureReason: state.appendFailureReason
            )
        }

        // 4. Check we got at least one sample.
        guard snapshot.hasWrittenFirstSample else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: tempURL)
            throw RecordingError.noFramesCaptured
        }

        // A screen recording without any video samples is not a usable recording.
        guard snapshot.hasWrittenVideoSample else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: tempURL)
            if let appendFailureReason = snapshot.appendFailureReason {
                throw RecordingError.finalizationFailed(appendFailureReason)
            }
            throw RecordingError.noFramesCaptured
        }

        // 5. Finalize.
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            let reason = Self.finalizationFailureReason(
                writer: writer,
                appendFailureReason: snapshot.appendFailureReason
            )
            log.error("Failed to finalize recording status=\(Self.writerStatusDescription(self.writer.status), privacy: .public) reason=\(reason, privacy: .public)")
            throw RecordingError.finalizationFailed(reason)
        }

        let finalElapsed = elapsedSeconds
        log.info("Recording stopped: \(String(format: "%.1f", finalElapsed))s → \(self.tempURL.lastPathComponent)")
        activeGeometry = nil
        return (tempURL, finalElapsed)
    }

    // MARK: - Private

    private func updateElapsed() {
        guard let start = startDate else { return }
        elapsedSeconds = Date().timeIntervalSince(start) - totalWallPauseDuration
    }

    nonisolated private static func resolveContentRect(
        preferred: CGRect,
        fallback: CGRect,
        requestedSourceRect: CGRect?
    ) -> CGRect {
        let preferredIsValid = preferred.width > 0 && preferred.height > 0
        let fallbackIsValid = fallback.width > 0 && fallback.height > 0

        guard preferredIsValid else { return fallback }
        guard fallbackIsValid else { return preferred }
        guard let requestedSourceRect else { return preferred }

        let preferredOverlap = intersectionArea(preferred, requestedSourceRect)
        let fallbackOverlap = intersectionArea(fallback, requestedSourceRect)
        return fallbackOverlap > preferredOverlap ? fallback : preferred
    }

    private static func currentApplicationsForDisplayCaptureExclusion() async -> [SCRunningApplication] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return [] }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return content.applications.filter { $0.bundleIdentifier == bundleIdentifier }
        } catch {
            log.warning("Unable to resolve Picelf application for display capture exclusion: \(error.localizedDescription)")
            return []
        }
    }

    nonisolated private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return max(0, intersection.width) * max(0, intersection.height)
    }

    nonisolated static func resolveGeometry(
        contentRect: CGRect,
        requestedSourceRect: CGRect?,
        scaleFactor: CGFloat,
        resolution: RecordingResolution
    ) -> ResolvedRecordingGeometry? {
        guard contentRect.width > 0, contentRect.height > 0 else { return nil }

        let scale = max(1, scaleFactor)
        let fullPixelWidth = max(2, Int(round(contentRect.width * scale)))
        let fullPixelHeight = max(2, Int(round(contentRect.height * scale)))

        let normalizedPixelRect: CGRect
        if let requestedSourceRect {
            let clampedSourceRect = requestedSourceRect.intersection(contentRect)
            guard !clampedSourceRect.isNull,
                  !clampedSourceRect.isEmpty,
                  clampedSourceRect.width > 0,
                  clampedSourceRect.height > 0 else {
                return nil
            }

            let localRect = CGRect(
                x: clampedSourceRect.minX - contentRect.minX,
                y: clampedSourceRect.minY - contentRect.minY,
                width: clampedSourceRect.width,
                height: clampedSourceRect.height
            )
            guard let pixelRect = Self.pixelCropRect(
                localRect: localRect,
                scaleFactor: scale,
                imageWidth: fullPixelWidth,
                imageHeight: fullPixelHeight
            ) else {
                return nil
            }
            normalizedPixelRect = evenTrimmedPixelRect(pixelRect)
        } else {
            normalizedPixelRect = evenTrimmedPixelRect(
                CGRect(x: 0, y: 0, width: fullPixelWidth, height: fullPixelHeight)
            )
        }

        guard normalizedPixelRect.width >= 2, normalizedPixelRect.height >= 2 else {
            return nil
        }

        let outputSize: (width: Int, height: Int)
        switch resolution {
        case .original:
            outputSize = (Int(normalizedPixelRect.width), Int(normalizedPixelRect.height))
        case .fhd:
            outputSize = clampSize(Int(normalizedPixelRect.width), Int(normalizedPixelRect.height), maxLong: 1920)
        case .hd:
            outputSize = clampSize(Int(normalizedPixelRect.width), Int(normalizedPixelRect.height), maxLong: 1280)
        }

        let sourceRect = CGRect(
            x: contentRect.minX + normalizedPixelRect.minX / scale,
            y: contentRect.minY + normalizedPixelRect.minY / scale,
            width: normalizedPixelRect.width / scale,
            height: normalizedPixelRect.height / scale
        )
        let sourceRectOrNil: CGRect? = Int(normalizedPixelRect.minX) == 0 &&
            Int(normalizedPixelRect.minY) == 0 &&
            Int(normalizedPixelRect.width) == fullPixelWidth &&
            Int(normalizedPixelRect.height) == fullPixelHeight
            ? nil
            : sourceRect

        return ResolvedRecordingGeometry(
            sourceRect: sourceRectOrNil,
            outputWidth: outputSize.width,
            outputHeight: outputSize.height
        )
    }

    nonisolated private static func pixelCropRect(
        localRect: CGRect,
        scaleFactor: CGFloat,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect? {
        let scale = max(1, scaleFactor)
        let scaledXMin = Int(floor(localRect.minX * scale))
        let scaledYMin = Int(floor(localRect.minY * scale))
        let scaledXMax = Int(ceil(localRect.maxX * scale))
        let scaledYMax = Int(ceil(localRect.maxY * scale))

        let clampedXMin = max(0, min(imageWidth, scaledXMin))
        let clampedYMin = max(0, min(imageHeight, scaledYMin))
        let clampedXMax = max(clampedXMin, min(imageWidth, scaledXMax))
        let clampedYMax = max(clampedYMin, min(imageHeight, scaledYMax))

        let cropWidth = clampedXMax - clampedXMin
        let cropHeight = clampedYMax - clampedYMin
        guard cropWidth > 0, cropHeight > 0 else { return nil }

        return CGRect(x: clampedXMin, y: clampedYMin, width: cropWidth, height: cropHeight)
    }

    nonisolated private static func evenTrimmedPixelRect(_ rect: CGRect) -> CGRect {
        var normalized = rect
        if Int(normalized.width) % 2 != 0 {
            normalized.size.width -= 1
        }
        if Int(normalized.height) % 2 != 0 {
            normalized.size.height -= 1
        }
        return normalized
    }

    nonisolated private static func clampSize(_ w: Int, _ h: Int, maxLong: Int) -> (width: Int, height: Int) {
        let evenW = max(2, w & ~1)
        let evenH = max(2, h & ~1)
        let longer = max(evenW, evenH)
        guard longer > maxLong else { return (evenW, evenH) }
        let ratio = Double(maxLong) / Double(longer)
        let newW = Int(Double(evenW) * ratio) & ~1
        let newH = Int(Double(evenH) * ratio) & ~1
        return (max(2, newW), max(2, newH))
    }

    func validateMicrophoneAccessIfNeeded() throws {
        guard configuration.microphoneDeviceID != nil else { return }
        guard microphoneAuthorizationStatusProvider() == .authorized else {
            throw RecordingError.microphoneAccessDenied
        }
    }

    // MARK: - Microphone Capture

    private func startMicrophoneCapture(deviceID: String) {
        let session = AVCaptureSession()

        // Find the specified microphone device
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        var targetDevice: AVCaptureDevice?
        if let device = discovery.devices.first(where: { $0.uniqueID == deviceID }) {
            targetDevice = device
        } else {
            log.warning("Microphone device not found: \(deviceID), using default")
            targetDevice = AVCaptureDevice.default(for: .audio)
        }

        guard let device = targetDevice else {
            log.error("No audio capture device available")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            log.error("Failed to create microphone input: \(error)")
            return
        }

        let output = AVCaptureAudioDataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setSampleBufferDelegate(self, queue: sampleQueue)
        }

        session.startRunning()
        micSession = session
        log.info("Microphone capture session started")
    }

    private func stopMicrophoneCapture() {
        micSession?.stopRunning()
        micSession = nil
        log.info("Microphone capture session stopped")
    }

    private func drainSampleQueue() async {
        await withCheckedContinuation { continuation in
            sampleQueue.async {
                continuation.resume()
            }
        }
    }

    nonisolated private static func writerStatusDescription(_ status: AVAssetWriter.Status) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .writing:
            return "writing"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .cancelled:
            return "cancelled"
        @unknown default:
            return "unknown(\(status.rawValue))"
        }
    }

    nonisolated private static func finalizationFailureReason(
        writer: AVAssetWriter,
        appendFailureReason: String?
    ) -> String {
        let writerReason = writer.error?.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = [
            appendFailureReason?.isEmpty == false ? appendFailureReason : nil,
            writerReason?.isEmpty == false ? writerReason : nil,
            "writer status: \(writerStatusDescription(writer.status))"
        ].compactMap { $0 }
        return pieces.joined(separator: " | ")
    }

    nonisolated private func appendSample(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType, offset: CMTime) {
        guard writer.status == .writing else { return }

        var buffer = sampleBuffer
        if CMTimeCompare(offset, .zero) != 0 {
            if let adjusted = adjustTimestamp(sampleBuffer, offset: offset) {
                buffer = adjusted
            }
        }

        switch type {
        case .screen:
            if videoInput.isReadyForMoreMediaData {
                if let mismatchReason = validateVideoSampleGeometry(buffer) {
                    recordAppendFailure(mediaKind: "video", reason: mismatchReason)
                    return
                }
                let appended = videoInput.append(buffer)
                if appended {
                    gate.withLock { $0.hasWrittenVideoSample = true }
                } else {
                    recordAppendFailure(mediaKind: "video")
                }
            }
        case .audio:
            if let audioInput, audioInput.isReadyForMoreMediaData {
                if !audioInput.append(buffer) {
                    recordAppendFailure(mediaKind: "system audio")
                }
            }
        case .microphone:
            // Microphone is handled by AVCaptureAudioDataOutput, not SCStream.
            break
        @unknown default:
            break
        }
    }

    nonisolated private func adjustTimestamp(_ buffer: CMSampleBuffer, offset: CMTime) -> CMSampleBuffer? {
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        let dur = CMSampleBufferGetDuration(buffer)
        let newPTS = CMTimeSubtract(pts, offset)

        var timingInfo = CMSampleTimingInfo(
            duration: dur,
            presentationTimeStamp: newPTS,
            decodeTimeStamp: .invalid
        )

        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: buffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &newBuffer
        )
        return newBuffer
    }

    nonisolated private func recordAppendFailure(mediaKind: String) {
        recordAppendFailure(mediaKind: mediaKind, reason: nil)
    }

    nonisolated private func recordAppendFailure(mediaKind: String, reason explicitReason: String?) {
        let writerReason = writer.error?.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = explicitReason ?? (writerReason?.isEmpty == false ? writerReason! : "append returned false")
        let detail = "Failed to append \(mediaKind) sample: \(reason)"
        let shouldLog = gate.withLock { state -> Bool in
            if state.appendFailureReason == nil {
                state.appendFailureReason = detail
                state.isRecording = false
                return true
            }
            return false
        }
        if shouldLog {
            log.error("\(detail, privacy: .public)")
        }
    }

    nonisolated private func validateVideoSampleGeometry(_ sampleBuffer: CMSampleBuffer) -> String? {
        guard let activeGeometry,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        else {
            return nil
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let sampleWidth = Int(dimensions.width)
        let sampleHeight = Int(dimensions.height)

        let shouldLog = gate.withLock { state -> Bool in
            if state.didInspectFirstVideoSample {
                return false
            }
            state.didInspectFirstVideoSample = true
            return true
        }
        if shouldLog {
            log.info(
                "First video sample dimensions=\(sampleWidth)x\(sampleHeight) expected=\(activeGeometry.outputWidth)x\(activeGeometry.outputHeight)"
            )
        }

        guard sampleWidth == activeGeometry.outputWidth, sampleHeight == activeGeometry.outputHeight else {
            return "Video sample dimensions \(sampleWidth)x\(sampleHeight) did not match configured writer size \(activeGeometry.outputWidth)x\(activeGeometry.outputHeight)"
        }
        return nil
    }
}

// MARK: - SCStreamOutput

extension ScreenRecorder: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        guard writer.status == .writing else { return }
        // Display recording can deliver idle frames with no pixel data — skip them.
        if type == .screen, sampleBuffer.imageBuffer == nil { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let canStartSession = type == .screen

        let action = gate.withLock { state -> SampleAction in
            guard state.isRecording else { return .drop }

            if state.isPaused {
                if state.hasWrittenFirstSample {
                    state.lastReceivedPTS = pts
                }
                return .drop
            }

            // Only video is allowed to anchor the writer session.
            if !state.hasWrittenFirstSample {
                guard canStartSession else { return .drop }
                state.hasWrittenFirstSample = true
                state.sessionStartPTS = pts
                state.lastReceivedPTS = pts
                return .startSessionAndAppend(sessionTime: pts)
            }

            if state.sessionStartPTS.isValid, CMTimeCompare(pts, state.sessionStartPTS) < 0 {
                return .drop
            }

            // First sample after resume: compute pause gap
            if state.pendingResume {
                let pauseGap = CMTimeSubtract(pts, state.pauseStartPTS)
                state.totalPauseDuration = CMTimeAdd(state.totalPauseDuration, pauseGap)
                state.pendingResume = false
            }

            state.lastReceivedPTS = pts

            // Duration limit check
            if configuration.durationLimitSeconds > 0 {
                let adjustedPTS = CMTimeSubtract(pts, state.totalPauseDuration)
                let limitTime = CMTimeMakeWithSeconds(Double(configuration.durationLimitSeconds), preferredTimescale: 600)
                if CMTimeCompare(adjustedPTS, limitTime) >= 0 {
                    return .durationLimitReached
                }
            }

            return .append(offset: state.totalPauseDuration)
        }

        switch action {
        case .drop:
            return
        case .startSessionAndAppend(let sessionTime):
            writer.startSession(atSourceTime: sessionTime)
            appendSample(sampleBuffer, type: type, offset: .zero)
        case .append(let offset):
            appendSample(sampleBuffer, type: type, offset: offset)
        case .durationLimitReached:
            Task { @MainActor in
                try? await self.stopRecording()
            }
        }
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("SCStream stopped unexpectedly: \(error.localizedDescription)")
        gate.withLock { state in state.isRecording = false }
        // Stop microphone capture on error
        Task { @MainActor in
            self.stopMicrophoneCapture()
        }
        // These are nonisolated(unsafe) — safe to access from sampleQueue after gate lock
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()
        let writerRef = writer!
        let urlRef = tempURL!
        Task {
            await writerRef.finishWriting()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.elapsedTimer?.invalidate()
                self.onUnexpectedStop?(urlRef, self.elapsedSeconds, error)
            }
        }
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension ScreenRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard sampleBuffer.isValid else { return }
        guard writer.status == .writing else { return }
        guard let micInput, micInput.isReadyForMoreMediaData else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        let action = gate.withLock { state -> SampleAction in
            guard state.isRecording else { return .drop }
            guard !state.isPaused else { return .drop }

            // Microphone samples are ignored until the first video sample anchors the session.
            if !state.hasWrittenFirstSample {
                return .drop
            }

            if state.sessionStartPTS.isValid, CMTimeCompare(pts, state.sessionStartPTS) < 0 {
                return .drop
            }

            // First sample after resume: compute pause gap
            if state.pendingResume {
                let pauseGap = CMTimeSubtract(pts, state.pauseStartPTS)
                state.totalPauseDuration = CMTimeAdd(state.totalPauseDuration, pauseGap)
                state.pendingResume = false
            }

            state.lastReceivedPTS = pts

            // Duration limit check
            if configuration.durationLimitSeconds > 0 {
                let adjustedPTS = CMTimeSubtract(pts, state.totalPauseDuration)
                let limitTime = CMTimeMakeWithSeconds(Double(configuration.durationLimitSeconds), preferredTimescale: 600)
                if CMTimeCompare(adjustedPTS, limitTime) >= 0 {
                    return .durationLimitReached
                }
            }

            return .append(offset: state.totalPauseDuration)
        }

        switch action {
        case .drop:
            return
        case .startSessionAndAppend(let sessionTime):
            writer.startSession(atSourceTime: sessionTime)
            appendMicSample(sampleBuffer, offset: .zero)
        case .append(let offset):
            appendMicSample(sampleBuffer, offset: offset)
        case .durationLimitReached:
            Task { @MainActor in
                try? await self.stopRecording()
            }
        }
    }

    nonisolated private func appendMicSample(_ sampleBuffer: CMSampleBuffer, offset: CMTime) {
        guard writer.status == .writing else { return }
        guard let micInput, micInput.isReadyForMoreMediaData else { return }

        var buffer = sampleBuffer
        if CMTimeCompare(offset, .zero) != 0 {
            if let adjusted = adjustTimestamp(sampleBuffer, offset: offset) {
                buffer = adjusted
            }
        }

        if !micInput.append(buffer) {
            recordAppendFailure(mediaKind: "microphone")
        }
    }
}
