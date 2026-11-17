import Foundation
import Testing

@testable import Verbatim

@MainActor
struct LibraryViewModelTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now: Date

    init() throws {
        let components = DateComponents(year: 2026, month: 11, day: 3, hour: 11, minute: 54)
        now = try #require(calendar.date(from: components))
    }

    private func makeViewModel(_ scenario: LibraryPreviewScenario = .list) -> LibraryViewModel {
        LibraryViewModel(
            previewData: .sample(now: now, calendar: calendar),
            scenario: scenario,
            now: now,
            calendar: calendar
        )
    }

    private func id(of title: String, in viewModel: LibraryViewModel) throws -> LibraryItem.ID {
        try #require(viewModel.items.first { $0.title == title }).id
    }

    @Test func sidebarCountsMatchTheDesign() {
        let viewModel = makeViewModel()

        #expect(viewModel.count(for: .all) == 12)
        #expect(viewModel.count(for: .recent) == 5)
        #expect(viewModel.count(for: .processing) == 4)
        #expect(viewModel.count(for: .screen) == 8)
        #expect(viewModel.count(for: .audio) == 4)
    }

    @Test(arguments: [
        (LibraryPreviewScenario.list, "Architecture Review"),
        (.processing, "Weekly Team Sync"),
        (.confirm, "Design Critique")
    ])
    func scenariosSelectTheDesignRecording(scenario: LibraryPreviewScenario, title: String) {
        #expect(makeViewModel(scenario).selectedItem?.title == title)
    }

    @Test func scenariosShowTheirStates() {
        #expect(makeViewModel(.processing).showsProcessingNote)
        #expect(makeViewModel(.context).contextMenuItem?.title == "Architecture Review")
        #expect(makeViewModel(.confirm).pendingDeletion?.title == "Design Critique")
        #expect(makeViewModel(.empty).content == .empty)
        #expect(makeViewModel(.empty).pathBarItem == nil)
        guard case .searchResults = makeViewModel(.search).content else {
            Issue.record("Expected search results")
            return
        }
    }

    @Test func arrowKeysMoveTheSelectionWithinTheVisibleList() throws {
        let viewModel = makeViewModel()
        viewModel.select(nil)

        viewModel.moveSelection(by: 1)
        #expect(viewModel.selectedItem?.title == "Architecture Review")

        viewModel.moveSelection(by: -1)
        #expect(viewModel.selectedItem?.title == "Architecture Review")

        viewModel.moveSelection(by: 1)
        #expect(viewModel.selectedItem?.title == "Weekly Team Sync")

        viewModel.select(filter: .audio)
        viewModel.moveSelection(by: -1)
        #expect(viewModel.selectedItem?.title == "Podcast Rough Cut")
    }

    @Test func sortingReversesTheList() {
        let viewModel = makeViewModel()

        viewModel.select(sortOrder: .oldestFirst)

        #expect(viewModel.visibleItems.first?.title == "Podcast Rough Cut")
        #expect(viewModel.sortOrder == .oldestFirst)
    }

    @Test func choosingASectionEndsSearchAndClosesTheMenu() {
        let viewModel = makeViewModel(.context)
        viewModel.updateSearchText("budget")

        viewModel.select(filter: .processing)

        #expect(!viewModel.isSearching)
        #expect(viewModel.contextMenuItemID == nil)
        // Architecture Review is not processing, so it no longer stays selected.
        #expect(viewModel.selectedItemID == nil)
    }

    @Test func removingFromLibraryOffersUndo() throws {
        let viewModel = makeViewModel(.context)
        let architecture = try id(of: "Architecture Review", in: viewModel)

        viewModel.removeFromLibrary(architecture)

        #expect(viewModel.items.count == 11)
        #expect(viewModel.lastRemoval?.item.id == architecture)
        #expect(viewModel.contextMenuItemID == nil)
        #expect(viewModel.selectedItem?.title == "Weekly Team Sync")

        viewModel.undoRemoval()

        #expect(viewModel.items.first?.id == architecture)
        #expect(viewModel.selectedItemID == architecture)
        #expect(viewModel.lastRemoval == nil)
    }

    @Test func movingToTrashClosesTheSheetWithoutUndo() throws {
        let viewModel = makeViewModel(.confirm)
        let critique = try id(of: "Design Critique", in: viewModel)

        viewModel.moveToTrash(critique)

        #expect(viewModel.pendingDeletion == nil)
        #expect(viewModel.lastRemoval == nil)
        #expect(!viewModel.items.contains { $0.id == critique })
    }

    @Test func removingEveryRecordingShowsTheEmptyState() {
        let viewModel = makeViewModel()

        for item in viewModel.items {
            viewModel.moveToTrash(item.id)
        }

        #expect(viewModel.content == .empty)
        #expect(viewModel.selectedItemID == nil)
    }

    @Test func processingStartsOnlyForRecordingsThatNeedIt() throws {
        let viewModel = makeViewModel()
        let failed = try id(of: "Design Critique", in: viewModel)
        let ready = try id(of: "Architecture Review", in: viewModel)

        viewModel.startProcessing(failed)
        viewModel.startProcessing(ready)

        #expect(viewModel.items.first { $0.id == failed }?.status == .transcribing(progress: 0.02))
        #expect(viewModel.items.first { $0.id == ready }?.status == .ready)
    }
}

@MainActor
struct SimulatedLibrarySearchTests {
    private let data = LibraryPreviewData.sample()

