import Foundation

/// Viewer states that can be shown without real media or transcription, matching section “03 Viewer” of the
/// design.
///
/// Select one at launch with `-ViewerPreviewScenario <rawValue>`, which also opens the Viewer window, from the
/// Debug menu in Debug builds, or in SwiftUI previews.
enum ViewerPreviewScenario: String, CaseIterable, Identifiable, Sendable {
    case video
    case search
    case audio
    case processing
    case failed
    case unprocessed

    static let launchArgumentKey = "ViewerPreviewScenario"

    /// The query the transcript search state shows.
    static let sampleSearchQuery = "recording"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .video: "Video with Transcript"
        case .search: "Search Within Transcript"
        case .audio: "Audio-Only Recording"
        case .processing: "Transcript Processing"
        case .failed: "Transcription Failed"
        case .unprocessed: "Not Processed"
        }
    }

    /// The Library recording each state shows.
    var recordingTitle: String {
        switch self {
        case .video, .search: "Architecture Review"
        case .audio: "1:1 with Maya"
        case .processing: "Weekly Team Sync"
        case .failed: "Design Critique"
        case .unprocessed: "Onboarding Walkthrough"
        }
    }

    /// Where playback stands when the state opens.
    var startPosition: TimeInterval {
        switch self {
        case .video: 262
        case .search: 260
        case .audio: 80
        case .processing, .failed, .unprocessed: 0
        }
    }

    /// Reads the scenario from launch arguments; `nil` when none, or an unknown one, is given.
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> ViewerPreviewScenario? {
        defaults.string(forKey: launchArgumentKey).flatMap(ViewerPreviewScenario.init(rawValue:))
    }
}
