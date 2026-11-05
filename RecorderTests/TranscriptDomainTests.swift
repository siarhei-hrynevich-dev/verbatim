import Foundation
import Testing

@testable import Recorder

struct TranscriptAssemblyTests {
    private let recordingID = UUID()

    private func assembled(_ speech: [RecognizedSpeech], duration: TimeInterval = 100) -> Transcript {
        Transcript.assembled(
            recordingID: recordingID,
            provenance: .init(
                modelID: "model",
                modelVersion: nil,
                language: "en",
                createdAt: Date(timeIntervalSince1970: 1_000)
            ),
            speech: speech,
            mediaDuration: duration
        )
    }

    private func speech(
        _ start: TimeInterval,
        _ end: TimeInterval,
        _ text: String = "words",
        _ source: TranscriptSource = .microphone
    ) -> RecognizedSpeech {
        RecognizedSpeech(startTime: start, endTime: end, text: text, source: source)
    }

    @Test func invalidTimesAndBlankTextAreDropped() {
        let transcript = assembled([
            speech(.nan, 1),
            speech(1, .infinity),
            speech(-3, -2),
            speech(4, 5, "   \n"),
            speech(6, 7, "Kept")
        ])

        #expect(transcript.segments.map(\.text) == ["Kept"])
    }

    @Test func aSegmentAlwaysHasAMomentOnTheTimelineAndStaysInsideTheMedia() {
        let transcript = assembled([speech(5, 5, "Blink"), speech(9, 40, "Long")], duration: 10)

        #expect(transcript.segments[0].endTime > transcript.segments[0].startTime)
        #expect(transcript.segments[1].endTime == 10)
    }

    @Test func segmentsAreOrderedByTimeThenSourceWhateverOrderTheyArriveIn() {
        let transcript = assembled([
            speech(10, 12, "c", .microphone),
            speech(4, 6, "b", .systemAudio),
            speech(4, 6, "a", .microphone),
            speech(0, 1, "z", .systemAudio)
        ])

        #expect(transcript.segments.map(\.text) == ["z", "a", "b", "c"])
        #expect(
            assembled(
                transcript.segments.reversed().map {
                    speech($0.startTime, $0.endTime, $0.text, $0.source)
                }
            ).segments.map(\.text) == ["z", "a", "b", "c"]
        )
    }

    @Test func speechRepeatedAtAChunkBoundaryAppearsOnce() {
        let transcript = assembled([speech(28, 30.5, "the same words"), speech(30, 31, "The same words ")])

        #expect(transcript.segments.count == 1)
    }

    @Test func differentSpeechOverlappingWithinASourceMovesRatherThanDisappears() {
        let transcript = assembled([speech(28, 30.5, "first"), speech(30, 32, "second")])

        #expect(transcript.segments.map(\.text) == ["first", "second"])
        #expect(transcript.segments[1].startTime == 30.5)
    }

    @Test func differentSourcesMayOverlapUnchanged() {
        let transcript = assembled([speech(1, 5, "me"), speech(2, 3, "them", .systemAudio)])

        #expect(transcript.segments.map(\.startTime) == [1, 2])
        #expect(transcript.segments.map(\.endTime) == [5, 3])
    }

    @Test func aSegmentCannotBeBuiltFromTimesRunningBackwards() {
        #expect(
            TranscriptSegment(recordingID: recordingID, startTime: 2, endTime: 1, text: "a", source: .unknown) == nil
        )
        #expect(
            TranscriptSegment(recordingID: recordingID, startTime: 1, endTime: 2, text: " ", source: .unknown) == nil
        )
    }
}

struct TranscriptFormatTests {
    private let transcript: Transcript
    private let id = UUID()

