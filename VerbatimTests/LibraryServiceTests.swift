import Foundation
import Testing

@testable import Verbatim

@MainActor
struct LibraryServiceTests {
    private let environment: LibraryTestEnvironment
    private let repository: SQLiteRecordingRepository
    private let service: LibraryService

    init() throws {
        environment = try LibraryTestEnvironment()
        repository = environment.makeRepository()
        service = environment.makeService(repository: repository)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func stored(_ recording: LibraryRecording? = nil) async throws -> LibraryRecording {
        let recording = try recording ?? environment.makeRecording()
        try await repository.insert(recording)
        return recording
    }

    // MARK: - Recording finalization

    /// The real coordinator and service together, with only the capture hardware faked.
    private func finishARecording(
        library: any FinishedRecordingRegistry,
        destination: RecordingDestination
    ) async -> RecordingCoordinator {
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let services = FakeRecordingServices(session: session)
        let coordinator = RecordingCoordinator(
            engine: services,
            permissions: FakePermissions(),
            destinations: PreparedDestination(destination: destination),
            metadataStore: services,
            library: library
        )
        coordinator.requestStart(TestFixtures.configuration(target: .window(TestFixtures.window)))
        await coordinator.waitUntilSettled()
        coordinator.requestStop()
        await coordinator.waitUntilSettled()
        return coordinator
    }

    @Test func aFinishedRecordingAppearsInTheLibrary() async throws {
        let destination = try environment.makeRecordingFolder()
        let revision = service.revision

        let coordinator = await finishARecording(library: service, destination: destination)

        let entries = try await service.recordings(matching: RecordingQuery())
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(coordinator.lastOutcome?.metadataErrorDetail == nil)
        #expect(entry.id == coordinator.lastOutcome?.metadata.recording.id)
        #expect(entry.media.url == destination.mediaURL)
        #expect(entry.fileSizeBytes == 2_048)
        #expect(entry.recording.duration == TestFixtures.media.duration)
        #expect(entry.captureMode == .window)
        #expect(entry.recording.processingStatus == .recorded)
        #expect(service.revision > revision)
    }

    @Test func historySurvivesARestart() async throws {
        let destination = try environment.makeRecordingFolder()
        _ = await finishARecording(library: service, destination: destination)

        let afterRestart = environment.makeService()

        #expect(try await afterRestart.recordings(matching: RecordingQuery()).count == 1)
    }

    @Test func aDatabaseFailureLeavesTheMediaAndIsReported() async throws {
        let destination = try environment.makeRecordingFolder()
        let failing = environment.makeService(repository: WriteFailingRepository(base: repository))

        let coordinator = await finishARecording(library: failing, destination: destination)

        #expect(exists(destination.mediaURL))
        #expect(coordinator.state == .idle)
        #expect(coordinator.lastOutcome?.metadataErrorDetail != nil)
        #expect(try await service.recordings(matching: RecordingQuery()).isEmpty)
    }

    @Test func mediaThatDidNotReachTheDiskGetsNoEntry() async throws {
        let destination = try environment.makeRecordingFolder()
        try FileManager.default.removeItem(at: destination.mediaURL)

        let coordinator = await finishARecording(library: service, destination: destination)

        #expect(coordinator.lastOutcome?.metadataErrorDetail != nil)
        #expect(try await service.recordings(matching: RecordingQuery()).isEmpty)
    }

    @Test func anUnfinishedRecordingGetsNoEntry() async throws {
        let session = FakeCaptureSession(finalizeResult: .failure(TestError.failed))
        let services = FakeRecordingServices(session: session)
        await services.configure(isFolderEmpty: false)
        let coordinator = RecordingCoordinator(
            engine: services,
            permissions: FakePermissions(),
            destinations: services,
            metadataStore: services,
            library: services
        )
        coordinator.requestStart(TestFixtures.configuration())
        await coordinator.waitUntilSettled()
        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        #expect(await services.libraryEntries.isEmpty)
        #expect(await services.savedMetadata.count == 1)
    }

    @Test func storingInTheLibraryIsIndependentOfTheSidecar() async throws {
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let services = FakeRecordingServices(session: session)
        await services.configure(saveError: TestError.failed)
        let coordinator = RecordingCoordinator(
            engine: services,
            permissions: FakePermissions(),
            destinations: services,
            metadataStore: services,
            library: services
        )
        coordinator.requestStart(TestFixtures.configuration())
        await coordinator.waitUntilSettled()
        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        #expect(await services.libraryEntries.count == 1)
        #expect(coordinator.lastOutcome?.metadataErrorDetail != nil)
    }

    // MARK: - Renaming

    @Test func renamingChangesTheTitleAndNoFile() async throws {
        let recording = try await stored()
        let revision = service.revision

        try await service.rename(recording.id, to: "  Quarterly Review  ")

        let fetched = try await repository.fetch(id: recording.id)
        #expect(fetched?.recording.title == "Quarterly Review")
        #expect(fetched?.media.url == recording.media.url)
        #expect(exists(recording.media.url))
        #expect(service.revision > revision)
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func anEmptyTitleIsRefused(title: String) async throws {
        let recording = try await stored()

        await #expect(throws: LibraryError.invalidTitle) {
            try await service.rename(recording.id, to: title)
        }
        #expect(try await repository.fetch(id: recording.id)?.recording.title == recording.recording.title)
    }

    @Test func aRenameThatCannotBeStoredIsReported() async throws {
        let recording = try await stored()
        let failing = environment.makeService(repository: WriteFailingRepository(base: repository))

        await #expect(throws: LibraryError.persistenceFailed(detail: "disk full")) {
            try await failing.rename(recording.id, to: "New")
        }
    }

