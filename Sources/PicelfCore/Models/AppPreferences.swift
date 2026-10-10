// AppPreferences.swift
// Picelf — Application Preferences
//
// Observable preferences model backed by UserDefaults. Supports dependency
// injection of a custom UserDefaults suite for isolated unit testing.
//
// Target: macOS 14+, Swift 5.9+

import Foundation
import Combine

// MARK: - Image Format

/// Supported export image formats.
enum ImageFormat: String, Codable, CaseIterable {
    case png
    case jpeg
}

enum CaptureRetentionUnit: String, Codable, CaseIterable, Identifiable {
    case seconds
    case hours
    case days

    var id: String { rawValue }
}

// MARK: - AppPreferences

/// Central preferences store for the Picelf app.
///
/// All `@Published` properties are automatically persisted to `UserDefaults`
/// via their `didSet` observers. The backing `UserDefaults` instance is
/// injectable so tests can use an isolated suite.
final class AppPreferences: ObservableObject {

    // MARK: Singleton

    static var shared = AppPreferences()

    // MARK: Storage

    private let defaults: UserDefaults
    private var isSyncingEditorExportState = false

    // MARK: Keys

    private enum Key {
        static let defaultFormat = "defaultFormat"
        static let jpegQuality = "jpegQuality"
        static let editorToolState = "editorToolState"
        static let autoSnapToWindows = "autoSnapToWindows"
        static let launchAtLogin = "launchAtLogin"
        static let savePath = "savePath"
        static let presets = "presets"
        static let appLanguage = "appLanguage"
        static let cacheFramesToDisk = "cacheFramesToDisk"
        static let recordingFormat = "recordingFormat"
        static let recordingResolution = "recordingResolution"
        static let recordingFrameRate = "recordingFrameRate"
        static let recordingShowsCursor = "recordingShowsCursor"
        static let recordingCountdown = "recordingCountdown"
        static let recordingCaptureSystemAudio = "recordingCaptureSystemAudio"
        static let recordingCaptureMicrophone = "recordingCaptureMicrophone"
        static let recordingMicrophoneDeviceID = "recordingMicrophoneDeviceID"
        static let recordingDurationLimit = "recordingDurationLimit"
        static let captureRetentionValue = "captureRetentionValue"
        static let captureRetentionUnit = "captureRetentionUnit"
        static let watermarkConfig = "watermarkConfig"
        static let translationTargetPreference = "translationTargetPreference"
        static let translationLastUsedTargetLanguage = "translationLastUsedTargetLanguage"
        static let translationOverlayMode = "translationOverlayMode"
        static let translationAutoRunFromSnapEdit = "translationAutoRunFromSnapEdit"
        static let translationExportFormatPreference = "translationExportFormatPreference"
    }

    // MARK: Published Properties

    @Published var defaultFormat: ImageFormat {
        didSet {
            defaults.set(defaultFormat.rawValue, forKey: Key.defaultFormat)
            syncEditorStateFromLegacyExportPreferences()
        }
    }

    @Published var jpegQuality: Double {
        didSet {
            defaults.set(jpegQuality, forKey: Key.jpegQuality)
            syncEditorStateFromLegacyExportPreferences()
        }
    }

    @Published var editorToolState: EditorToolState {
        didSet {
            let sanitized = editorToolState.sanitized()
            if sanitized != editorToolState {
                editorToolState = sanitized
                return
            }
            persistEditorToolState()
            syncLegacyExportPreferencesFromEditorState()
        }
    }

