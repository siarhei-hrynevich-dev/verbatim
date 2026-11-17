import Foundation
import Testing

@testable import Verbatim

struct UserDefaultsSettingsRepositoryTests {
    private func withRepository(
        _ body: (UserDefaultsSettingsRepository, UserDefaults) throws -> Void
    ) throws {
        let suiteName = "UserDefaultsSettingsRepositoryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(UserDefaultsSettingsRepository(defaults: defaults), defaults)
    }

    @Test func unsetSettingsUseTheDefaults() throws {
        try withRepository { repository, _ in
            #expect(repository.loadSettings() == AppSettings())
            #expect(repository.loadSelectedModelID() == nil)
        }
    }

    @Test func roundTripsEverySetting() throws {
        try withRepository { repository, _ in
            let settings = AppSettings(
                showsMenuBarIcon: false,
                opensRecorderOnDockClick: false,
                closeBehavior: .quit
            )

            repository.saveSettings(settings)

            #expect(repository.loadSettings() == settings)
        }
    }

    @Test func selectedModelRoundTripsAndClears() throws {
        try withRepository { repository, _ in
            repository.saveSelectedModelID("openai_whisper-tiny")
            #expect(repository.loadSelectedModelID() == "openai_whisper-tiny")

            repository.saveSelectedModelID(nil)
            #expect(repository.loadSelectedModelID() == nil)
        }
    }

    @Test func invalidStoredValuesFallBackToDefaults() throws {
        try withRepository { repository, defaults in
            defaults.set("explode", forKey: "settings.closeBehavior")

            #expect(repository.loadSettings().closeBehavior == .keepRunning)
        }
    }
}

struct JSONModelRegistryStoreTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "JSONModelRegistryStoreTests-\(UUID().uuidString)/registry.json")
    }

    @Test func missingFileIsAnEmptyRegistry() async throws {
        let store = JSONModelRegistryStore(fileURL: temporaryURL())

        #expect(try await store.load() == ModelRegistry())
    }

    @Test func roundTripsThroughAFileAndCreatesItsFolder() async throws {
        let store = JSONModelRegistryStore(fileURL: temporaryURL())
        let registry = ModelRegistry(
            installations: ["tiny": ModelFixtures.installation()],
            artifactSizes: ["tiny": 42]
        )

        try await store.save(registry)

        #expect(try await store.load() == registry)
    }

    @Test func corruptedFileCountsAsEmptyRatherThanFailing() async throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)

        let store = JSONModelRegistryStore(fileURL: url)

        #expect(try await store.load() == ModelRegistry())
    }
}

@MainActor
struct AppPreferencesTests {
    @Test func changesSaveAtOnceAndAreRestored() {
        let repository = InMemorySettingsRepository()
        let preferences = AppPreferences(repository: repository)

        preferences.update { $0.showsMenuBarIcon = false }

        #expect(repository.loadSettings().showsMenuBarIcon == false)
        #expect(AppPreferences(repository: repository).settings.showsMenuBarIcon == false)
    }
}

struct AppMetadataTests {
    @Test func readsVersionAndBuildFromTheBundle() {
        let metadata = AppMetadata(infoDictionary: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "7"])

        #expect(metadata.version == "0.1.0")
        #expect(metadata.build == "7")
    }

    @Test func missingValuesDoNotInventAVersion() {
        let metadata = AppMetadata(infoDictionary: [:])

        #expect(metadata.version == "—")
        #expect(metadata.build == "—")
    }
}
