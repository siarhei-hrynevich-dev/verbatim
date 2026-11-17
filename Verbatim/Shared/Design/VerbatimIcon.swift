import SwiftUI

/// Stroke icons of the Verbatim design, stored as template SVGs in the asset catalog.
enum VerbatimIcon: String {
    case alert
    case audio
    case check
    case chevronDown = "chevd"
    case chevronLeft = "chevl"
    case chevronRight = "chevr"
    case chevronUp = "chevu"
    case circle
    case clock
    case code
    case copy
    case download
    case drive
    case export
    case externalLink = "ext"
    case file
    case folder
    case gear
    case info
    case list
    case loader
    case lock
    case maximize = "max"
    case microphone = "mic"
    case microphoneOff = "micoff"
    case missingFile = "missing"
    case monitor
    case more
    case pause
    case play
    case record = "rec"
    case retry
    case search
    case shield
    case sort
    case sparkles
    case trash
    case upDown = "updown"
    case volume = "vol"
    case window
    case xCircle = "xcircle"

    var image: Image {
        Image("Icon-\(rawValue)")
    }
}

/// Renders a design icon at a square point size, tinted with the current foreground style.
/// Icons are decorative; the surrounding control provides the accessible label.
struct IconView: View {
    let icon: VerbatimIcon
    let size: CGFloat

    init(_ icon: VerbatimIcon, size: CGFloat) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        icon.image
            .resizable()
            .renderingMode(.template)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
