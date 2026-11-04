import SQLiteVecStore
import Testing
import WhisperKit

struct DependencySmokeTests {
    @Test func whisperOptionsAreAvailableWithoutLoadingModels() {
        let options = DecodingOptions()
        #expect(options.temperature == 0)
    }

    @Test func sqliteDistanceMetricIsAvailableWithoutOpeningDatabase() {
        #expect(DistanceMetric.cosine.rawValue == "cosine")
        #expect(DistanceMetric.allCases.contains(.l2))
    }
}