    // MARK: - Removing and deleting

    @Test func removingFromTheLibraryLeavesEveryFile() async throws {
        let recording = try await stored()
        let folder = recording.media.url.deletingLastPathComponent()

        let removed = try await service.removeFromLibrary(recording.id)

        #expect(removed == recording)
        #expect(try await repository.fetch(id: recording.id) == nil)
        #expect(exists(recording.media.url))
        #expect(exists(folder.appending(path: RecordingFileLayout.metadataFileName)))
        #expect(try environment.trashedItemNames().isEmpty)
    }

    @Test func aRemovedRecordingCanBeRestored() async throws {
        let recording = try await stored()
        let removed = try await service.removeFromLibrary(recording.id)

        try await service.restore(removed)

        #expect(try await repository.fetch(id: recording.id) == recording)
    }

    @Test func deletingMovesFilesToTheTrashAndThenForgets() async throws {
        let recording = try await stored()

        let leftBehind = try await service.delete(recording.id)

        #expect(leftBehind.isEmpty)
        #expect(try await repository.fetch(id: recording.id) == nil)
        #expect(!exists(recording.media.url))
        #expect(try environment.trashedItemNames().count == 1)
    }

    @Test func whenTheTrashFailsTheEntryStays() async throws {
        let recording = try await stored()
        let failing = environment.makeService(
            repository: repository,
            fileStore: TrashFailingFileStore(base: environment.makeFileStore())
        )

        await #expect(throws: LibraryError.trashFailed(detail: "The volume is read-only.")) {
            _ = try await failing.delete(recording.id)
        }
        #expect(try await repository.fetch(id: recording.id) == recording)
        #expect(exists(recording.media.url))
    }

    @Test func aMissingFileIsNotDeletedAndKeepsItsEntry() async throws {
        let recording = try await stored()
        try FileManager.default.removeItem(at: recording.media.url.deletingLastPathComponent())

        await #expect(throws: LibraryError.mediaUnavailable(.missing)) {
            _ = try await service.delete(recording.id)
        }
        #expect(try await repository.fetch(id: recording.id) == recording)
    }

    @Test func trashedFilesWithAnEntryThatCannotBeRemovedAreReported() async throws {
        let recording = try await stored()
        let failing = environment.makeService(repository: WriteFailingRepository(base: repository))

        await #expect {
            _ = try await failing.delete(recording.id)
        } throws: { error in
            guard case LibraryError.entryKeptAfterTrash = error else {
                return false
            }
            return true
        }
        #expect(try await repository.fetch(id: recording.id) != nil)
    }

    // MARK: - Missing and moved files

    @Test func aMissingFileIsDetectedAndTheEntryKept() async throws {
        let recording = try await stored()
        try FileManager.default.removeItem(at: recording.media.url)

        let inspections = await service.inspect([recording])

        #expect(inspections[recording.id]?.availability == .missing)
        #expect(try await repository.fetch(id: recording.id) != nil)
    }

    @Test func aFileMovedInFinderUpdatesItsStoredLocation() async throws {
        let recording = try await stored()
        let movedURL = environment.root.appending(path: "moved.mov")
        try FileManager.default.moveItem(at: recording.media.url, to: movedURL)

        _ = await service.inspect([recording])

        let fetched = try await repository.fetch(id: recording.id)
        #expect(fetched?.media.url.lastPathComponent == "moved.mov")
    }

    @Test func locatingRepointsTheSameEntry() async throws {
        let recording = try await stored()
        try FileManager.default.removeItem(at: recording.media.url)
        let replacement = try await environment.writePlayableMedia(hasVideo: true)

        try await service.relocate(recording.id, to: replacement)

        let entries = try await service.recordings(matching: RecordingQuery())
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.id == recording.id)
        #expect(entry.recording.title == recording.recording.title)
        #expect(entry.media.url == replacement)
        #expect(entry.fileSizeBytes > 0)
        #expect(await service.inspect([entry])[entry.id]?.availability == .available)
    }

    @Test func aRefusedFileLeavesTheEntryAsItWas() async throws {
        let recording = try await stored()
        let notMedia = environment.root.appending(path: "notes.mov")
        try Data("text".utf8).write(to: notMedia)

        await #expect(throws: LibraryError.corruptedMedia) {
            try await service.relocate(recording.id, to: notMedia)
        }
        #expect(try await repository.fetch(id: recording.id) == recording)
    }

    @Test func locatingAFileAnotherEntryUsesIsRefused() async throws {
        let replacement = try await environment.writePlayableMedia(hasVideo: true)
        var other = try environment.makeRecording(title: "Other")
        other.media = MediaReference(url: replacement)
        try await repository.insert(other)
        let recording = try await stored()

        await #expect(throws: LibraryError.alreadyInLibrary) {
            try await service.relocate(recording.id, to: replacement)
        }
    }

    // MARK: - Finder

    @Test func openingTheRecordingsFolderUsesTheConfiguredFolder() async throws {
        try await service.openRecordingsFolder()

        #expect(await environment.finder.state.opened == [environment.recordingsFolder])
    }
}

