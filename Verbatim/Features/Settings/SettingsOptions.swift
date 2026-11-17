import Foundation

/// The Settings window's tabs, in toolbar order.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case models
    case agents
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

    /// The full notices, with every copyright line and license text, in the repository.
    static let noticesURL = URL(
        string: "https://github.com/siarhei-hrynevich/verbatim/blob/main/THIRD_PARTY_NOTICES.md"
    )

    /// What the app actually ships: the packages it links, the code vendored inside them, and the weights it can
    /// download. Keep in step with THIRD_PARTY_NOTICES.md; packages that are only resolved, not built, are left out.
    static let shipped = [
        ThirdPartyLicense(
            name: "WhisperKit",
            license: "MIT",
            url: URL(string: "https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.1/LICENSE")
        ),
        ThirdPartyLicense(
            name: "SQLiteVecKit",
            license: "MIT",
            url: URL(string: "https://github.com/carlosypunto/SQLiteVecKit/blob/0.1.1/LICENSE")
        ),
        ThirdPartyLicense(
            name: "sqlite-vec",
            license: "MIT",
            url: URL(string: "https://github.com/carlosypunto/SQLiteVecKit/blob/0.1.1/Sources/CSQLiteVec/LICENSE-MIT")
        ),
        ThirdPartyLicense(
            name: "MLX Swift",
            license: "MIT",
            url: URL(string: "https://github.com/ml-explore/mlx-swift/blob/0.31.4/LICENSE")
        ),
        ThirdPartyLicense(
            name: "MLX",
            license: "MIT",
            url: URL(string: "https://github.com/ml-explore/mlx/blob/v0.31.1/LICENSE")
        ),
        ThirdPartyLicense(
            name: "MLX C",
            license: "MIT",
            url: URL(string: "https://github.com/ml-explore/mlx-c/blob/v0.6.0/LICENSE")
        ),
        ThirdPartyLicense(
            name: "metal-cpp",
            license: "Apache 2.0",
            url: URL(string: "https://github.com/ml-explore/mlx-swift/blob/0.31.4/Source/Cmlx/metal-cpp/LICENSE.txt")
        ),
        ThirdPartyLicense(
            name: "{fmt}",
            license: "MIT",
            url: URL(string: "https://github.com/ml-explore/mlx-swift/blob/0.31.4/Source/Cmlx/fmt/LICENSE")
        ),
        ThirdPartyLicense(
            name: "JSON for Modern C++",
            license: "MIT",
            url: URL(string: "https://github.com/ml-explore/mlx-swift/blob/0.31.4/Source/Cmlx/json/LICENSE.MIT")
        ),
        ThirdPartyLicense(
            name: "MLX Swift LM",
            license: "MIT",
            url: URL(string: "https://github.com/ml-explore/mlx-swift-lm/blob/3.31.4/LICENSE")
        ),
        ThirdPartyLicense(
            name: "swift-transformers",
            license: "Apache 2.0",
            url: URL(string: "https://github.com/huggingface/swift-transformers/blob/1.4.0/LICENSE")
        ),
        ThirdPartyLicense(
            name: "swift-huggingface",
            license: "Apache 2.0",
            url: URL(string: "https://github.com/huggingface/swift-huggingface/blob/1.0.0/LICENSE")
        ),
        ThirdPartyLicense(
            name: "swift-jinja",
            license: "Apache 2.0",
            url: URL(string: "https://github.com/huggingface/swift-jinja/blob/3.0.0/LICENSE")
        ),
        ThirdPartyLicense(
            name: "swift-collections",
            license: "Apache 2.0",
            url: URL(string: "https://github.com/apple/swift-collections/blob/1.7.5/LICENSE.txt")
        ),
        ThirdPartyLicense(
            name: "swift-crypto",
            license: "Apache 2.0",
            url: URL(string: "https://github.com/apple/swift-crypto/blob/4.5.2/LICENSE.txt")
        ),
        ThirdPartyLicense(
            name: "swift-numerics",
            license: "Apache 2.0",
            url: URL(string: "https://github.com/apple/swift-numerics/blob/1.1.1/LICENSE.txt")
        ),
        ThirdPartyLicense(
            name: "yyjson",
            license: "MIT",
            url: URL(string: "https://github.com/ibireme/yyjson/blob/0.13.0/LICENSE")
        ),
        ThirdPartyLicense(
            name: "EventSource",
            license: "MIT",
            url: URL(string: "https://github.com/mattt/EventSource/blob/1.6.0/LICENSE.md")
        ),
        ThirdPartyLicense(
            name: "Whisper models (Core ML)",
            license: "MIT",
            url: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")
        ),
        ThirdPartyLicense(
            name: "Whisper tokenizers",
            license: "Apache 2.0",
            url: URL(string: "https://huggingface.co/openai/whisper-large-v3")
        ),
        ThirdPartyLicense(
            name: "Qwen3 models",
            license: "Apache 2.0",
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/main/LICENSE")
        ),
        ThirdPartyLicense(
            name: "Multilingual E5 models",
            license: "MIT",
            url: URL(string: "https://huggingface.co/intfloat/multilingual-e5-small")
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
        sourceCodeURL = URL(string: "https://github.com/siarhei-hrynevich/verbatim")
    }

    init(infoDictionary: [String: Any]) {
        self.init(
            version: infoDictionary["CFBundleShortVersionString"] as? String ?? "—",
            build: infoDictionary["CFBundleVersion"] as? String ?? "—"
        )
    }
}
