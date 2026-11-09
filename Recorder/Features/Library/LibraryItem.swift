import Foundation

/// A recording as the Library lists it: one folder on disk with its media, transcript files and processing state.
struct LibraryItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case screen
        case window
        case audio
    }

    enum Status: Equatable, Sendable {
        case ready
        /// Waiting its turn in the queue.
        case pending
        /// `progress` is a fraction from 0 to 1.
        case transcribing(progress: Double)
        /// `progress` is a fraction from 0 to 1.
        case indexing(progress: Double)
        /// Saved without a transcript, for example with auto-transcription off.
        case recorded
        case failed
        /// The recording folder is no longer where the Library expects it.
        case missing
    }

    let id: UUID
    var title: String
    let recordedAt: Date
    let duration: TimeInterval
    let sizeBytes: Int64
    let kind: Kind
    var status: Status
    /// The recording's folder inside the recordings folder, such as `2026-11-03 Architecture Review`.
    let folderName: String
    /// Where the recording really is, for one the Library tracks on disk. Sample recordings have no location.
    var location: Location?
    /// Whether transcription can be started from here. Off for an entry with no transcription behind it.
    var isProcessingAvailable = true
    /// A transcript is stored, whatever the latest job did: only a finished replacement ever touches it.
    var hasStoredTranscript = false
    /// Why the latest transcription failed, as the status explains it.
    var failureIssue: TranscriptionIssue?
    /// Whether the transcript can be made again. Sample recordings don't offer it.
    var offersRetranscription = false
    /// In the order the sidebar lists tags.
    var tags: [RecordingTag] = []

    /// A tracked recording's folder and files as last inspected.
    struct Location: Equatable, Sendable {
        /// The folder's full path, when it is not directly inside the recordings folder.
        var folderPath: String?
        /// The name of the folder holding the recording's folder.
        var parentFolderName: String?
        var fileNames: [String]
        /// Whether Delete moves the whole folder to the Trash, rather than individual files.
        var trashesFolder: Bool
        /// Why the media cannot be reached, if it cannot.
        var unavailability: MediaAvailability?
    }

    /// The recording's files; the design's recording folders hold the media file and three transcript formats.
    var fileNames: [String] {
        location?.fileNames ?? [
            kind == .audio ? "recording.m4a" : "recording.mov", "transcript.txt", "transcript.srt", "transcript.json"
        ]
    }

    var isMissing: Bool {
        status == .missing
    }

    var hasTranscript: Bool {
        switch status {
        case .ready, .indexing: true
        case .pending, .transcribing, .recorded, .failed, .missing: hasStoredTranscript
        }
    }

    /// Progress of the transcript or search index, while one is being built.
    var processingProgress: Double? {
        switch status {
        case .transcribing(let progress), .indexing(let progress): progress
        case .ready, .pending, .recorded, .failed, .missing: nil
        }
    }

    /// Queued or running, which offers stopping instead of starting.
    var isProcessing: Bool {
        switch status {
        case .pending, .transcribing: offersRetranscription
        case .ready, .indexing, .recorded, .failed, .missing: false
        }
    }

    /// Whether transcription can be started: the recording has no transcript yet, or processing failed.
    var canStartProcessing: Bool {
        isProcessingAvailable && (status == .recorded || status == .failed)
    }

    var canRetranscribe: Bool {
        offersRetranscription && status == .ready
    }

    /// The fix offered inline next to the status, if any.
    var statusActionTitle: String? {
        isMissing || canStartProcessing ? status.actionTitle : nil
    }

    var kindLabel: String {
        switch kind {
        case .screen: String(localized: "Screen")
        case .window: String(localized: "Window")
        case .audio: String(localized: "Audio only")
        }
    }
}

extension LibraryItem {
    /// `inspection` is `nil` until the file system has been checked; the recording shows as present until then. A job,
    /// when there is one, knows more than the stored status. `isProcessingAvailable` is off without a queue to use.
    init(
        _ recording: LibraryRecording,
        inspection: RecordingFileInspection?,
        recordingsFolder: URL?,
        job: TranscriptionJob? = nil,
        isProcessingAvailable: Bool = false,
        tags: [RecordingTag] = []
    ) {
        let media = inspection?.media ?? recording.media
        let folder = media.url.deletingLastPathComponent()
        let isInRecordingsFolder = folder.deletingLastPathComponent().path() == recordingsFolder?.path()
        let availability = inspection?.availability ?? .available
        self.init(
            id: recording.id,
            title: recording.recording.title,
            recordedAt: recording.recording.createdAt,
            duration: recording.recording.duration,
            sizeBytes: recording.fileSizeBytes,
            kind: Kind(recording.captureMode),
            status: availability == .available ? Status(recording.recording.processingStatus, job: job) : .missing,
            folderName: folder.lastPathComponent,
            location: Location(
                folderPath: isInRecordingsFolder ? nil : folder.path(percentEncoded: false),
                parentFolderName: isInRecordingsFolder ? nil : folder.deletingLastPathComponent().lastPathComponent,
                fileNames: inspection?.fileNames ?? [media.url.lastPathComponent],
                trashesFolder: inspection?.trashesFolder ?? false,
                unavailability: availability == .available ? nil : availability
            ),
            isProcessingAvailable: isProcessingAvailable,
            hasStoredTranscript: recording.hasTranscript,
            failureIssue: job?.failure.map(TranscriptionIssue.init),
            offersRetranscription: isProcessingAvailable,
            tags: tags
        )
    }
}

extension LibraryItem.Kind {
    fileprivate init(_ captureMode: CaptureMode) {
        switch captureMode {
        case .screen: self = .screen
        case .window: self = .window
        case .audioOnly: self = .audio
        }
    }
}

extension LibraryItem.Status {
    fileprivate init(_ status: Recording.ProcessingStatus, job: TranscriptionJob?) {
        switch job?.state {
        case .pending:
            self = .pending
            return
        case .preparing, .transcribing, .saving:
            self = .transcribing(progress: 0)
            return
        case .failed:
            self = .failed
            return
        case .completed, .cancelled, nil:
            break
        }
        // Without a queue running, a job that says it is underway isn't, and a stored one will be recovered at launch.
        switch status {
        case .recorded: self = .recorded
        case .pending: self = .pending
        case .transcribing: self = .transcribing(progress: 0)
        case .indexing: self = .indexing(progress: 0)
        case .ready: self = .ready
        case .failed: self = .failed
        }
    }
}
