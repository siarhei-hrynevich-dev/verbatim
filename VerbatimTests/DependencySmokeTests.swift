import SQLiteVecStore
import Testing
import WhisperKit

@testable import Verbatim

struct DependencySmokeTests {
    @Test func whisperOptionsAreAvailableWithoutLoadingModels() {
        let options = DecodingOptions()
        #expect(options.temperature == 0)
    }

    @Test func sqliteDistanceMetricIsAvailableWithoutOpeningDatabase() {
        #expect(DistanceMetric.cosine.rawValue == "cosine")
        #expect(DistanceMetric.allCases.contains(.l2))
    }

    @Test func theLanguagesOfferedAreTheOnesWhisperKitKnows() {
        #expect(Set(TranscriptionLanguage.supportedCodes) == Set(Constants.languages.values))
    }
}