    init() {
        transcript = Transcript.assembled(
            recordingID: id,
            provenance: .init(
                modelID: "openai_whisper-tiny",
                modelVersion: "tiny",
                language: "en",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            speech: [
                RecognizedSpeech(startTime: 3_725.5, endTime: 3_727, text: "Later.", source: .systemAudio),
                RecognizedSpeech(startTime: 1.25, endTime: 4, text: "Hello\nthere.", source: .microphone),
                RecognizedSpeech(startTime: 2, endTime: 3, text: "Hi.", source: .systemAudio)
            ],
            mediaDuration: 4_000
        )
    }

    private func text(_ format: TranscriptFormat) throws -> String {
        try #require(String(bytes: try format.rendered(transcript), encoding: .utf8))
    }

    @Test func srtHasNumberedChronologicalCuesWithValidTimes() throws {
        let expected = """
            1
            00:00:01,250 --> 00:00:04,000
            [You] Hello there.

            2
            00:00:02,000 --> 00:00:03,000
            [System Audio] Hi.

            3
            01:02:05,500 --> 01:02:07,000
            [System Audio] Later.


            """
        #expect(try text(.subtitles) == expected)
    }

    @Test func srtWithOneSourceHasNoLabels() throws {
        let single = Transcript.assembled(
            recordingID: id,
            provenance: .init(modelID: "m", modelVersion: nil, language: nil, createdAt: .now),
            speech: [RecognizedSpeech(startTime: 0, endTime: 1, text: "Solo", source: .microphone)],
            mediaDuration: 2
        )

        let rendered = try #require(String(bytes: try TranscriptFormat.subtitles.rendered(single), encoding: .utf8))

        #expect(rendered == "1\n00:00:00,000 --> 00:00:01,000\nSolo\n\n")
    }

    @Test func aZeroLengthCueStillEndsAfterItStarts() throws {
        let single = Transcript(
            recordingID: id,
            modelID: "m",
            modelVersion: nil,
            language: nil,
            createdAt: .now,
            segments: [TranscriptSegment(recordingID: id, startTime: 5, endTime: 5, text: "a", source: .unknown)]
                .compactMap { $0 }
        )

        let rendered = try #require(String(bytes: try TranscriptFormat.subtitles.rendered(single), encoding: .utf8))

        #expect(rendered.contains("00:00:05,000 --> 00:00:05,001"))
    }

    @Test func textHasOneLabeledTimestampedLinePerSegment() throws {
        let expected = """
            [00:00:01] You: Hello there.
            [00:00:02] System Audio: Hi.
            [01:02:05] System Audio: Later.

            """
        #expect(try text(.text) == expected)
    }

    @Test func jsonKeepsTimesSourcesAndModel() throws {
        let object = try JSONSerialization.jsonObject(with: try TranscriptFormat.json.rendered(transcript))
        let document = try #require(object as? [String: Any])
        let segments = try #require(document["segments"] as? [[String: Any]])
        let model = try #require(document["model"] as? [String: Any])

        #expect(document["recordingID"] as? String == id.uuidString)
        #expect(document["language"] as? String == "en")
        #expect(model["id"] as? String == "openai_whisper-tiny")
        #expect(model["version"] as? String == "tiny")
        #expect(segments.count == 3)
        #expect(segments[0]["start"] as? Double == 1.25)
        #expect(segments[0]["end"] as? Double == 4)
        #expect(segments[0]["source"] as? String == "microphone")
    }

    @Test func fileNamesAreTheOnesTheLibraryKnowsToBelongToARecording() {
        #expect(Set(TranscriptFormat.allCases.map(\.fileName)) == Set(RecordingFileLayout.transcriptFileNames))
    }
}

struct TranscriptionJobTests {
    @Test func aFinishedJobCanOnlyGoBackToTheQueue() {
        for state in [TranscriptionJob.State.completed, .failed, .cancelled] {
            for next in TranscriptionJob.State.allCases {
                #expect(state.allowsTransition(to: next) == (next == .pending))
            }
        }
    }

    @Test func runningJobsCanReturnToTheQueueButQueuedOnesCannotJumpAhead() {
        for state in [TranscriptionJob.State.preparing, .transcribing, .saving] {
            #expect(state.allowsTransition(to: .pending))
        }
        #expect(!TranscriptionJob.State.pending.allowsTransition(to: .transcribing))
        #expect(!TranscriptionJob.State.pending.allowsTransition(to: .completed))
        #expect(!TranscriptionJob.State.transcribing.allowsTransition(to: .completed))
    }

    @Test func aStoppedJobLeavesTheRecordingAsItWas() {
        #expect(TranscriptionJob.State.cancelled.recordingStatus(hasTranscript: true) == .ready)
        #expect(TranscriptionJob.State.cancelled.recordingStatus(hasTranscript: false) == .recorded)
        #expect(TranscriptionJob.State.saving.recordingStatus(hasTranscript: true) == .transcribing)
    }

    @Test func failuresSurviveBeingStored() throws {
        let failures: [TranscriptionFailure] = [
            .noModelSelected,
            .modelUnavailable("tiny"),
            .mediaUnavailable(.volumeUnavailable),
            .insufficientDiskSpace(requiredBytes: 5, availableBytes: 1),
            .recognitionFailed(detail: "details")
        ]
        for failure in failures {
            let data = try JSONEncoder().encode(failure)
            #expect(try JSONDecoder().decode(TranscriptionFailure.self, from: data) == failure)
        }
    }

    @Test func errorsFromOtherLayersAreTranslated() {
        #expect(TranscriptionFailure(ModelManagementError.noModelSelected) == .noModelSelected)
        #expect(TranscriptionFailure(ModelManagementError.selectedModelUnavailable("x")) == .modelUnavailable("x"))
        #expect(TranscriptionFailure(LibraryError.mediaUnavailable(.missing)) == .mediaUnavailable(.missing))
        #expect(TranscriptionFailure(LibraryError.recordingNotFound) == .recordingNotFound)
    }

    @Test func storedLanguagesThatAreNoLongerSupportedReadAsAutomatic() {
        #expect(TranscriptionLanguage(storedCode: nil) == .automatic)
        #expect(TranscriptionLanguage(storedCode: "klingon") == .automatic)
        #expect(TranscriptionLanguage(storedCode: "de") == .explicit(code: "de"))
    }
}
