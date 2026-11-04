import Foundation
import Testing

@testable import Recorder

struct SQLiteRecordingRepositoryTests {
    private let environment: LibraryTestEnvironment
    private let repository: SQLiteRecordingRepository

    init() throws {
        environment = try LibraryTestEnvironment()
        repository = environment.makeRepository()
    }

    private func insert(
        _ title: String,
        createdAt: TimeInterval = 1_800_000_000,
        duration: TimeInterval = 60,
        mode: CaptureMode = .screen
    ) async throws -> LibraryRecording {
        let recording = try environment.makeRecording(
            title: title,
            createdAt: Date(timeIntervalSince1970: createdAt),
            duration: duration,
            mode: mode
        )
        try await repository.insert(recording)
        return recording
    }

    private func titles(_ query: RecordingQuery) async throws -> [String] {
        try await repository.fetch(matching: query).map(\.recording.title)
    }

    // MARK: - Persistence

    @Test func storedRecordingsSurviveReopeningTheDatabase() async throws {
        let recording = try await insert("Architecture Review", duration: 4_360, mode: .window)

        let reopened = environment.makeRepository()

        let fetched = try #require(try await reopened.fetch(id: recording.id))
        #expect(fetched == recording)
        #expect(try await reopened.count(matching: RecordingQuery()) == 1)
    }

    @Test func fetchingAnUnknownIdentifierFindsNothing() async throws {
        #expect(try await repository.fetch(id: UUID()) == nil)
    }

    @Test func updatesTitleOnly() async throws {
        let recording = try await insert("Old")

        try await repository.updateTitle(id: recording.id, title: "New")

        let fetched = try #require(try await repository.fetch(id: recording.id))
        #expect(fetched.recording.title == "New")
        #expect(fetched.media == recording.media)
    }

    @Test func updatesMetadata() async throws {
        var recording = try await insert("Demo")
        recording.fileSizeBytes = 99
        recording.media.url = environment.root.appending(path: "moved.mov")
        recording.recording.processingStatus = .failed

        try await repository.update(recording)

        #expect(try await repository.fetch(id: recording.id) == recording)
    }

    @Test func deletesTheEntry() async throws {
        let recording = try await insert("Demo")

        try await repository.delete(id: recording.id)

        #expect(try await repository.fetch(id: recording.id) == nil)
    }

