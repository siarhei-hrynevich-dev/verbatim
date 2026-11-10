import Foundation
import Observation
import os

/// Presentation state of the Viewer window: the recording being shown, its playback, and the transcript panel.
///
/// Live, it opens recordings by identifier through `LibraryService` and plays them through `PlaybackService`. For
/// design review it can instead show a `ViewerPreviewScenario`: sample recordings and transcripts, a clock advanced by
/// the view, and no media, in the same way as `LibraryViewModel`'s scenarios. A live recording's lines come from its
/// stored transcript, through `ProcessingCoordinator`.
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

    /// A seek waiting for the one in progress to finish. Only the newest matters.
    struct PendingSeek {
        let target: TimeInterval
        let precision: PlaybackSeekPrecision
    }

    // Only this type and its extensions in `ViewerViewModel+*.swift` write these; Swift has no narrower access level
    // that spans files. Views read them and call the actions.

    /// `nil` until the Library has answered, and when nothing is open.
    var recording: ViewerRecording? {
        didSet {
            let isSameTranscript = oldValue?.transcript == recording?.transcript
            if !isSameTranscript || oldValue?.transcriptState != recording?.transcriptState {
                transcriptChanged()
            }
        }
    }
    /// The editable recording title in the window toolbar.
    var title = ""
    var playbackState = PlaybackState.idle
    /// The playhead as shown. While dragging or seeking, this is where the user asked to go. Changes many times a
    /// second, so the transcript reads `activeLineIndex` instead, which changes only when another line starts.
    var position: TimeInterval = 0 {
        didSet { updateActiveLine() }
    }
    /// What the open file really contains; `nil` until it has loaded.
    var mediaInfo: PlaybackMediaInfo?
    var speed = PlaybackSpeed.normal
    /// From 0 to 1.
    var volume = 1.0
    var isMuted = false
    var isLocatingFile = false
    /// The format being saved through the save panel.
    var exportRequest: ViewerExportFormat?
    /// A failed action that leaves playback as it was, such as Show in Finder.
    var actionIssue: LibraryIssue?
    /// Whether this shows a design scenario instead of a real recording.
    var isPreviewing: Bool
    /// Whether the transcript scrolls along with playback. Scrolling by hand pauses it.
    private(set) var isFollowingPlayback = true
    private(set) var searchText = ""
    /// Position of the current match within `matchingLineIndices`.
    private(set) var currentMatch = 0
    /// The line being spoken at the playhead: the last line that starts at or before it.
    private(set) var activeLineIndex: Int?
    /// Indices of transcript lines containing the search text, ignoring case.
    private(set) var matchingLineIndices: [Int] = []
    /// What the side panel shows: the transcript, or its summary.
    var panelMode = ViewerPanelMode.transcript
    /// The open recording's stored summary, once read.
    var summary: TranscriptSummary?

    @ObservationIgnored let library: LibraryService?
    @ObservationIgnored let playback: (any PlaybackService)?
    @ObservationIgnored let processing: ProcessingCoordinator?
    @ObservationIgnored let summaries: SummaryCoordinator?
    /// The summaries revision whose result is showing, so a new summary is read when one is stored.
    @ObservationIgnored var loadedSummaryRevision: Int?
    /// The stable identity of what is open; titles and file names can change.
    @ObservationIgnored var recordingID: UUID?
    @ObservationIgnored var openMedia: OpenMediaFile?
    /// The transcript as stored, which exports are rendered from.
    @ObservationIgnored var storedTranscript: Transcript?
    /// Which completed job's transcript is showing, so a new one is loaded when it arrives.
    @ObservationIgnored var loadedTranscriptStamp: Date?
    /// Whether this session has read the stored transcript at all.
    @ObservationIgnored var hasReadTranscript = false
    @ObservationIgnored var loadTask: Task<Void, Never>?
    @ObservationIgnored var seekTask: Task<Void, Never>?
    @ObservationIgnored var actionTask: Task<Void, Never>?
    @ObservationIgnored var pendingSeek: PendingSeek?
    @ObservationIgnored var isScrubbing = false
    /// Playback resumes once the seeks underway have landed: after a drag or a replay.
    @ObservationIgnored var resumesAfterSeek = false

    private let previewData: ViewerPreviewData

    /// The real Viewer, showing nothing until `open(recordingID:at:)`. A `previewScenario` starts on sample data
    /// instead, until `endPreview()`.
    init(
        library: LibraryService,
        playback: any PlaybackService,
        processing: ProcessingCoordinator? = nil,
        summaries: SummaryCoordinator? = nil,
        previewScenario: ViewerPreviewScenario? = nil
    ) {
        self.library = library
        self.playback = playback
        self.processing = processing
        self.summaries = summaries
        previewData = .sample()
        isPreviewing = false
        if let previewScenario {
            apply(previewScenario)
        }
    }

    /// Sample data only, for SwiftUI previews and tests of the design states.
    init(previewData: ViewerPreviewData = .sample(), scenario: ViewerPreviewScenario = .video) {
        library = nil
        playback = nil
        processing = nil
        summaries = nil
        self.previewData = previewData
        isPreviewing = true
        apply(scenario)
    }

    // MARK: - Derived state

    var isPlaying: Bool {
        playbackState == .playing
    }

    var canControlPlayback: Bool {
        playbackState.isLoaded
    }

    /// The length the controls use: the media's own once it has been read.
    var duration: TimeInterval {
        PlaybackTimeline.effectiveDuration(media: mediaInfo?.duration, stored: recording?.item.duration ?? 0)
    }

    /// Whether to show a video picture, by what the file contains once that is known.
    var showsVideo: Bool {
        mediaInfo?.hasVideo ?? (recording?.item.kind != .audio)
    }

    var playbackIssue: ViewerIssue? {
        guard case .failed(let failure) = playbackState else {
            return nil
        }
        return ViewerIssue(failure)
    }

    /// Whether the transcript file exists on disk to be shown, which does not require having its lines loaded.
    var canShowTranscriptInFinder: Bool {
        guard let recording else {
            return false
        }
        return isPreviewing
            ? recording.hasTranscript : RecordingFileLayout.transcriptFileName(in: recording.item.fileNames) != nil
    }

    /// Changes whenever the Library's contents do, so an open recording can follow a rename or a removal.
    var libraryRevision: Int {
        (library?.revision ?? 0) + (processing?.revision ?? 0)
    }

    var lines: [TranscriptLine] {
        guard let recording, recording.hasTranscript else {
            return []
        }
        return recording.transcript
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
        updateMatches()
    }

    func showNextMatch() {
        stepMatch(by: 1)
    }

    func showPreviousMatch() {
        stepMatch(by: -1)
    }

    /// Starts transcription, from Generate Transcript, Retry or Re-transcribe. Design scenarios simulate it.
    func startProcessing() {
        guard isPreviewing else {
            if let recordingID {
                processing?.enqueue(recordingID)
            }
            return
        }
        switch recording?.transcriptState {
        case .failed, .notProcessed:
            recording?.transcriptState = .processing(progress: Self.initialProgress)
        case .ready, .processing, .unavailable, nil:
            break
        }
    }

    func resetTranscriptPresentation() {
        searchText = ""
        currentMatch = 0
        isFollowingPlayback = true
        updateMatches()
    }

    // MARK: - Preview scenarios

    /// Shows a sample recording, optionally at a transcript position in seconds, as search results do.
    func open(_ item: LibraryItem, at timestamp: TimeInterval? = nil) {
        endLiveSession()
        isPreviewing = true
        recording = previewData.recording(for: item)
        title = item.title
        position = min(max(timestamp ?? 0, 0), item.duration)
        playbackState = .paused
        speed = .normal
        resetTranscriptPresentation()
    }

    func apply(_ scenario: ViewerPreviewScenario) {
        guard let item = previewData.item(titled: scenario.recordingTitle) else {
            return
        }
        open(item, at: scenario.startPosition)
        playbackState = scenario == .video ? .playing : .paused
        if scenario == .search {
            updateSearchText(ViewerPreviewScenario.sampleSearchQuery)
            currentMatch = 1
        }
    }

    /// Leaves the design scenario and returns to showing nothing, ready for a real recording.
    func endPreview() {
        guard library != nil else {
            return
        }
        isPreviewing = false
        recording = nil
        title = ""
        position = 0
        playbackState = .idle
        resetTranscriptPresentation()
    }

    /// Advances simulated playback by `seconds` of wall-clock time, scaled by the speed. Stops at the end.
    func advanceSimulation(by seconds: TimeInterval) {
        guard isPreviewing, isPlaying else {
            return
        }
        position = min(duration, position + seconds * speed.rawValue)
        if position >= duration {
            playbackState = .ended
        }
    }

    // MARK: - Private

    private func transcriptChanged() {
        updateActiveLine()
        updateMatches()
    }

    /// Assigned only when it differs: anything showing the line redraws when this is written. Lines are in start order.
    private func updateActiveLine() {
        let lines = lines
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].start <= position {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let active = low > 0 ? low - 1 : nil
        if active != activeLineIndex {
            activeLineIndex = active
        }
    }

    private func updateMatches() {
        let query = trimmedQuery
        let lines = lines
        matchingLineIndices =
            query.isEmpty
            ? [] : lines.indices.filter { lines[$0].text.range(of: query, options: .caseInsensitive) != nil }
    }

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

    static let logger = Logger(subsystem: "dev.local.Recorder", category: "Playback")
}
