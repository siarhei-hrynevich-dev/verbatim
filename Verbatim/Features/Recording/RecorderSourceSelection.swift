import Foundation
import Observation

/// What can be recorded right now and which of it is selected.
///
/// A remembered selection outlives its source: a disconnected display or microphone is selected again when it comes
/// back. A source that vanishes after being seen in this session is reported; a stale one from an earlier launch
/// is not.
@MainActor
@Observable
final class RecorderSourceSelection {
    private(set) var displays: [CaptureDisplay] = []
    private(set) var windows: [CaptureWindow] = []
    private(set) var microphones: [Microphone] = []
    private(set) var windowThumbnails: [CaptureWindow.ID: Data] = [:]
    /// A selected source that went away.
    var lostSourceIssue: RecorderIssue?

    var selectedDisplayID: CaptureDisplay.ID? { didSet { selectionDidChange() } }
    var selectedWindowID: CaptureWindow.ID? { didSet { windowSelectionDidChange() } }
    var selectedMicrophoneID: Microphone.ID? { didSet { selectionDidChange() } }

    /// Called for selection changes made by the user, not for ones following the sources.
    @ObservationIgnored var onUserSelection: () -> Void = {}
    @ObservationIgnored private(set) var rememberedWindow: RememberedWindow?
    @ObservationIgnored private var isFollowingSources = false
    @ObservationIgnored private var seenSelections = SeenSelections()

    /// Window identifiers do not survive app relaunches, so a window is also recognized by its app and title.
    struct RememberedWindow: Equatable {
        let bundleIdentifier: String
        let title: String
    }

    /// The name of each selection when it was last available; `nil` until seen in this session.
    private struct SeenSelections {
        var display: String?
        var window: String?
        var microphone: String?
    }

    init(preferences: RecordingPreferences) {
        selectedDisplayID = preferences.displayID
        selectedWindowID = preferences.windowID
        selectedMicrophoneID = preferences.microphoneID
        if let bundleIdentifier = preferences.windowBundleIdentifier, let title = preferences.windowTitle {
            rememberedWindow = RememberedWindow(bundleIdentifier: bundleIdentifier, title: title)
        }
    }

    var selectedDisplay: CaptureDisplay? {
        displays.first { $0.id == selectedDisplayID } ?? displays.first
    }

    var selectedWindow: CaptureWindow? {
        windows.first { $0.id == selectedWindowID }
    }

    var selectedMicrophone: Microphone? {
        microphones.first { $0.id == selectedMicrophoneID } ?? microphones.first
    }

    // MARK: - Following the sources

    func update(sources: CaptureSources, microphones available: [Microphone], captureMode: CaptureMode) {
        isFollowingSources = true
        defer { isFollowingSources = false }

        if available != microphones {
            microphones = available
        }
        if sources.displays != displays {
            displays = sources.displays
        }
        if sources.windows != windows {
            windows = sources.windows
            windowThumbnails = windowThumbnails.filter { id, _ in sources.windows.contains { $0.id == id } }
        }
        followMicrophone()
        followDisplay(captureMode: captureMode)
        followWindow(captureMode: captureMode)
    }

    func addThumbnails(_ thumbnails: [CaptureWindow.ID: Data]) {
        windowThumbnails.merge(thumbnails) { _, new in new }
    }

    var windowsWithoutThumbnail: [CaptureWindow.ID] {
        windows.map(\.id).filter { windowThumbnails[$0] == nil }
    }

    /// Replaces everything with a design scenario's sample data.
    func showSamples(_ sample: RecorderPreviewData) {
        isFollowingSources = true
        defer { isFollowingSources = false }
        displays = sample.displays
        windows = sample.windows
        microphones = sample.microphones
        windowThumbnails = [:]
        lostSourceIssue = nil
        selectedDisplayID = sample.displays.first?.id
        selectedWindowID = sample.windows.first?.id
        selectedMicrophoneID = sample.microphones.first?.id
    }

    /// Goes back to the saved choices after a design scenario.
    func restore(_ preferences: RecordingPreferences) {
        isFollowingSources = true
        defer { isFollowingSources = false }
        lostSourceIssue = nil
        selectedDisplayID = preferences.displayID
        selectedWindowID = preferences.windowID
        selectedMicrophoneID = preferences.microphoneID
    }

    private func followMicrophone() {
        if let microphone = microphones.first(where: { $0.id == selectedMicrophoneID }) {
            seenSelections.microphone = microphone.name
            if case .microphoneUnavailable = lostSourceIssue {
                lostSourceIssue = nil
            }
        } else if let name = seenSelections.microphone {
            seenSelections.microphone = nil
            lostSourceIssue = .microphoneUnavailable(name: name)
        }
    }

    private func followDisplay(captureMode: CaptureMode) {
        if let display = displays.first(where: { $0.id == selectedDisplayID }) {
            seenSelections.display = display.name
            if case .displayUnavailable = lostSourceIssue {
                lostSourceIssue = nil
            }
        } else if let name = seenSelections.display {
            seenSelections.display = nil
            if captureMode == .screen {
                lostSourceIssue = .displayUnavailable(name: name)
            }
        }
    }

    private func followWindow(captureMode: CaptureMode) {
        if let window = selectedWindow {
            seenSelections.window = window.title
        } else if let rememberedMatch {
            selectedWindowID = rememberedMatch.id
            seenSelections.window = rememberedMatch.title
        } else if let name = seenSelections.window {
            seenSelections.window = nil
            selectedWindowID = nil
            if captureMode == .window {
                lostSourceIssue = .windowUnavailable(name: name)
            }
        } else if lostSourceIssue == nil {
            selectedWindowID = windows.first?.id
        }
    }

    private var rememberedMatch: CaptureWindow? {
        guard let rememberedWindow else {
            return nil
        }
        return windows.first { window in
            window.bundleIdentifier == rememberedWindow.bundleIdentifier && window.title == rememberedWindow.title
        }
    }

    private func windowSelectionDidChange() {
        if !isFollowingSources, let selectedWindow {
            rememberedWindow = RememberedWindow(
                bundleIdentifier: selectedWindow.bundleIdentifier,
                title: selectedWindow.title
            )
        }
        selectionDidChange()
    }

    private func selectionDidChange() {
        guard !isFollowingSources else {
            return
        }
        lostSourceIssue = nil
        onUserSelection()
    }
}