    @Test func changingAnUnknownRecordingFails() async throws {
        await #expect(throws: LibraryError.recordingNotFound) {
            try await repository.updateTitle(id: UUID(), title: "New")
        }
        await #expect(throws: LibraryError.recordingNotFound) {
            try await repository.delete(id: UUID())
        }
    }

    @Test func twoEntriesCannotShareOneFile() async throws {
        let recording = try await insert("Demo")
        var duplicate = try environment.makeRecording(title: "Copy")
        duplicate.media = recording.media

        await #expect(throws: LibraryError.alreadyInLibrary) {
            try await repository.insert(duplicate)
        }
    }

    @Test func addsUpFileSizes() async throws {
        _ = try await insert("One")
        _ = try await insert("Two")

        #expect(try await repository.totalFileSize() == 4_096)
    }

    @Test func storesQueryTextLiterallyNotAsSQL() async throws {
        let hostile = "x'); DROP TABLE recordings; --"
        _ = try await insert(hostile)

        var query = RecordingQuery()
        query.search = .init(text: hostile)

        #expect(try await titles(query) == [hostile])
    }

    // MARK: - Sorting and searching

    @Test func sortsEveryWay() async throws {
        _ = try await insert("banana", createdAt: 2_000, duration: 10)
        _ = try await insert("Apple", createdAt: 1_000, duration: 30)
        _ = try await insert("Cherry", createdAt: 3_000, duration: 20)

        var query = RecordingQuery()
        #expect(try await titles(query) == ["Cherry", "banana", "Apple"])
        query.sortOrder = .oldestFirst
        #expect(try await titles(query) == ["Apple", "banana", "Cherry"])
        query.sortOrder = .name
        #expect(try await titles(query) == ["Apple", "banana", "Cherry"])
        query.sortOrder = .duration
        #expect(try await titles(query) == ["Apple", "Cherry", "banana"])
    }

    @Test func searchIgnoresCaseAndAccentsInAnyAlphabet() async throws {
        _ = try await insert("Совещание команды")
        _ = try await insert("Café Meeting")
        _ = try await insert("Other")

        var query = RecordingQuery()
        query.search = .init(text: "СОВЕЩАНИЕ")
        #expect(try await titles(query) == ["Совещание команды"])
        query.search = .init(text: "cafe")
        #expect(try await titles(query) == ["Café Meeting"])
    }

    @Test func searchTreatsWildcardsAsText() async throws {
        _ = try await insert("100% done")
        _ = try await insert("Nothing")

        var query = RecordingQuery()
        query.search = .init(text: "%")

        #expect(try await titles(query) == ["100% done"])
    }

    @Test func searchFindsRecordingsByDateEvenWhenTheTitleDoesNotMatch() async throws {
        _ = try await insert("Inside", createdAt: 1_500)
        _ = try await insert("Outside", createdAt: 2_500)

        var query = RecordingQuery()
        query.search = .init(
            text: "1970",
            recordedDuring: DateInterval(
                start: Date(timeIntervalSince1970: 1_000),
                end: Date(timeIntervalSince1970: 2_000)
            )
        )

        #expect(try await titles(query) == ["Inside"])
    }

    @Test func filtersBySectionConditions() async throws {
        _ = try await insert("Screen", createdAt: 1_000, mode: .screen)
        _ = try await insert("Window", createdAt: 2_000, mode: .window)
        _ = try await insert("Audio", createdAt: 3_000, mode: .audioOnly)

        var query = RecordingQuery()
        query.captureModes = [.audioOnly]
        #expect(try await titles(query) == ["Audio"])
        #expect(try await repository.count(matching: query) == 1)

        query = RecordingQuery()
        query.createdSince = Date(timeIntervalSince1970: 2_000)
        #expect(try await titles(query) == ["Audio", "Window"])

        query = RecordingQuery()
        query.statuses = [.transcribing]
        #expect(try await titles(query).isEmpty)
    }

    // MARK: - Stored data that cannot be trusted

    @Test func skipsARowThatCannotDescribeARecording() async throws {
        _ = try await insert("Good")
        _ = try await repository.count(matching: RecordingQuery())
        let database = try SQLiteDatabase(url: environment.databaseURL)
        try database.execute(
            """
            INSERT INTO recordings (id, title, title_key, created_at, recording_type, media_path, processing_status, \
            updated_at) VALUES ('not-a-uuid', 'Bad', 'bad', 0, 'screen', '/tmp/bad.mov', 'recorded', 0)
            """
        )

        #expect(try await titles(RecordingQuery()) == ["Good"])
    }

    @Test func anUnknownStatusReadsAsNeutral() async throws {
        let recording = try await insert("Demo")
        let database = try SQLiteDatabase(url: environment.databaseURL)
        try database.execute("UPDATE recordings SET processing_status = 'from-the-future'")

        let fetched = try await repository.fetch(id: recording.id)

        #expect(fetched?.recording.processingStatus == .recorded)
    }
}

struct LibrarySchemaTests {
    private let environment: LibraryTestEnvironment

    init() throws {
        environment = try LibraryTestEnvironment()
    }

    private func version(of url: URL) throws -> Int64? {
        try SQLiteDatabase(url: url).query("PRAGMA user_version").first?.integer("user_version")
    }

