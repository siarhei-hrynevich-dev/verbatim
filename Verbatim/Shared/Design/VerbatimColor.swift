import SwiftUI

/// Semantic colors of the Verbatim design. Each token resolves light and dark values from the asset catalog,
/// so views follow the system appearance automatically. Selection, switches and links use the system accent color.
enum VerbatimColor {
    static let windowBackground = Color("WindowBackground")
    /// The main content area of a document-style window, such as the Library list.
    static let contentBackground = Color("ContentBackground")
    static let sidebarBackground = Color("SidebarBackground")
    static let menuBackground = Color("MenuBackground")
    /// The outer hairline of floating surfaces such as menus.
    static let edge = Color("Edge")
    /// The Viewer's transcript panel.
    static let transcriptBackground = Color("TranscriptBackground")
    static let groupBackground = Color("GroupBackground")
    static let controlBackground = Color("ControlBackground")
    static let primaryText = Color("PrimaryText")
    static let secondaryText = Color("SecondaryText")
    static let tertiaryText = Color("TertiaryText")
    static let separator = Color("Separator")
    static let fill = Color("Fill")
    static let selectedSegment = Color("SelectedSegment")
    static let switchOff = Color("SwitchOff")
    static let meterOff = Color("MeterOff")
    static let thumbnail = Color("Thumbnail")
    static let thumbnailBar = Color("ThumbnailBar")
    static let thumbnailWindow = Color("ThumbnailWindow")
    static let thumbnailWindowAlternate = Color("ThumbnailWindowAlternate")

    /// Marks recording, the record action, and destructive or failed states.
    static let red = Color("Red")
    static let orange = Color("Orange")
    static let green = Color("Green")
    static let yellow = Color("Yellow")
    static let pink = Color("Pink")
    static let purple = Color("Purple")
    static let accent = Color.accentColor
}
