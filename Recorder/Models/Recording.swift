import Foundation

/// Metadata only; media files and processing jobs will be persisted separately.
struct Recording: Identifiable, Codable, Equatable, Sendable {
    enum ProcessingStatus: String, Codable, CaseIterable, Sendable {
        case pending
        case transcribing
        case indexing
        case ready
        case failed
    }

    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidDuration
    }

    let id: UUID
    let title: String
    let createdAt: Date
    let duration: TimeInterval
    var processingStatus: ProcessingStatus

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval,
        processingStatus: ProcessingStatus = .pending
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ValidationError.emptyTitle
        }
        guard duration.isFinite, duration >= 0 else {
            throw ValidationError.invalidDuration
        }
        self.id = id
        self.title = trimmedTitle
        self.createdAt = createdAt
        self.duration = duration
        self.processingStatus = processingStatus
    }
}
