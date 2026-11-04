import Foundation
import Observation

/// Presentation state of the Viewer window: simulated playback, the transcript panel and transcript search.
///
/// This is a layout-only implementation: playback is a clock advanced by the view, recordings and transcripts come
/// from fixed sample data, and starting processing only changes local state. No media, transcription or storage
/// service is involved yet.
@MainActor
@Observable
final class ViewerViewModel {
    enum PlaybackSpeed: Double, CaseIterable, Sendable {
        case normal = 1
        case fast = 1.5
        case double = 2

        /// Speeds cycle 1×, 1.5×, 2×, as in the design.
        var next: PlaybackSpeed {
            switch self {
            case .normal: .fast
            case .fast: .double
            case .double: .normal
            }
        }
    }

    private(set) var recording: ViewerRecording
    /// The editable recording title in the window toolbar.
    var title: String
    private(set) var position: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var speed: PlaybackSpeed = .normal
    /// Whether the transcript scrolls along with playback. Scrolling by hand pauses it.
    private(set) var isFollowingPlayback = true
    private(set) var searchText = ""
    /// Position of the current match within `matchingLineIndices`.
    private(set) var currentMatch = 0

    private let previewData: ViewerPreviewData

    init(previewData: ViewerPreviewData = .sample(), scenario: ViewerPreviewScenario = .video) {
        self.previewData = previewData
        let fallback = previewData.library.items.first ?? Self.placeholderItem
        recording = previewData.recording(for: fallback)
        title = fallback.title
        apply(scenario)
    }

    // MARK: - Derived state

    var duration: TimeInterval {
        recording.item.duration
    }

    var lines: [TranscriptLine] {
        recording.hasTranscript ? recording.transcript : []
    }

    /// The line being spoken at the playhead: the last line that starts at or before it.
    var activeLineIndex: Int? {
        lines.lastIndex { $0.start <= position }
    }

    /// Indices of transcript lines containing the search text, ignoring case.
    var matchingLineIndices: [Int] {
        let query = trimmedQuery
        guard !query.isEmpty else {
            return []
        }
        return lines.indices.filter { lines[$0].text.range(of: query, options: .caseInsensitive) != nil }
    }

    var currentMatchLineIndex: Int? {
        let matches = matchingLineIndices
        guard !matches.isEmpty else {
            return nil
        }
        return matches[min(currentMatch, matches.count - 1)]
    }

    var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Opening

    /// Shows a Library recording, optionally at a transcript position in seconds, as search results do.
    func open(_ item: LibraryItem, at timestamp: TimeInterval? = nil) {
        recording = previewData.recording(for: item)
        title = item.title
        position = min(max(timestamp ?? 0, 0), item.duration)
        isPlaying = false
        speed = .normal
        searchText = ""
        currentMatch = 0
        isFollowingPlayback = true
    }

    // MARK: - Playback

    func togglePlayback() {
        if !isPlaying, position >= duration {
            position = 0
        }
        isPlaying.toggle()
    }

    /// Advances simulated playback by `seconds` of wall-clock time, scaled by the speed. Stops at the end.
    func advance(by seconds: TimeInterval) {
        guard isPlaying else {
            return
        }
        position = min(duration, position + seconds * speed.rawValue)
        if position >= duration {
            isPlaying = false
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: position + seconds)
    }

    func seek(to newPosition: TimeInterval) {
        position = min(max(newPosition, 0), duration)
    }

    /// Jumps to a transcript line, as clicking it does.
    func seekToLine(at index: Int) {
        guard lines.indices.contains(index) else {
            return
        }
        seek(to: lines[index].start)
    }

    func cycleSpeed() {
        speed = speed.next
    }

    // MARK: - Transcript

    func pauseFollowingPlayback() {
        isFollowingPlayback = false
    }

    func resumeFollowingPlayback() {
        isFollowingPlayback = true
    }

    func updateSearchText(_ text: String) {
        searchText = text
        currentMatch = 0
    }

    func showNextMatch() {
        stepMatch(by: 1)
    }

    func showPreviousMatch() {
        stepMatch(by: -1)
    }

    /// Simulates starting transcription, from Generate Transcript or Retry Processing.
    func startProcessing() {
        switch recording.transcriptState {
        case .failed, .notProcessed:
            recording.transcriptState = .processing(progress: Self.initialProgress)
        case .ready, .processing:
            break
        }
    }

    // MARK: - Preview scenarios

    func apply(_ scenario: ViewerPreviewScenario) {
        guard let item = previewData.item(titled: scenario.recordingTitle) else {
            return
        }
        open(item, at: scenario.startPosition)
        isPlaying = scenario == .video
        if scenario == .search {
            searchText = ViewerPreviewScenario.sampleSearchQuery
            currentMatch = 1
        }
    }

    // MARK: - Private

    /// Each step moves the playhead to the match and follows it in the transcript.
    private func stepMatch(by offset: Int) {
        let matches = matchingLineIndices
        guard !matches.isEmpty else {
            return
        }
        let current = min(currentMatch, matches.count - 1)
        currentMatch = (current + offset + matches.count) % matches.count
        seek(to: lines[matches[currentMatch]].start)
        isFollowingPlayback = true
    }

    /// Restarted processing shows a sliver of progress right away, as in the design prototype.
    private static let initialProgress = 0.01

    /// Only used if the sample library is empty, which the bundled sample never is.
    private static let placeholderItem = LibraryItem(
        id: UUID(),
        title: "Recording",
        recordedAt: .now,
        duration: 0,
        sizeBytes: 0,
        kind: .screen,
        status: .ready,
        folderName: "Recording"
    )
}
