import Foundation
import Testing

@testable import Verbatim

struct RecordingTagTests {
    private let environment: LibraryTestEnvironment
    private let repository: SQLiteRecordingRepository
    private let work = RecordingTag.defaults[0]
    private let personal = RecordingTag.defaults[1]

    init() throws {
        environment = try LibraryTestEnvironment()
        repository = environment.makeRepository()
    }

    private func insert(_ title: String, tagIDs: Set<UUID> = []) async throws -> LibraryRecording {
        var recording = try environment.makeRecording(title: title)
        recording.tagIDs = tagIDs
        try await repository.insert(recording)
        return recording
    }

    // MARK: - Tags

    @Test func aNewLibraryHasWorkAndPersonal() async throws {
        let tags = try await repository.fetchTags()

        #expect(tags == RecordingTag.defaults)
        #expect(tags.map(\.name) == ["work", "personal"])
    }

    @Test func newTagsComeAfterTheOthersAndSurviveReopening() async throws {
        let travel = RecordingTag(id: UUID(), name: "Travel", color: .orange)

        try await repository.insertTag(travel)

        #expect(try await environment.makeRepository().fetchTags() == RecordingTag.defaults + [travel])
    }

    @Test func aTagNameIsUniqueIgnoringCase() async throws {
        await #expect(throws: LibraryError.duplicateTagName) {
            try await repository.insertTag(RecordingTag(id: UUID(), name: "WORK", color: .red))
        }
        await #expect(throws: LibraryError.duplicateTagName) {
            try await repository.updateTag(RecordingTag(id: personal.id, name: "Work", color: .red))
        }
    }

    @Test func editingChangesNameAndColorEverywhere() async throws {
        let recording = try await insert("Tagged", tagIDs: [work.id])

        try await repository.updateTag(RecordingTag(id: work.id, name: "Job", color: .purple))

        #expect(try await repository.fetchTags().first == RecordingTag(id: work.id, name: "Job", color: .purple))
        #expect(try await repository.fetch(id: recording.id)?.tagIDs == [work.id])
    }

    @Test func deletingATagRemovesItOnlyFromRecordings() async throws {
        let recording = try await insert("Tagged", tagIDs: [work.id, personal.id])

        try await repository.deleteTag(id: work.id)

        #expect(try await repository.fetch(id: recording.id)?.tagIDs == [personal.id])
        #expect(try await repository.fetchTags() == [personal])
        await #expect(throws: LibraryError.tagNotFound) { try await repository.deleteTag(id: work.id) }
    }

    @Test func tagNamesAreTrimmedAndLimited() throws {
        #expect(try RecordingTag.validatedName("  Trip  ") == "Trip")
        #expect(throws: LibraryError.invalidTagName) { try RecordingTag.validatedName("   ") }
        let tooLong = String(repeating: "a", count: RecordingTag.nameLengthLimit + 1)
        #expect(throws: LibraryError.invalidTagName) { try RecordingTag.validatedName(tooLong) }
    }

    // MARK: - Tags on recordings

    @Test func tagsSurviveReopeningTheDatabase() async throws {
        let recording = try await insert("Tagged", tagIDs: [work.id, personal.id])

        let fetched = try #require(try await environment.makeRepository().fetch(id: recording.id))

        #expect(fetched.tagIDs == [work.id, personal.id])
    }

    @Test func replacingTagsKeepsOnlyTheNewSet() async throws {
        let recording = try await insert("Tagged", tagIDs: [work.id])

        try await repository.updateTags(id: recording.id, tagIDs: [personal.id])

        #expect(try await repository.fetch(id: recording.id)?.tagIDs == [personal.id])
    }

    @Test func unknownRecordingsAndTagsAreRefused() async throws {
        let recording = try await insert("Tagged", tagIDs: [work.id])

        await #expect(throws: LibraryError.recordingNotFound) {
            try await repository.updateTags(id: UUID(), tagIDs: [work.id])
        }
        await #expect(throws: LibraryError.tagNotFound) {
            try await repository.updateTags(id: recording.id, tagIDs: [UUID()])
        }
        #expect(try await repository.fetch(id: recording.id)?.tagIDs == [work.id])
    }

    @Test func aTagFiltersAndCountsRecordings() async throws {
        _ = try await insert("Plain")
        _ = try await insert("Work one", tagIDs: [work.id])
        _ = try await insert("Both", tagIDs: [work.id, personal.id])
        var query = RecordingQuery()
        query.tagID = personal.id

        #expect(try await repository.fetch(matching: query).map(\.recording.title) == ["Both"])
        query.tagID = work.id
        #expect(try await repository.count(matching: query) == 2)
        #expect(try await repository.count(matching: RecordingQuery()) == 3)
    }

    @Test func deletingARecordingRemovesItsTagLinks() async throws {
        let recording = try await insert("Tagged", tagIDs: [work.id])

        try await repository.delete(id: recording.id)

        var query = RecordingQuery()
        query.tagID = work.id
        #expect(try await repository.count(matching: query) == 0)
    }

    // MARK: - Service

    @Test @MainActor func theServiceManagesTagsAndRestoresThemWithAnUndoneRemoval() async throws {
        let service = environment.makeService(repository: repository)
        let recording = try await insert("Tagged")

        try await service.createTag(named: "  Trip ", color: .red)
        let trip = try #require(try await service.tags().last)
        #expect(trip.name == "Trip")

        try await service.setTags([trip.id], for: recording.id)
        let revision = service.revision
        try await service.setTags([trip.id], for: recording.id)
        #expect(service.revision == revision)

        let removed = try await service.removeFromLibrary(recording.id)
        try await service.restore(removed)
        #expect(try await service.recording(withID: recording.id).tagIDs == [trip.id])

        try await service.editTag(trip.id, name: "Holiday", color: .yellow)
        try await service.deleteTag(trip.id)
        #expect(try await service.tags() == RecordingTag.defaults)
        #expect(try await service.recording(withID: recording.id).tagIDs.isEmpty)
    }

    @Test @MainActor func theServiceRefusesABlankTagName() async {
        let service = environment.makeService(repository: repository)

        await #expect(throws: LibraryError.invalidTagName) {
            try await service.createTag(named: " ", color: .red)
        }
    }

    @Test func aTagSectionQueriesItsTag() {
        #expect(LibraryFilter.tagged(work.id).query(now: .now, calendar: .current).tagID == work.id)
    }
}
