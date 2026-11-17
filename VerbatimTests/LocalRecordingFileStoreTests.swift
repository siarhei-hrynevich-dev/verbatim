import Foundation
import Testing

@testable import Verbatim

struct LocalRecordingFileStoreTests {
    private let environment: LibraryTestEnvironment
    private let store: LocalRecordingFileStore

    init() throws {
        environment = try LibraryTestEnvironment()
        store = environment.makeFileStore()
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    // MARK: - Finalized media

    @Test func describesFinishedMedia() async throws {
        let destination = try environment.makeRecordingFolder()

        let snapshot = try await store.describeMedia(at: destination.mediaURL)

        #expect(snapshot.media.url == destination.mediaURL)
        #expect(snapshot.fileSizeBytes == 2_048)
    }

    @Test func refusesMediaThatIsNotThere() async throws {
        let destination = try environment.makeRecordingFolder()
        try FileManager.default.removeItem(at: destination.mediaURL)

        await #expect(throws: LibraryError.mediaUnavailable(.missing)) {
            try await store.describeMedia(at: destination.mediaURL)
        }
    }

    // MARK: - Availability

    @Test func aRecordingInPlaceIsAvailableWithItsRelatedFiles() async throws {
        let recording = try environment.makeRecording()
        let folder = recording.media.url.deletingLastPathComponent()
        try Data("hello".utf8).write(to: folder.appending(path: "transcript.txt"))

        let inspection = await store.inspect(recording)

        #expect(inspection.availability == .available)
        #expect(inspection.fileNames == ["recording.mov", "recording.json", "transcript.txt"])
        #expect(inspection.trashesFolder)
    }

    @Test func aDeletedFileIsMissing() async throws {
        let recording = try environment.makeRecording()
        try FileManager.default.removeItem(at: recording.media.url.deletingLastPathComponent())

        let inspection = await store.inspect(recording)

        #expect(inspection.availability == .missing)
        #expect(inspection.media == recording.media)
    }

    @Test func aFileOnADisconnectedDriveIsReportedAsSuch() async throws {
        let recording = try LibraryRecording(
            recording: Recording(title: "External", duration: 1, processingStatus: .recorded),
            captureMode: .screen,
            media: MediaReference(url: URL(fileURLWithPath: "/Volumes/NoSuchDrive-\(UUID())/a/recording.mov")),
            fileSizeBytes: 1
        )

        #expect(await store.inspect(recording).availability == .volumeUnavailable)
    }

    @Test func aFileMovedInFinderIsFoundThroughItsBookmark() async throws {
        let recording = try environment.makeRecording()
        try #require(recording.media.bookmark != nil)
        let movedURL = environment.root.appending(path: "Renamed Elsewhere.mov")
        try FileManager.default.moveItem(at: recording.media.url, to: movedURL)

        let inspection = await store.inspect(recording)

        #expect(inspection.availability == .available)
        #expect(inspection.media.url.lastPathComponent == "Renamed Elsewhere.mov")
    }

    @Test func aFileTheUserTrashedCountsAsMissing() async throws {
        let recording = try environment.makeRecording()
        let trash = environment.root.appending(path: ".Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: recording.media.url, to: trash.appending(path: "recording.mov"))

        #expect(await store.inspect(recording).availability == .missing)
    }

    // MARK: - Finder

    @Test func finderActionsTargetTheRightItems() async throws {
        let recording = try environment.makeRecording()

        try await store.reveal(recording)
        try await store.openFolder(of: recording)

        #expect(await environment.finder.state.revealed == [recording.media.url])
        #expect(await environment.finder.state.opened == [recording.media.url.deletingLastPathComponent()])
    }

    @Test func finderActionsNeedTheFile() async throws {
        let recording = try environment.makeRecording()
        try FileManager.default.removeItem(at: recording.media.url)

        await #expect(throws: LibraryError.mediaUnavailable(.missing)) {
            try await store.reveal(recording)
        }
        #expect(await environment.finder.state.revealed.isEmpty)
    }

    @Test func aFolderThatCannotBeOpenedIsRevealedInstead() async throws {
        let recording = try environment.makeRecording()
        await environment.finder.state.setOpensSucceed(false)

        try await store.openFolder(of: recording)

        #expect(await environment.finder.state.revealed == [recording.media.url.deletingLastPathComponent()])
    }

    @Test func openingTheRecordingsFolderCreatesItFirst() async throws {
        let folder = environment.root.appending(path: "Not Yet Created", directoryHint: .isDirectory)

        try await store.openFolder(at: folder)

        #expect(exists(folder))
        #expect(await environment.finder.state.opened == [folder])
    }

    // MARK: - Trash

    @Test func movesAnOwnedFolderToTheTrashWhole() async throws {
        let recording = try environment.makeRecording()
        let folder = recording.media.url.deletingLastPathComponent()

        let leftBehind = try await store.moveToTrash(recording)

        #expect(leftBehind.isEmpty)
        #expect(!exists(folder))
        #expect(try environment.trashedItemNames().count == 1)
        #expect(try environment.trashedItemNames().first?.hasSuffix(folder.lastPathComponent) == true)
    }

    @Test func leavesFilesItDoesNotOwnInARecordingFolder() async throws {
        let recording = try environment.makeRecording()
        let folder = recording.media.url.deletingLastPathComponent()
        let personal = folder.appending(path: "my notes.txt")
        try Data("mine".utf8).write(to: personal)

        let inspection = await store.inspect(recording)
        _ = try await store.moveToTrash(recording)

        #expect(!inspection.trashesFolder)
        #expect(exists(personal))
        #expect(!exists(recording.media.url))
        #expect(!exists(folder.appending(path: RecordingFileLayout.metadataFileName)))
        #expect(try environment.trashedItemNames().count == 2)
    }