    @Test func findsExactMomentsBeforeRelatedOnes() throws {
        let results = SimulatedLibrarySearch.results(
            for: "Recording Engine",
            in: data.items,
            transcript: data.transcript
        )

        #expect(results.titleMatches.isEmpty)
        #expect(results.momentCount == 6)
        #expect(
            results.momentGroups.map(\.item.title) == [
                "Architecture Review", "Weekly Team Sync", "1:1 with Maya", "Q4 Planning", "Product Demo"
            ]
        )
        let first = try #require(results.momentGroups.first)
        #expect(first.moments.map(\.match) == [.exact, .related])
    }

    @Test func matchesTitles() {
        let results = SimulatedLibrarySearch.results(for: "maya", in: data.items, transcript: data.transcript)

        #expect(results.titleMatches.map(\.title) == ["1:1 with Maya"])
        #expect(results.resultCount == 1)
    }

    @Test func ignoresRemovedRecordings() {
        let remaining = data.items.filter { $0.title != "Q4 Planning" }

        let results = SimulatedLibrarySearch.results(for: "budget", in: remaining, transcript: data.transcript)

        #expect(results.resultCount == 0)
    }
}

struct LibraryFormatTests {
    @Test(arguments: [(4_360.0, "1:12:40"), (2_538.0, "42:18"), (192.0, "3:12")])
    func formatsDurations(seconds: Double, expected: String) {
        #expect(LibraryFormat.duration(seconds) == expected)
    }

    @Test(arguments: [(260.0, "04:20"), (3_090.0, "51:30")])
    func formatsTimestamps(seconds: Double, expected: String) {
        #expect(LibraryFormat.timestamp(seconds) == expected)
    }

    @Test func shortensTranscriptFileNames() {
        let names = ["recording.mov", "transcript.txt", "transcript.srt", "transcript.json"]

        #expect(LibraryFormat.fileSummary(names) == "recording.mov · transcript.txt · .srt · .json")
    }

    @Test func pluralizesCounts() {
        #expect(LibraryFormat.count(1, singular: "result", plural: "results") == "1 result")
        #expect(LibraryFormat.count(6, singular: "result", plural: "results") == "6 results")
    }
}

struct LibraryPreviewScenarioTests {
    @Test func readsScenarioFromDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "LibraryPreviewScenarioTests"))
        defer { defaults.removePersistentDomain(forName: "LibraryPreviewScenarioTests") }

        #expect(LibraryPreviewScenario.fromLaunchArguments(defaults) == nil)

        defaults.set("confirm", forKey: LibraryPreviewScenario.launchArgumentKey)
        #expect(LibraryPreviewScenario.fromLaunchArguments(defaults) == .confirm)

        defaults.set("unknown", forKey: LibraryPreviewScenario.launchArgumentKey)
        #expect(LibraryPreviewScenario.fromLaunchArguments(defaults) == nil)
    }
}

struct LibraryProcessingStepTests {
    private let recordingID = UUID()

    private func summary(_ state: SummaryJob.State) -> SummaryJob {
        SummaryJob(recordingID: recordingID, state: state, queuedAt: .now)
    }

    private func index(_ state: IndexingJob.State) -> IndexingJob {
        IndexingJob(recordingID: recordingID, state: state, queuedAt: .now)
    }

    @Test func aRecordingWithNothingAfterTranscriptionStaysAsItIs() {
        #expect(LibraryItem.Status(summary: nil, indexing: nil) == nil)
        #expect(LibraryItem.Status(summary: summary(.failed(.noModelSelected)), indexing: nil) == nil)
        #expect(LibraryItem.Status(summary: nil, indexing: index(.failed(.noModelSelected))) == nil)
    }

    @Test(arguments: [
        (SummaryJob.State.loadingModel, 0.0),
        (.summarizingParts(completed: 1, total: 4), 0.2),
        (.combining, 0.8),
        (.saving, 1.0)
    ])
    func aSummaryShowsItsProgressAsTheSecondStep(state: SummaryJob.State, fraction: Double) {
        let status = LibraryItem.Status(summary: summary(state), indexing: index(.queued))

        #expect(status == .summarizing(progress: fraction))
        #expect(status?.stepFraction == "2/3")
    }

    @Test func indexingShowsTheChunksEmbeddedAsTheThirdStep() {
        let status = LibraryItem.Status(summary: nil, indexing: index(.embedding(completed: 3, total: 12)))

        #expect(status == .indexing(progress: 0.25))
        #expect(status?.stepFraction == "3/3")
        #expect(LibraryItem.Status(summary: nil, indexing: index(.chunking)) == .indexing(progress: 0))
    }

    @Test func aRunningStepComesBeforeAQueuedOne() {
        #expect(
            LibraryItem.Status(summary: summary(.queued), indexing: index(.chunking)) == .indexing(progress: 0)
        )
        #expect(LibraryItem.Status(summary: summary(.queued), indexing: index(.queued)) == .waiting(.summary))
        #expect(LibraryItem.Status(summary: nil, indexing: index(.queued)) == .waiting(.indexing))
    }

    @Test func transcriptionIsTheFirstStepAndAFinishedRecordingHasNone() {
        #expect(LibraryItem.Status.transcribing(progress: 0.5).stepFraction == "1/3")
        #expect(LibraryItem.Status.pending.step == .transcription)
        #expect(LibraryItem.Status.ready.step == nil)
        #expect(LibraryItem.Status.waiting(.indexing).stepDescription == "Step 3 of 3: search index")
    }
}
