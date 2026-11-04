import Foundation
import Testing

@testable import Recorder

struct RecordingTests {
    @Test func createsMetadata() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 0)
        let recording = try Recording(id: id, title: "  Demo  ", createdAt: date, duration: 12)
        #expect(recording.id == id)
        #expect(recording.title == "Demo")
        #expect(recording.createdAt == date)
        #expect(recording.duration == 12)
        #expect(recording.processingStatus == .pending)
    }

    @Test(arguments: Recording.ProcessingStatus.allCases)
    func preservesProcessingStatus(status: Recording.ProcessingStatus) throws {
        let recording = try Recording(title: "Demo", duration: 0, processingStatus: status)
        let data = try JSONEncoder().encode(recording)
        #expect(try JSONDecoder().decode(Recording.self, from: data) == recording)
    }

    @Test func rejectsBlankTitle() {
        #expect(throws: Recording.ValidationError.emptyTitle) {
            try Recording(title: " \n ", duration: 0)
        }
    }

    @Test(arguments: [-1.0, Double.infinity, -Double.infinity, Double.nan])
    func rejectsInvalidDuration(duration: Double) {
        #expect(throws: Recording.ValidationError.invalidDuration) {
            try Recording(title: "Demo", duration: duration)
        }
    }
}