    @Test func inAFolderItDidNotCreateOnlyTheMediaGoes() async throws {
        let folder = environment.root.appending(path: "Client Work", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let media = folder.appending(path: "final.mov")
        try Data(repeating: 1, count: 16).write(to: media)
        // Same names as app-owned files, but in a folder that is the user's.
        let lookalike = folder.appending(path: RecordingFileLayout.metadataFileName)
        try Data("{}".utf8).write(to: lookalike)
        var recording = try environment.makeRecording()
        recording.media = MediaReference(url: media)

        _ = try await store.moveToTrash(recording)

        #expect(!exists(media))
        #expect(exists(lookalike))
        #expect(exists(folder))
    }

    @Test func aFolderOwnedByAnotherRecordingIsNotOwned() throws {
        let id = UUID()
        let name = RecordingFileLayout.directoryName(createdAt: .now, id: id)

        #expect(RecordingFileLayout.isOwnedDirectory(named: name, recordingID: id))
        #expect(!RecordingFileLayout.isOwnedDirectory(named: name, recordingID: UUID()))
        #expect(!RecordingFileLayout.isOwnedDirectory(named: "Movies", recordingID: id))
    }

    @Test func whenTheTrashRefusesTheMediaNothingIsLost() async throws {
        let recording = try environment.makeRecording()
        let failing = LocalRecordingFileStore(systemActions: environment.finder) { _ in
            throw TestError.failed
        }

        await #expect {
            _ = try await failing.moveToTrash(recording)
        } throws: { error in
            guard case LibraryError.trashFailed = error else {
                return false
            }
            return true
        }
        #expect(exists(recording.media.url))
    }

    @Test func aRelatedFileThatStaysBehindIsReported() async throws {
        let recording = try environment.makeRecording()
        let trashFolder = environment.trashFolder
        // Refuses the folder and the sidecar, as a partly accessible folder would.
        let picky = LocalRecordingFileStore(systemActions: environment.finder) { url in
            guard url.lastPathComponent == RecordingFileLayout.mediaFileName else {
                throw TestError.failed
            }
            try FileManager.default.moveItem(at: url, to: trashFolder.appending(path: url.lastPathComponent))
        }

        let leftBehind = try await picky.moveToTrash(recording)

        #expect(leftBehind == [RecordingFileLayout.metadataFileName])
        #expect(!exists(recording.media.url))
    }

    // MARK: - Choosing a replacement

    @Test func acceptsPlayableMediaOfTheSameKind() async throws {
        let recording = try environment.makeRecording(mode: .window)
        let url = try await environment.writePlayableMedia(hasVideo: true)

        let snapshot = try await store.validateReplacement(at: url, for: recording)

        #expect(snapshot.media.url == url)
        #expect(snapshot.fileSizeBytes > 0)
        #expect(snapshot.duration.map { $0 > 0 } == true)
    }

    @Test func refusesMediaOfAnotherKind() async throws {
        let recording = try environment.makeRecording(mode: .screen)
        let url = try await environment.writePlayableMedia(hasVideo: false)

        await #expect(throws: LibraryError.incompatibleMedia) {
            try await store.validateReplacement(at: url, for: recording)
        }
    }

    @Test func refusesAFileThatIsNotMedia() async throws {
        let recording = try environment.makeRecording()

        await #expect(throws: LibraryError.corruptedMedia) {
            // The stand-in media file has the right name but is not a movie.
            try await store.validateReplacement(at: recording.media.url, for: recording)
        }
    }
}

struct VideoThumbnailProviderTests {
    private let environment: LibraryTestEnvironment

    init() throws {
        environment = try LibraryTestEnvironment()
    }

    private func recording(mode: CaptureMode, at url: URL) throws -> LibraryRecording {
        try LibraryRecording(
            recording: Recording(title: "Demo", duration: 1, processingStatus: .recorded),
            captureMode: mode,
            media: MediaReference(url: url),
            fileSizeBytes: 1
        )
    }

    @Test func generatesOnceAndServesFromTheCacheAfterwards() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: true)
        let recording = try recording(mode: .screen, at: url)

        let first = try #require(await environment.thumbnails.thumbnail(for: recording))
        try FileManager.default.removeItem(at: url)
        let second = await environment.thumbnails.thumbnail(for: recording)

        #expect(!first.isEmpty)
        #expect(second == first)
    }

    @Test func survivesRelaunchThroughTheDiskCache() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: true)
        let recording = try recording(mode: .screen, at: url)
        let folder = environment.root.appending(path: "Thumbnails", directoryHint: .isDirectory)
        let first = try #require(await VideoThumbnailProvider(cacheFolder: folder).thumbnail(for: recording))
        try FileManager.default.removeItem(at: url)

        let afterRelaunch = await VideoThumbnailProvider(cacheFolder: folder).thumbnail(for: recording)

        #expect(afterRelaunch == first)
    }

    @Test func audioAndUnreadableMediaHaveNoThumbnail() async throws {
        let audio = try await environment.writePlayableMedia(hasVideo: false)
        let notMedia = try environment.makeRecording().media.url

        let audioRecording = try recording(mode: .audioOnly, at: audio)
        let unreadable = try recording(mode: .screen, at: notMedia)

        #expect(await environment.thumbnails.thumbnail(for: audioRecording) == nil)
        #expect(await environment.thumbnails.thumbnail(for: unreadable) == nil)
    }

    @Test func discardingForgetsTheThumbnail() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: true)
        let recording = try recording(mode: .screen, at: url)
        _ = await environment.thumbnails.thumbnail(for: recording)
        try FileManager.default.removeItem(at: url)

        await environment.thumbnails.discardThumbnail(for: recording.id)

        #expect(await environment.thumbnails.thumbnail(for: recording) == nil)
    }
}