    @Published var autoSnapToWindows: Bool {
        didSet { defaults.set(autoSnapToWindows, forKey: Key.autoSnapToWindows) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @Published var savePath: String {
        didSet { defaults.set(savePath, forKey: Key.savePath) }
    }

    @Published var appLanguage: String {
        didSet {
            let normalized = AppLanguageOption.normalized(raw: appLanguage).rawValue
            if normalized != appLanguage {
                appLanguage = normalized
                return
            }
            defaults.set(normalized, forKey: Key.appLanguage)
        }
    }

    @Published var cacheFramesToDisk: Bool {
        didSet { defaults.set(cacheFramesToDisk, forKey: Key.cacheFramesToDisk) }
    }

    @Published var captureRetentionValue: Int {
        didSet {
            let clamped = Self.clampRetentionValue(captureRetentionValue, unit: captureRetentionUnit)
            if clamped != captureRetentionValue {
                captureRetentionValue = clamped
                return
            }
            defaults.set(clamped, forKey: Key.captureRetentionValue)
        }
    }

    @Published var captureRetentionUnit: CaptureRetentionUnit {
        didSet {
            defaults.set(captureRetentionUnit.rawValue, forKey: Key.captureRetentionUnit)
            let clamped = Self.clampRetentionValue(captureRetentionValue, unit: captureRetentionUnit)
            if clamped != captureRetentionValue {
                captureRetentionValue = clamped
            }
        }
    }

    // MARK: Recording Preferences

    @Published var recordingFormat: RecordingFormat {
        didSet { defaults.set(recordingFormat.rawValue, forKey: Key.recordingFormat) }
    }

    @Published var recordingResolution: RecordingResolution {
        didSet { defaults.set(recordingResolution.rawValue, forKey: Key.recordingResolution) }
    }

    @Published var recordingFrameRate: Int {
        didSet { defaults.set(recordingFrameRate, forKey: Key.recordingFrameRate) }
    }

    @Published var recordingShowsCursor: Bool {
        didSet { defaults.set(recordingShowsCursor, forKey: Key.recordingShowsCursor) }
    }

    @Published var recordingCountdown: Int {
        didSet { defaults.set(recordingCountdown, forKey: Key.recordingCountdown) }
    }

    @Published var recordingCaptureSystemAudio: Bool {
        didSet { defaults.set(recordingCaptureSystemAudio, forKey: Key.recordingCaptureSystemAudio) }
    }

    @Published var recordingCaptureMicrophone: Bool {
        didSet { defaults.set(recordingCaptureMicrophone, forKey: Key.recordingCaptureMicrophone) }
    }

    @Published var recordingMicrophoneDeviceID: String {
        didSet { defaults.set(recordingMicrophoneDeviceID, forKey: Key.recordingMicrophoneDeviceID) }
    }

    @Published var recordingDurationLimit: Int {
        didSet { defaults.set(recordingDurationLimit, forKey: Key.recordingDurationLimit) }
    }

    @Published var presets: [RegionPreset] {
        didSet { persistPresets() }
    }

    @Published var watermarkConfig: WatermarkConfig {
        didSet {
            if let data = try? JSONEncoder().encode(watermarkConfig) {
                defaults.set(data, forKey: Key.watermarkConfig)
            }
        }
    }

    @Published var translationTargetPreference: TranslationTargetPreference {
        didSet { defaults.set(translationTargetPreference.rawValue, forKey: Key.translationTargetPreference) }
    }

    @Published var translationLastUsedTargetLanguage: TranslationLanguageOption {
        didSet { defaults.set(translationLastUsedTargetLanguage.rawValue, forKey: Key.translationLastUsedTargetLanguage) }
    }

    @Published var translationOverlayMode: TranslationOverlayMode {
        didSet { defaults.set(translationOverlayMode.rawValue, forKey: Key.translationOverlayMode) }
    }

    @Published var translationAutoRunFromSnapEdit: Bool {
        didSet { defaults.set(translationAutoRunFromSnapEdit, forKey: Key.translationAutoRunFromSnapEdit) }
    }

    @Published var translationExportFormatPreference: TranslationExportFormatPreference {
        didSet { defaults.set(translationExportFormatPreference.rawValue, forKey: Key.translationExportFormatPreference) }
    }

    var captureRetentionInterval: TimeInterval {
        let value = TimeInterval(Self.clampRetentionValue(captureRetentionValue, unit: captureRetentionUnit))
        switch captureRetentionUnit {
        case .seconds:
            return value
        case .hours:
            return value * 3600
        case .days:
            return value * 24 * 3600
        }
    }

    static func retentionBounds(for unit: CaptureRetentionUnit) -> ClosedRange<Int> {
        switch unit {
        case .seconds:
            return 1...86_400
        case .hours:
            return 1...8_760
        case .days:
            return 1...3_650
        }
    }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load default export settings first; they are also migration fallback.
        let loadedDefaultFormat: ImageFormat
        if let raw = defaults.string(forKey: Key.defaultFormat),
           let format = ImageFormat(rawValue: raw) {
            loadedDefaultFormat = format
        } else {
            loadedDefaultFormat = .png
        }
        let loadedJPEGQuality: Double
        if defaults.object(forKey: Key.jpegQuality) != nil {
            loadedJPEGQuality = defaults.double(forKey: Key.jpegQuality)
        } else {
            loadedJPEGQuality = 0.9
        }

        // Load editor tool state (fallback migrates legacy export settings).
        let loadedEditorToolState: EditorToolState
        if let data = defaults.data(forKey: Key.editorToolState),
           let decoded = try? JSONDecoder().decode(EditorToolState.self, from: data) {
            loadedEditorToolState = decoded.sanitized()
        } else {
            loadedEditorToolState = EditorToolState.defaultState(
                exportFormat: loadedDefaultFormat,
                jpegQuality: loadedJPEGQuality
            )
        }

        // Keep legacy fields aligned for existing callers/preferences UI.
        self.defaultFormat = loadedEditorToolState.exportFormat
        self.jpegQuality = loadedEditorToolState.jpegQuality
        self.editorToolState = loadedEditorToolState

        // Load autoSnapToWindows
        if defaults.object(forKey: Key.autoSnapToWindows) != nil {
            self.autoSnapToWindows = defaults.bool(forKey: Key.autoSnapToWindows)
        } else {
            self.autoSnapToWindows = true
        }

        // Load launchAtLogin
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)

        // Load savePath
        self.savePath = defaults.string(forKey: Key.savePath) ?? ""

        // Load appLanguage (system/en/zh; unknown values fallback to English)
        self.appLanguage = AppLanguageOption.normalized(
            raw: defaults.string(forKey: Key.appLanguage)
        ).rawValue

        // Load cacheFramesToDisk (default: disabled)
        if defaults.object(forKey: Key.cacheFramesToDisk) != nil {
            self.cacheFramesToDisk = defaults.bool(forKey: Key.cacheFramesToDisk)
        } else {
            self.cacheFramesToDisk = false
        }

        // Load capture retention policy
        let loadedRetentionUnit: CaptureRetentionUnit
        if let raw = defaults.string(forKey: Key.captureRetentionUnit),
           let unit = CaptureRetentionUnit(rawValue: raw) {
            loadedRetentionUnit = unit
        } else {
            loadedRetentionUnit = .days
        }
        self.captureRetentionUnit = loadedRetentionUnit
        if defaults.object(forKey: Key.captureRetentionValue) != nil {
            let loaded = defaults.integer(forKey: Key.captureRetentionValue)
            self.captureRetentionValue = Self.clampRetentionValue(loaded, unit: loadedRetentionUnit)
        } else {
            self.captureRetentionValue = 10
        }

        // Load recording preferences
        if let raw = defaults.string(forKey: Key.recordingFormat),
           let fmt = RecordingFormat(rawValue: raw) {
            self.recordingFormat = fmt
        } else {
            self.recordingFormat = .mp4
        }
        if let raw = defaults.string(forKey: Key.recordingResolution),
           let res = RecordingResolution(rawValue: raw) {
            self.recordingResolution = res
        } else {
            self.recordingResolution = .original
        }
        if defaults.object(forKey: Key.recordingFrameRate) != nil {
            self.recordingFrameRate = defaults.integer(forKey: Key.recordingFrameRate)
        } else {
            self.recordingFrameRate = 30
        }
        if defaults.object(forKey: Key.recordingShowsCursor) != nil {
            self.recordingShowsCursor = defaults.bool(forKey: Key.recordingShowsCursor)
        } else {
            self.recordingShowsCursor = true
        }
        self.recordingCountdown = defaults.integer(forKey: Key.recordingCountdown)
        if defaults.object(forKey: Key.recordingCaptureSystemAudio) != nil {
            self.recordingCaptureSystemAudio = defaults.bool(forKey: Key.recordingCaptureSystemAudio)
        } else {
            self.recordingCaptureSystemAudio = true
        }
        self.recordingCaptureMicrophone = defaults.bool(forKey: Key.recordingCaptureMicrophone)
        self.recordingMicrophoneDeviceID = defaults.string(forKey: Key.recordingMicrophoneDeviceID) ?? ""
        self.recordingDurationLimit = defaults.integer(forKey: Key.recordingDurationLimit)

        // Load presets
        if let data = defaults.data(forKey: Key.presets),
           let decoded = try? JSONDecoder().decode([RegionPreset].self, from: data) {
            self.presets = decoded
        } else {
            self.presets = []
        }

        // Load watermark config
        if let data = defaults.data(forKey: Key.watermarkConfig),
           let config = try? JSONDecoder().decode(WatermarkConfig.self, from: data) {
            self.watermarkConfig = config
        } else {
            self.watermarkConfig = WatermarkConfig()
        }

        if let raw = defaults.string(forKey: Key.translationTargetPreference),
           let preference = TranslationTargetPreference(rawValue: raw) {
            self.translationTargetPreference = preference
        } else {
            self.translationTargetPreference = .followAppLanguage
        }

        self.translationLastUsedTargetLanguage = TranslationLanguageOption.normalized(
            raw: defaults.string(forKey: Key.translationLastUsedTargetLanguage)
        )

        if let raw = defaults.string(forKey: Key.translationOverlayMode),
           let mode = TranslationOverlayMode(rawValue: raw) {
            self.translationOverlayMode = mode
        } else {
            self.translationOverlayMode = .hover
        }

        if defaults.object(forKey: Key.translationAutoRunFromSnapEdit) != nil {
            self.translationAutoRunFromSnapEdit = defaults.bool(forKey: Key.translationAutoRunFromSnapEdit)
        } else {
            self.translationAutoRunFromSnapEdit = true
        }

        if let raw = defaults.string(forKey: Key.translationExportFormatPreference),
           let preference = TranslationExportFormatPreference(rawValue: raw) {
            self.translationExportFormatPreference = preference
        } else {
            self.translationExportFormatPreference = .matchSource
        }
    }

