import Foundation

/// The Settings window's tabs, in toolbar order.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case models
    case storage
    case about

    var id: String {
        rawValue
    }
}

/// A third-party component and its license.
struct ThirdPartyLicense: Identifiable, Sendable {
    let name: String
    let license: String
    /// Where the full text is published.
    let url: URL?

    var id: String {
        name
    }

    /// What the app actually ships: the packages it links and the weights it can download.
    static let shipped = [
        ThirdPartyLicense(
            name: "WhisperKit",
            license: "MIT",
            url: URL(string: "https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.1/LICENSE")
        ),
        ThirdPartyLicense(
            name: "OpenAI Whisper models",
            license: "MIT",
            url: URL(string: "https://github.com/openai/whisper/blob/main/LICENSE")
        ),
        ThirdPartyLicense(
            name: "SQLiteVecKit",
            license: "MIT",
            url: URL(string: "https://github.com/carlosypunto/SQLiteVecKit/blob/0.1.1/LICENSE")
        ),
        ThirdPartyLicense(
            name: "swift-argument-parser",
            license: "Apache 2.0",
            url: URL(string: "https://github.com/apple/swift-argument-parser/blob/1.8.2/LICENSE.txt")
        )
    ]
}

/// The version shown in About, from the app's own bundle.
struct AppMetadata: Equatable, Sendable {
    let version: String
    let build: String
    let sourceCodeURL: URL?

    init(version: String, build: String) {
        self.version = version
        self.build = build
        sourceCodeURL = URL(string: "https://github.com/verbatim-app/verbatim")
    }

    init(infoDictionary: [String: Any]) {
        self.init(
            version: infoDictionary["CFBundleShortVersionString"] as? String ?? "—",
            build: infoDictionary["CFBundleVersion"] as? String ?? "—"
        )
    }
}
