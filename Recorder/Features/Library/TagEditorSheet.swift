import SwiftUI

/// Asks for a tag's name and color, for a new tag or an existing one. Return confirms, Escape cancels.
struct TagEditorSheet: View {
    let isNew: Bool
    let save: (String, TagColor) -> Void
    let cancel: () -> Void

    @State private var name: String
    @State private var color: TagColor
    @FocusState private var isFieldFocused: Bool

    init(
        editing tag: RecordingTag?,
        save: @escaping (String, TagColor) -> Void,
        cancel: @escaping () -> Void
    ) {
        isNew = tag == nil
        self.save = save
        self.cancel = cancel
        _name = State(initialValue: tag?.name ?? "")
        _color = State(initialValue: tag?.color ?? .blue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isNew ? "New Tag" : "Edit Tag")
                .font(.system(size: 13, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($isFieldFocused)
            HStack(spacing: 8) {
                ForEach(TagColor.allCases, id: \.self) { candidate in
                    Button {
                        color = candidate
                    } label: {
                        TagDot(color: candidate, size: 18)
                            .padding(3)
                            // The ring marks the chosen color; every color stays filled so it reads as a swatch.
                            .overlay {
                                Circle().strokeBorder(
                                    candidate == color ? VerbatimColor.primaryText : .clear,
                                    lineWidth: 1.5
                                )
                            }
                            // A plain button only reacts where it draws, so without this the middle of a dot is dead.
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(candidate.title)
                    .accessibilityLabel(candidate.title)
                    .accessibilityAddTraits(candidate == color ? [.isSelected] : [])
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .buttonStyle(.verbatim(.secondary, size: .dialog))
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    save(name, color)
                }
                .buttonStyle(.verbatim(.accent, size: .dialog))
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
}
