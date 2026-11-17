import Foundation

/// Stores recording preferences as individual defaults, so a value that is no longer valid only resets itself.
struct UserDefaultsRecordingPreferencesStore: RecordingPreferencesStore {
    private enum Key {
        static let captureMode = "recording.captureMode"
        static let displayID = "recording.displayID"
        static let windowID = "recording.windowID"
        static let windowBundleIdentifier = "recording.windowBundleIdentifier"
        static let windowTitle = "recording.windowTitle"
        static let microphoneID = "recording.microphoneID"
        static let isMicrophoneEnabled = "recording.isMicrophoneEnabled"
        static let isSystemAudioEnabled = "recording.isSystemAudioEnabled"
        static let quality = "recording.quality"
        static let frameRate = "recording.frameRate"
        static let transcribesWhenFinished = "recording.transcribesWhenFinished"
    }

    /// UserDefaults is documented as thread-safe, but is not marked Sendable.
    nonisolated(unsafe) let defaults: UserDefaults

    func load() -> RecordingPreferences {
        var preferences = RecordingPreferences()
        if let captureMode = defaults.string(forKey: Key.captureMode).flatMap(CaptureMode.init) {
            preferences.captureMode = captureMode
        }
        preferences.displayID = defaults.string(forKey: Key.displayID)
        preferences.windowID = defaults.string(forKey: Key.windowID)
        preferences.windowBundleIdentifier = defaults.string(forKey: Key.windowBundleIdentifier)
        preferences.windowTitle = defaults.string(forKey: Key.windowTitle)
        preferences.microphoneID = defaults.string(forKey: Key.microphoneID)
        if let isEnabled = defaults.object(forKey: Key.isMicrophoneEnabled) as? Bool {
            preferences.isMicrophoneEnabled = isEnabled
        }
        if let isEnabled = defaults.object(forKey: Key.isSystemAudioEnabled) as? Bool {
            preferences.isSystemAudioEnabled = isEnabled
        }
        if let quality = defaults.string(forKey: Key.quality).flatMap(VideoQuality.init) {
            preferences.quality = quality
        }
        if let frameRate = FrameRate(rawValue: defaults.integer(forKey: Key.frameRate)) {
            preferences.frameRate = frameRate
        }
        if let isEnabled = defaults.object(forKey: Key.transcribesWhenFinished) as? Bool {
            preferences.transcribesWhenFinished = isEnabled
        }
        return preferences
    }

    func save(_ preferences: RecordingPreferences) {
        defaults.set(preferences.captureMode.rawValue, forKey: Key.captureMode)
        defaults.set(preferences.displayID, forKey: Key.displayID)
        defaults.set(preferences.windowID, forKey: Key.windowID)
        defaults.set(preferences.windowBundleIdentifier, forKey: Key.windowBundleIdentifier)
        defaults.set(preferences.windowTitle, forKey: Key.windowTitle)
        defaults.set(preferences.microphoneID, forKey: Key.microphoneID)
        defaults.set(preferences.isMicrophoneEnabled, forKey: Key.isMicrophoneEnabled)
        defaults.set(preferences.isSystemAudioEnabled, forKey: Key.isSystemAudioEnabled)
        defaults.set(preferences.quality.rawValue, forKey: Key.quality)
        defaults.set(preferences.frameRate.rawValue, forKey: Key.frameRate)
        defaults.set(preferences.transcribesWhenFinished, forKey: Key.transcribesWhenFinished)
    }
}
