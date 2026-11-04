import Foundation

/// What a recording captures.
enum CaptureMode: String, CaseIterable, Sendable {
    case screen
    case window
    case audioOnly

    var capturesVideo: Bool {
        self != .audioOnly
    }
}

enum VideoQuality: String, CaseIterable, Sendable {
    case hd720 = "720p"
    case hd1080 = "1080p"
    case native = "Native"
}

enum FrameRate: Int, CaseIterable, Sendable {
    case fps30 = 30
    case fps60 = 60
}

/// A display that can be captured.
struct CaptureDisplay: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
}

/// An application window that can be captured.
struct CaptureWindow: Identifiable, Hashable, Sendable {
    let id: String
    let appName: String
    let title: String
}
