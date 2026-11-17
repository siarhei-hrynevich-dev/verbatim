import SwiftUI

/// Asks for a recording's new name. Only the title changes; its files keep their names. Return confirms, Escape
/// cancels.
struct RenameRecordingSheet: View {
    let rename: (String) -> Void
    let cancel: () -> Void

    @State private var title: String
    @FocusState private var isFieldFocused: Bool

    init(currentTitle: String, rename: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.rename = rename
        self.cancel = cancel
        _title = State(initialValue: currentTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename Recording")
                .font(.system(size: 13, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            TextField("Name", text: $title)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($isFieldFocused)
            Text("The file on disk keeps its name.")
                .font(.system(size: 11))
                .foregroundStyle(VerbatimColor.secondaryText)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .buttonStyle(.verbatim(.secondary, size: .dialog))
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    rename(title)
                }
                .buttonStyle(.verbatim(.accent, size: .dialog))
                .keyboardShortcut(.defaultAction)
                .disabled(isTitleBlank)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 360)
        .foregroundStyle(VerbatimColor.primaryText)
        .focusEffectDisabled()
        .presentationBackground(VerbatimColor.windowBackground)
        .onAppear { isFieldFocused = true }
    }

    private var isTitleBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
