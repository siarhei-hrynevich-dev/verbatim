import AppKit
import SwiftUI

/// The accent colors of the design's accent tweak, each with its light and dark value.
///
/// Windows follow the system accent color by default. An explicit accent overrides it for a window, so the design
/// can be reviewed with each accent in previews and Debug builds. Select one at launch with
/// `-VerbatimAccent <rawValue>`.
enum VerbatimAccent: String, CaseIterable, Identifiable, Sendable {
    case blue
    case indigo
    case teal
    case graphite

    static let launchArgumentKey = "VerbatimAccent"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .teal: "Teal"
        case .graphite: "Graphite"
        }
    }

    var color: Color {
        let (light, dark) = hexValues
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            }
        )
    }

    private var hexValues: (light: UInt32, dark: UInt32) {
        switch self {
        case .blue: (0x007AFF, 0x0A84FF)
        case .indigo: (0x5856D6, 0x5E5CE6)
        case .teal: (0x0A8A9E, 0x40C8E0)
        case .graphite: (0x6E6E73, 0x98989D)
        }
    }

    /// Reads the accent from launch arguments; `nil` keeps the system accent.
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> VerbatimAccent? {
        defaults.string(forKey: launchArgumentKey).flatMap(VerbatimAccent.init(rawValue:))
    }
}

extension View {
    /// Overrides the accent used by `VerbatimColor.accent` and native controls; `nil` keeps the system accent.
    ///
    /// `tint(_:)` alone does not change `Color.accentColor` on macOS, so both modifiers are applied.
    func verbatimAccent(_ accent: VerbatimAccent?) -> some View {
        accentColor(accent?.color).tint(accent?.color)
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
