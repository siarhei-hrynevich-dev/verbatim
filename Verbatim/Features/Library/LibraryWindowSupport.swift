import SwiftUI

/// Navigation to other windows, which the Library hands to the app, and design-review actions with no real
/// implementation yet. Every action defaults to doing nothing.
struct LibraryWindowActions {
    /// Opens a recording, optionally at a transcript position in seconds.
    var openRecording: (LibraryItem.ID, TimeInterval?) -> Void = { _, _ in }
    var openTranscript: (LibraryItem.ID) -> Void = { _ in }
    var newRecording: () -> Void = {}
    var openSettings: () -> Void = {}
    var addExistingFiles: () -> Void = {}
    var pauseProcessing: () -> Void = {}
}

/// Fixed metrics of the Library window.
enum LibraryLayout {
    static let windowWidth: CGFloat = 1000
    static let windowHeight: CGFloat = 700
    static let sidebarWidth: CGFloat = 220
    static let minimumDetailWidth: CGFloat = 640
    /// The undo toast floats 46 pt above the bottom of the window.
    static let toastBottomOffset: CGFloat = 46
    static let contextMenuLeading: CGFloat = 236
    static let contextMenuRowOffset: CGFloat = 30
    static let contextMenuFlippedRowOffset: CGFloat = 14
    static let contextMenuMargin: CGFloat = 8
}

extension RecordingSortOrder {
    var title: String {
        switch self {
        case .newestFirst: String(localized: "Newest First")
        case .oldestFirst: String(localized: "Oldest First")
        case .name: String(localized: "Name")
        case .duration: String(localized: "Duration")
        }
    }
}

extension LibraryFilter {
    var title: String {
        switch self {
        case .all: String(localized: "All Recordings")
        case .recent: String(localized: "Recent")
        case .processing: String(localized: "Processing")
        case .screen: String(localized: "Screen Recordings")
        case .audio: String(localized: "Audio Recordings")
        case .tagged: String(localized: "Tag")
        }
    }

    var icon: VerbatimIcon {
        switch self {
        case .all: .list
        case .recent: .clock
        case .processing: .loader
        case .screen: .monitor
        case .audio: .audio
        case .tagged: .list
        }
    }
}

extension TagColor {
    var title: String {
        switch self {
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .grey: String(localized: "Grey")
        }
    }

    var swiftUI: Color {
        switch self {
        case .red: VerbatimColor.red
        case .orange: VerbatimColor.orange
        case .yellow: VerbatimColor.yellow
        case .green: VerbatimColor.green
        case .blue: Color(nsColor: .systemBlue)
        case .purple: VerbatimColor.purple
        case .grey: Color(nsColor: .systemGray)
        }
    }
}
