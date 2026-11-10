import Foundation

/// The language summaries are written in, chosen once in Settings. It does not follow the transcript: a recording in
/// any language, or in several, is summarized in this one.
struct SummaryLanguage: Hashable, Sendable {
    /// An ISO 639-1 code, such as `ru`.
    let code: String

    /// `nil` for a code that is not offered, as one stored by another version may be.
    init?(code: String) {
        guard Self.supportedCodes.contains(code) else {
            return nil
        }
        self.code = code
    }

    /// The first of the user's preferred languages that is offered, otherwise English.
    static func preferred(from preferredLanguages: [String]) -> SummaryLanguage {
        let codes = preferredLanguages.compactMap { Locale.Language(identifier: $0).languageCode?.identifier }
        if let language = codes.lazy.compactMap(SummaryLanguage.init(code:)).first {
            return language
        }
        return english
    }

    static let english = SummaryLanguage(uncheckedCode: "en")

    /// Languages the catalog's models write well; Qwen3 is trained on many more, but these are the common ones.
    static let supportedCodes: Set<String> = [
        "ar", "be", "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "he", "hi", "hr", "hu", "id", "it",
        "ja", "kk", "ko", "lt", "lv", "nl", "no", "pl", "pt", "ro", "ru", "sk", "sl", "sr", "sv", "th", "tr", "uk",
        "uz", "vi", "zh"
    ]

    private init(uncheckedCode: String) {
        code = uncheckedCode
    }
}