    private func preparedDatabase() throws -> URL {
        try FileManager.default.createDirectory(
            at: environment.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return environment.databaseURL
    }

    @Test func aNewDatabaseGetsTheLatestVersion() async throws {
        _ = try await environment.makeRepository().count(matching: RecordingQuery())

        #expect(try version(of: environment.databaseURL) == LibrarySchema.migrations.last.map { Int64($0.version) })
    }

    @Test func reopeningKeepsDataAndDoesNotMigrateAgain() async throws {
        let recording = try environment.makeRecording()
        try await environment.makeRepository().insert(recording)

        let fetched = try await environment.makeRepository().fetch(id: recording.id)

        #expect(fetched == recording)
    }

    @Test func laterMigrationsApplyToExistingDataInOrder() async throws {
        let recording = try environment.makeRecording()
        try await environment.makeRepository().insert(recording)
        let upgraded =
            LibrarySchema.migrations + [
                SQLiteMigration(
                    version: 3,
                    sql: "CREATE TABLE third (id INTEGER, second_id INTEGER REFERENCES second (id))"
                ),
                SQLiteMigration(version: 2, sql: "CREATE TABLE second (id INTEGER PRIMARY KEY)")
            ]

        let repository = SQLiteRecordingRepository(databaseURL: environment.databaseURL, migrations: upgraded)

        #expect(try await repository.fetch(id: recording.id) == recording)
        #expect(try version(of: environment.databaseURL) == 3)
    }

    @Test func aFailedMigrationRollsBackAndKeepsTheData() async throws {
        let recording = try environment.makeRecording()
        try await environment.makeRepository().insert(recording)
        let broken =
            LibrarySchema.migrations + [
                SQLiteMigration(version: 2, sql: "CREATE TABLE half_done (id INTEGER); THIS IS NOT SQL;")
            ]

        let repository = SQLiteRecordingRepository(databaseURL: environment.databaseURL, migrations: broken)

        await #expect {
            _ = try await repository.fetch(id: recording.id)
        } throws: { error in
            guard case LibraryError.databaseMigrationFailed = error else {
                return false
            }
            return true
        }
        #expect(try version(of: environment.databaseURL) == 1)
        let tables = try SQLiteDatabase(url: environment.databaseURL)
            .query("SELECT name FROM sqlite_master WHERE name = 'half_done'")
        #expect(tables.isEmpty)
        #expect(try await environment.makeRepository().fetch(id: recording.id) == recording)
    }

    @Test func aDatabaseFromANewerVersionIsLeftAlone() async throws {
        let url = try preparedDatabase()
        try SQLiteDatabase(url: url).executeScript("PRAGMA user_version = 999")

        await #expect(throws: LibraryError.databaseFromNewerVersion) {
            _ = try await environment.makeRepository().count(matching: RecordingQuery())
        }
        #expect(try version(of: url) == 999)
    }

    @Test func aFileThatIsNotADatabaseIsReportedAndKept() async throws {
        let url = try preparedDatabase()
        let contents = Data(repeating: 0x41, count: 8_192)
        try contents.write(to: url)

        await #expect {
            _ = try await environment.makeRepository().count(matching: RecordingQuery())
        } throws: { error in
            guard case LibraryError.databaseUnavailable = error else {
                return false
            }
            return true
        }
        #expect(try Data(contentsOf: url) == contents)
    }
}

struct RecordingDateSearchTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func search() throws -> RecordingDateSearch {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)))
        return RecordingDateSearch(now: now, calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    @Test func understandsNumericDates() throws {
        #expect(try search().interval(matching: "2026-02-03")?.start == date(2026, 2, 3))
        #expect(try search().interval(matching: "2026-02")?.end == date(2026, 3, 1))
        #expect(try search().interval(matching: "2025")?.end == date(2026, 1, 1))
    }

    @Test func understandsWrittenDates() throws {
        #expect(try search().interval(matching: "Feb 3, 2025")?.start == date(2025, 2, 3))
        #expect(try search().interval(matching: "Feb 3")?.start == date(2026, 2, 3))
    }

    @Test func aDateWithoutAYearIsTheMostRecentOne() throws {
        #expect(try search().interval(matching: "Nov 4")?.start == date(2025, 11, 4))
        #expect(try search().interval(matching: "December")?.start == date(2025, 12, 1))
    }

    @Test func understandsRelativeDays() throws {
        #expect(try search().interval(matching: "today")?.start == date(2026, 3, 15))
        #expect(try search().interval(matching: "Yesterday")?.start == date(2026, 3, 14))
    }

    @Test(arguments: ["", "   ", "Weekly sync", "Maybe", "12345"])
    func otherTextIsNotADate(text: String) throws {
        #expect(try search().interval(matching: text) == nil)
    }
}
