import Foundation

/// Which audio a transcript segment was heard on. Labels the track, not a person: no speakers are identified.
enum TranscriptSource: String, Codable, CaseIterable, Sendable {
    case microphone
    case systemAudio
    /// The tracks could not be told apart, as in a file from elsewhere, so they were transcribed as one mix.
    case unknown

    init(_ kind: AudioSourceKind) {
        switch kind {
        case .microphone: self = .microphone
        case .systemAudio: self = .systemAudio
        }
    }

    /// Breaks ties between segments starting at the same moment, so the order never depends on processing order.
    fileprivate var mergeRank: Int {
        switch self {
        case .microphone: 0
        case .systemAudio: 1
        case .unknown: 2
        }
    }
}

/// One timestamped piece of speech. Times are seconds on the recording's own timeline, the one playback uses.
struct TranscriptSegment: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let recordingID: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let source: TranscriptSource

    /// `nil` for times that could not describe speech, or for blank text.
    init?(
        id: UUID = UUID(),
        recordingID: UUID,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        source: TranscriptSource
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard startTime.isFinite, endTime.isFinite, startTime >= 0, endTime >= startTime, !trimmedText.isEmpty else {
            return nil
        }
        self.id = id
        self.recordingID = recordingID
        self.startTime = startTime
        self.endTime = endTime
        self.text = trimmedText
        self.source = source
    }
}

/// Speech as a recognizer reported it, with times already on the recording's timeline but not yet checked or ordered.
struct RecognizedSpeech: Equatable, Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let source: TranscriptSource
}

/// A finished transcript. One exists per recording, and only complete ones are ever stored: the state of the work
/// that produces one belongs to `TranscriptionJob`.
struct Transcript: Equatable, Sendable {
    let recordingID: UUID
    let modelID: SpeechModel.ID
    /// `nil` when the model does not report one.
    let modelVersion: String?
    /// The detected or chosen language code, such as `en`. `nil` when no speech was found to detect it from.
    let language: String?
    let createdAt: Date
    /// In the stable order of `assembled`: by start time, then source.
    let segments: [TranscriptSegment]

    /// What a transcript records about how it was made.
    struct Provenance: Equatable, Sendable {
        let modelID: SpeechModel.ID
        let modelVersion: String?
        let language: String?
        let createdAt: Date
    }

    /// Turns what a recognizer reported into a valid, stably ordered transcript. Invalid and blank speech is dropped,
    /// and times are kept inside the media. Within one source, the end of one chunk can repeat the start of the next:
    /// identical overlapping text is dropped, and other overlaps are moved to start where the previous one ended.
    /// Different sources may overlap, because people do talk over each other.
    static func assembled(
        recordingID: UUID,
        provenance: Provenance,
        speech: [RecognizedSpeech],
        mediaDuration: TimeInterval
    ) -> Transcript {
        let bySource = Dictionary(grouping: speech, by: \.source)
        let segments = bySource.flatMap { source, heard in
            validSegments(from: heard, of: source, recordingID: recordingID, mediaDuration: mediaDuration)
        }
        return Transcript(
            recordingID: recordingID,
            modelID: provenance.modelID,
            modelVersion: provenance.modelVersion,
            language: provenance.language,
            createdAt: provenance.createdAt,
            segments: inStableOrder(segments)
        )
    }

    private static func validSegments(
        from speech: [RecognizedSpeech],
        of source: TranscriptSource,
        recordingID: UUID,
        mediaDuration: TimeInterval
    ) -> [TranscriptSegment] {
        let chronological = speech.enumerated()
            .filter { heard in
                heard.element.startTime.isFinite && heard.element.endTime.isFinite && heard.element.startTime >= 0
                    && heard.element.endTime >= heard.element.startTime
            }
            .sorted { ($0.element.startTime, $0.offset) < ($1.element.startTime, $1.offset) }
            .map(\.element)
        var result: [TranscriptSegment] = []
        for heard in chronological {
            let previous = result.last
            if let previous, heard.startTime < previous.endTime, sameWords(heard.text, previous.text) {
                continue
            }
            let start = max(heard.startTime, previous?.endTime ?? 0)
            let end = max(heard.endTime, start + minimumSpanSeconds)
            let segment = TranscriptSegment(
                recordingID: recordingID,
                startTime: limited(start, to: mediaDuration),
                endTime: limited(end, to: mediaDuration),
                text: heard.text,
                source: source
            )
            if let segment {
                result.append(segment)
            }
        }
        return result
    }

    private static func inStableOrder(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.sorted {
            ($0.startTime, $0.source.mergeRank, $0.endTime) < ($1.startTime, $1.source.mergeRank, $1.endTime)
        }
    }

    private static func sameWords(_ first: String, _ second: String) -> Bool {
        first.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(second.trimmingCharacters(in: .whitespacesAndNewlines), options: .caseInsensitive) == .orderedSame
    }

    /// A duration of 0 means the media did not report one, which limits nothing.
    private static func limited(_ time: TimeInterval, to mediaDuration: TimeInterval) -> TimeInterval {
        mediaDuration > 0 ? min(time, mediaDuration) : time
    }

    /// Recognizers can report a start and end that coincide; such a segment still needs a moment on the timeline.
    private static let minimumSpanSeconds: TimeInterval = 0.1
}

/// The language to transcribe in. Automatic detection is the default, and is requested explicitly from the recognizer.
enum TranscriptionLanguage: Hashable, Sendable {
    case automatic
    case explicit(code: String)

    /// `nil` for automatic detection.
    var code: String? {
        switch self {
        case .automatic: nil
        case .explicit(let code): code
        }
    }

    /// A code that is no longer supported reads as automatic.
    init(storedCode: String?) {
        if let storedCode, Self.supportedCodes.contains(storedCode) {
            self = .explicit(code: storedCode)
        } else {
            self = .automatic
        }
    }

    /// The languages Whisper models know, as checked against WhisperKit's table by `DependencySmokeTests`.
    static let supportedCodes: [String] = """
        af am ar as az ba be bg bn bo br bs ca cs
        cy da de el en es et eu fa fi fo fr gl gu
        ha haw he hi hr ht hu hy id is it ja jw ka
        kk km kn ko la lb ln lo lt lv mg mi mk ml
        mn mr ms mt my ne nl nn no oc pa pl ps pt
        ro ru sa sd si sk sl sn so sq sr su sv sw
        ta te tg th tk tl tr tt uk ur uz vi yi yo
        yue zh
        """
        .split(separator: /\s+/).map(String.init)
}
