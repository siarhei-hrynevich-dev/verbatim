import Foundation

extension SummaryLanguage {
    /// The languages to choose from, by name in the user's language.
    static let choices: [SummaryLanguage] =
        supportedCodes
        .compactMap(SummaryLanguage.init(code:))
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

    var title: String {
        TranscriptionLanguage.displayName(forCode: code)
    }
}
