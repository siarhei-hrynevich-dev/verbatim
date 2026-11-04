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

    /// A newly finished recording. Its title is generated, and its duration comes from finished media or a running
    /// clock, so neither can violate the invariants of the validating initializer; a nonsensical duration reads as 0.
    init(id: UUID, createdAt: Date, validatedMediaDuration: TimeInterval, processingStatus: ProcessingStatus) {
        self.id = id
        title = RecordingMetadata.defaultTitle(createdAt: createdAt)
        self.createdAt = createdAt
        duration = validatedMediaDuration.isFinite ? max(validatedMediaDuration, 0) : 0
        self.processingStatus = processingStatus
    }
}
