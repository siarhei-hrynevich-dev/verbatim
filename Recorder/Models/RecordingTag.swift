import Foundation

/// The colors a tag can have. The raw value is what the database stores, so it must never change.
enum TagColor: String, CaseIterable, Hashable, Sendable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case grey
}

/// A label the user can put on recordings, like a Finder tag: a name and a color. Recordings refer to a tag by its
/// identifier, so renaming or recoloring one changes it everywhere.
struct RecordingTag: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var color: TagColor

    static let nameLengthLimit = 40

    /// The name without surrounding whitespace. Throws `LibraryError.invalidTagName` when nothing or too much is left.
    static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= nameLengthLimit else {
            throw LibraryError.invalidTagName
        }
        return trimmed
    }

    /// The tags a new library starts with. The migration that creates the `tags` table inserts the same ones, and a
    /// test keeps the two in step.
    static let defaults = [
        RecordingTag(id: defaultID(1), name: "work", color: .blue),
        RecordingTag(id: defaultID(2), name: "personal", color: .green)
    ]

    /// `6F1D2A40-0000-4000-8000-00000000000<n>`, as the migration writes it.
    private static func defaultID(_ number: UInt8) -> UUID {
        UUID(uuid: (0x6F, 0x1D, 0x2A, 0x40, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, number))
    }
}
