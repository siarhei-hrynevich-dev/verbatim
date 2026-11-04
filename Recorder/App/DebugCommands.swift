#if DEBUG
    import AppKit
    import SwiftUI

    /// Debug-build menu for reviewing the layout-only windows: their design states, the design's accent colors,
    /// and Light or Dark appearance.
    struct DebugCommands: Commands {
        let recorderViewModel: RecorderViewModel
        let libraryViewModel: LibraryViewModel
        let viewerViewModel: ViewerViewModel
        let settingsViewModel: SettingsViewModel
        @Binding var accent: VerbatimAccent?

        @Environment(\.openWindow) private var openWindow
        @Environment(\.openSettings) private var openSettings

        var body: some Commands {
            CommandMenu("Debug") {
                Menu("Recorder State") {
                    Button("Live") {
                        recorderViewModel.endPreview()
                    }
                    ForEach(RecorderPreviewScenario.allCases) { scenario in
                        Button(scenario.title) {
                            recorderViewModel.apply(scenario)
                        }
                    }
                }

                Menu("Library State") {
                    Button("Live") {
                        libraryViewModel.endPreview()
                        openWindow(id: LibraryWindowView.windowID)
                    }
                    ForEach(LibraryPreviewScenario.allCases) { scenario in
                        Button(scenario.title) {
                            libraryViewModel.apply(scenario)
                            openWindow(id: LibraryWindowView.windowID)
                        }
                    }
                }

                Menu("Viewer State") {
                    Button("Live") {
                        viewerViewModel.endPreview()
                        openWindow(id: ViewerWindowView.windowID)
                    }
                    ForEach(ViewerPreviewScenario.allCases) { scenario in
                        Button(scenario.title) {
                            viewerViewModel.apply(scenario)
                            openWindow(id: ViewerWindowView.windowID)
                        }
                    }
                }

                Menu("Settings State") {
                    ForEach(SettingsPreviewScenario.allCases) { scenario in
                        Button(scenario.title) {
                            settingsViewModel.apply(scenario)
                            openSettings()
                        }
                    }
                }

                Divider()

                Picker("Accent Color", selection: $accent) {
                    Text("System").tag(VerbatimAccent?.none)
                    ForEach(VerbatimAccent.allCases) { accent in
                        Text(accent.title).tag(VerbatimAccent?.some(accent))
                    }
                }

                Menu("Appearance") {
                    Button("System") { NSApp.appearance = nil }
                    Button("Light") { NSApp.appearance = NSAppearance(named: .aqua) }
                    Button("Dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
                }
            }
        }
    }
#endif