    // MARK: Preset CRUD

    func addPreset(_ preset: RegionPreset) {
        presets.append(preset)
    }

    func updatePreset(_ preset: RegionPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
    }

    func removePreset(id: UUID) {
        presets.removeAll { $0.id == id }
    }

    func updateEditorToolState(_ mutate: (inout EditorToolState) -> Void) {
        var next = editorToolState
        mutate(&next)
        next = next.sanitized()
        guard next != editorToolState else { return }
        editorToolState = next
    }

    // MARK: Private

    private func persistEditorToolState() {
        if let data = try? JSONEncoder().encode(editorToolState) {
            defaults.set(data, forKey: Key.editorToolState)
        }
    }

    private func syncLegacyExportPreferencesFromEditorState() {
        guard !isSyncingEditorExportState else { return }
        isSyncingEditorExportState = true
        let state = editorToolState
        if defaultFormat != state.exportFormat {
            defaultFormat = state.exportFormat
        }
        if abs(jpegQuality - state.jpegQuality) > 0.0001 {
            jpegQuality = state.jpegQuality
        }
        isSyncingEditorExportState = false
    }

    private func syncEditorStateFromLegacyExportPreferences() {
        guard !isSyncingEditorExportState else { return }
        isSyncingEditorExportState = true
        var next = editorToolState
        next.exportFormat = defaultFormat
        next.jpegQuality = jpegQuality
        next = next.sanitized()
        if next != editorToolState {
            editorToolState = next
        }
        isSyncingEditorExportState = false
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: Key.presets)
        }
    }

    private static func clampRetentionValue(_ value: Int, unit: CaptureRetentionUnit) -> Int {
        let bounds = retentionBounds(for: unit)
        return min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}
