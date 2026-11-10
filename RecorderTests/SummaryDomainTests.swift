import Foundation
import Testing

@testable import Recorder

struct SummaryDomainTests {
    // MARK: - Batching

    @Test func batchesKeepOrderAndFitTheBudget() {
        let batches = SummaryBatching.batches(tokenCounts: [4, 4, 4, 4, 4], limit: 10)

        #expect(batches == [0..<2, 2..<4, 4..<5])
    }

    @Test func anItemOverTheBudgetGetsABatchOfItsOwn() {
        let batches = SummaryBatching.batches(tokenCounts: [3, 50, 3, 3], limit: 10)

        #expect(batches == [0..<1, 1..<2, 2..<4])
    }

    @Test func nothingToBatchGivesNoBatches() {
        #expect(SummaryBatching.batches(tokenCounts: [], limit: 10).isEmpty)
    }

    // MARK: - Settings

    @Test func storedSettingsAreClampedIntoRangeAndContext() {
        let wild = SummarySettings(
            batchTokens: 1_000_000,
            batchNoteTokens: 5,
            summaryTokens: 99_999,
            temperature: .nan,
            topP: 3,
            topK: -4,
            repetitionPenalty: 0.2
        )

        let clamped = wild.clamped(toContext: 8_000)

        #expect(clamped.batchNoteTokens == SummarySettings.batchNoteTokenRange.lowerBound)
        #expect(clamped.batchTokens == 8_000 - clamped.batchNoteTokens - SummarySettings.promptOverheadTokens)
        #expect(clamped.summaryTokens == SummarySettings.summaryTokenRange.upperBound)
        #expect(clamped.temperature == 0)
        #expect(clamped.topP == 1)
        #expect(clamped.topK == 0)
        #expect(clamped.repetitionPenalty == 1)
    }

    @Test(arguments: LanguageModelCatalog.curated)
    func everyPresetIsAlreadyValid(model: LanguageModel) {
        #expect(model.preset.clamped(toContext: model.contextTokens) == model.preset)
    }

    // MARK: - Catalog

    @Test(arguments: LanguageModelCatalog.curated)
    func catalogEntriesArePinnedAndSafe(model: LanguageModel) {
        #expect(ModelFileStore.isSafeIdentifier(model.id))
        #expect(model.revision.count == 40 && model.revision.allSatisfy(\.isHexDigit))
        #expect(model.repository.split(separator: "/").count == 2)
        #expect(model.sharedFilesKey == nil)
    }

    @Test func theRecommendationFollowsWhatTheMacSupports() {
        let catalog = LanguageModelCatalog.curated
        let everything = Set(catalog.map(\.id))

        #expect(
            LanguageModelCatalog.recommended(from: catalog, supportedIDs: everything)?.id
                == "qwen3-4b-instruct-2507-4bit"
        )
        #expect(
            LanguageModelCatalog.recommended(from: catalog, supportedIDs: ["qwen3-1.7b-4bit"])?.id == "qwen3-1.7b-4bit"
        )
        #expect(LanguageModelCatalog.recommended(from: catalog, supportedIDs: []) == nil)
    }

    // MARK: - Summaries

    @Test func aSummaryIsCurrentOnlyForTheTranscriptItWasMadeFrom() {
        let id = UUID()
        let transcript = SummaryFixtures.transcript(of: id, lines: 2)
        let summary = TranscriptSummary(
            recordingID: id,
            modelID: "m",
            language: "ru",
            transcriptCreatedAt: transcript.createdAt,
            createdAt: .now,
            text: "t",
            parts: []
        )
        let newer = SummaryFixtures.transcript(of: id, lines: 2)
        let remade = Transcript(
            recordingID: id,
            modelID: newer.modelID,
            modelVersion: nil,
            language: "ru",
            createdAt: transcript.createdAt.addingTimeInterval(60),
            segments: newer.segments
        )

        #expect(summary.isCurrent(for: transcript))
        #expect(!summary.isCurrent(for: remade))
    }

    @Test func failuresTranslateFromModelErrors() {
        #expect(SummaryFailure(ModelManagementError.noModelSelected) == .noModelSelected)
        #expect(SummaryFailure(ModelManagementError.selectedModelUnavailable("x")) == .modelUnavailable("x"))
        #expect(SummaryFailure(SummaryFailure.emptyTranscript) == .emptyTranscript)
    }

    // MARK: - Prompts

    @Test func reasoningIsRemovedFromReplies() {
        #expect(SummaryPrompts.cleaned("<think>hmm</think>\n\n- point") == "- point")
        #expect(SummaryPrompts.cleaned("- point <think>unfinished") == "- point")
        #expect(SummaryPrompts.cleaned("  plain  ") == "plain")
    }

    @Test func theAnswerIsAskedForInTheChosenLanguage() {
        #expect(SummaryPrompts.languageName(SummaryFixtures.russian) == "Russian")
        #expect(SummaryPrompts.writingRule(.english).hasPrefix("Write only in English"))
    }

    // MARK: - Language

    @Test func theDefaultIsTheFirstPreferredLanguageOffered() {
        #expect(SummaryLanguage.preferred(from: ["xx-XX", "ru-BY", "en-US"]).code == "ru")
        #expect(SummaryLanguage.preferred(from: ["zh-Hans-CN"]).code == "zh")
        #expect(SummaryLanguage.preferred(from: ["xx"]) == .english)
        #expect(SummaryLanguage.preferred(from: []) == .english)
    }

    @Test func onlyOfferedLanguagesCanBeChosen() {
        #expect(SummaryLanguage(code: "ru") != nil)
        #expect(SummaryLanguage(code: "klingon") == nil)
        #expect(SummaryLanguage.supportedCodes.contains("en"))
    }
}
