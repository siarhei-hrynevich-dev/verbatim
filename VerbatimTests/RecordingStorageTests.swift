import Foundation
import Testing

@testable import Verbatim

struct RecordingPreferencesStoreTests {
    private func withStore(_ body: (UserDefaultsRecordingPreferencesStore, UserDefaults) throws -> Void) throws {
        let suiteName = "RecordingPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(UserDefaultsRecordingPreferencesStore(defaults: defaults), defaults)
    }

    @Test func unsetPreferencesUseTheDefaults() throws {
        try withStore { store, _ in
            #expect(store.load() == RecordingPreferences())
        }
    }

    @Test func roundTripsEveryPreference() throws {
        try withStore { store, _ in
            let preferences = RecordingPreferences(
                captureMode: .window,
                displayID: "display",
                windowID: "42",
                windowBundleIdentifier: "com.apple.Notes",
                windowTitle: "Agenda",
                microphoneID: "mic",
                isMicrophoneEnabled: false,
                isSystemAudioEnabled: false,
                quality: .native,
                frameRate: .fps30,
                transcribesWhenFinished: false
            )

            store.save(preferences)

            #expect(store.load() == preferences)
        }
    }

    @Test func invalidStoredValuesFallBackToDefaults() throws {
        try withStore { store, defaults in
            defaults.set("hologram", forKey: "recording.captureMode")
            defaults.set(24, forKey: "recording.frameRate")

            #expect(store.load().captureMode == .screen)
            #expect(store.load().frameRate == .fps60)
        }
    }
}

struct FileRecordingStoreTests {
    private func withStore(_ body: (FileRecordingStore, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FileRecordingStoreTests-\(UUID())")
        let suiteName = "FileRecordingStoreTests-\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let folder = root.appending(path: "Movies/Verbatim", directoryHint: .isDirectory)
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        try await body(FileRecordingStore(defaults: defaults, defaultFolder: folder), folder)
    }

    @Test func createsTheFolderTreeAndOneDirectoryPerRecording() async throws {
        try await withStore { store, folder in
            let date = Date()

            let first = try await store.prepareDestination(id: UUID(), createdAt: date)
            let second = try await store.prepareDestination(id: UUID(), createdAt: date)

            #expect(first.directoryURL != second.directoryURL)
            #expect(first.mediaURL.lastPathComponent == "recording.mov")
            #expect(second.mediaURL.lastPathComponent == "recording.mov")
            let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            #expect(contents.count == 2)
        }
    }

    @Test func neverReusesAnExistingRecordingDirectory() async throws {
        try await withStore { store, _ in
            let id = UUID()
            let date = Date()
            let destination = try await store.prepareDestination(id: id, createdAt: date)
            try Data("existing".utf8).write(to: destination.mediaURL)

            await #expect(throws: RecordingFailure.self) {
                _ = try await store.prepareDestination(id: id, createdAt: date)
            }
            #expect(try Data(contentsOf: destination.mediaURL) == Data("existing".utf8))
        }
    }

    @Test func unwritableLocationFailsWithItsPath() async throws {
        let store = FileRecordingStore(
            defaults: .standard,
            defaultFolder: URL(fileURLWithPath: "/System/Verbatim-does-not-exist", isDirectory: true)
        )

        await #expect {
            _ = try await store.prepareDestination(id: UUID(), createdAt: Date())
        } throws: { error in
            guard case .destinationUnavailable(let path, _) = error as? RecordingFailure else {
                return false
            }
            return path.contains("Verbatim-does-not-exist")
        }
        #expect(await store.currentLocation().isAccessible == false)
    }

    @Test func discardsOnlyEmptyDirectories() async throws {
        try await withStore { store, _ in
            let empty = try await store.prepareDestination(id: UUID(), createdAt: Date())
            let used = try await store.prepareDestination(id: UUID(), createdAt: Date())
            try Data("media".utf8).write(to: used.mediaURL)

            #expect(await store.discardIfEmpty(empty))
            #expect(await !store.discardIfEmpty(used))

            #expect(!FileManager.default.fileExists(atPath: empty.directoryURL.path))
            #expect(FileManager.default.fileExists(atPath: used.mediaURL.path))
        }
    }

    @Test func savesMetadataBesideTheMedia() async throws {
        try await withStore { store, _ in
            let destination = try await store.prepareDestination(id: UUID(), createdAt: Date())
            let metadata = RecordingMetadata(
                recording: try Recording(title: "Sync", duration: 3),
                mediaFileName: destination.mediaURL.lastPathComponent,
                captureMode: .screen,
                sourceName: "Studio Display",
                hasVideo: true,
                audioSources: [.microphone],
                fileSizeBytes: 10,
                completion: .complete,
                transcriptionRequested: true
            )

            try await store.save(metadata, in: destination)

            let data = try Data(contentsOf: destination.directoryURL.appending(path: "recording.json"))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(RecordingMetadata.self, from: data)
            #expect(decoded.sourceName == "Studio Display")
            #expect(decoded.transcriptionRequested)
        }
    }

    @Test func reportsFreeSpaceForAFolderThatDoesNotExistYet() async throws {
        try await withStore { store, _ in
            let location = await store.currentLocation()

            #expect(location.availableBytes > 0)
            #expect(location.isAccessible)
            #expect(location.displayPath.hasSuffix("Movies/Verbatim"))
        }
    }

    @Test func defaultFolderIsMoviesVerbatim() {
        #expect(FileRecordingStore.defaultFolder().path(percentEncoded: false).hasSuffix("/Movies/Verbatim/"))
    }
}
