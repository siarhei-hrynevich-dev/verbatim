import Foundation

/// Library states that can be shown without real storage or processing, matching section “02 Library” of the
/// design.
///
/// Select one at launch with `-LibraryPreviewScenario <rawValue>` (for example in the scheme's arguments), which
/// also opens the Library window, from the Debug menu in Debug builds, or in SwiftUI previews.
enum LibraryPreviewScenario: String, CaseIterable, Identifiable, Sendable {
    case list
    case processing
    case search
    case context
    case confirm
    case empty

    static let launchArgumentKey = "LibraryPreviewScenario"

    /// The query the Search results state shows.
    static let sampleSearchQuery = "recording engine"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .list: "Recordings"
        case .processing: "Processing"
        case .search: "Search Results"
        case .context: "Context Menu"
        case .confirm: "Delete Confirmation"
        case .empty: "Empty"
        }
    }

    /// Reads the scenario from launch arguments, which `UserDefaults` exposes in its argument domain.
    /// Returns `nil` when none, or an unknown one, is given.
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> LibraryPreviewScenario? {
        defaults.string(forKey: launchArgumentKey).flatMap(LibraryPreviewScenario.init(rawValue:))
    }
}