/// Hands out one folder prepared in advance, so a test can put files in it.
private struct PreparedDestination: RecordingDestinationStore {
    let destination: RecordingDestination

    func currentLocation() async -> RecordingLocation {
        RecordingLocation(
            url: destination.directoryURL.deletingLastPathComponent(),
            displayPath: "~/Verbatim",
            availableBytes: 100_000_000_000,
            isAccessible: true
        )
    }
    func prepareDestination(id: UUID, createdAt: Date) async throws -> RecordingDestination { destination }
    func discardIfEmpty(_ destination: RecordingDestination) async -> Bool { false }
    func useFolder(_ url: URL) async throws {}
    func useDefaultFolder() async {}
}

// MARK: - Generated titles

extension LibraryServiceTests {
    @Test func aGeneratedTitleReplacesTheDefaultOne() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let recording = try await stored(
            environment.makeRecording(title: RecordingMetadata.defaultTitle(createdAt: createdAt), createdAt: createdAt)
        )

        try await service.applyGeneratedTitle("Budget planning", to: recording.id)

        #expect(try await repository.fetch(id: recording.id)?.recording.title == "Budget planning")
    }

    @Test func aGeneratedTitleNeverReplacesOneTheUserChose() async throws {
        let recording = try await stored()
        let revision = service.revision

        try await service.applyGeneratedTitle("Budget planning", to: recording.id)

        #expect(try await repository.fetch(id: recording.id)?.recording.title == "Demo")
        #expect(service.revision == revision)
    }
}
