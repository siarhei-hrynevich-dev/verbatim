import AVFoundation
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Small JPEG stills of video recordings, cached in memory and on disk, so scrolling never generates one twice.
///
/// Generation decodes a single frame near the start and runs one at a time, however many rows appear at once.
actor VideoThumbnailProvider: RecordingThumbnailProvider {
    private let cacheFolder: URL
    private let memoryCache = NSCache<NSUUID, NSData>()
    /// Media that gave no image; asking again is pointless until the recording's file changes.
    private var unavailable: Set<UUID> = []
    private var running: [UUID: Task<Data?, Never>] = [:]
    private var lastGeneration: Task<Data?, Never>?

    init(cacheFolder: URL) {
        self.cacheFolder = cacheFolder
        memoryCache.countLimit = Self.memoryCacheCount
    }

    static func defaultCacheFolder() -> URL {
        URL.cachesDirectory.appending(path: "Verbatim/Thumbnails", directoryHint: .isDirectory)
    }

    func thumbnail(for recording: LibraryRecording) async -> Data? {
        let id = recording.id
        guard recording.captureMode.capturesVideo, !unavailable.contains(id) else {
            return nil
        }
        if let cached = memoryCache.object(forKey: id as NSUUID) {
            return cached as Data
        }
        if let stored = readFromDisk(id) {
            memoryCache.setObject(stored as NSData, forKey: id as NSUUID)
            return stored
        }
        if let task = running[id] {
            return await task.value
        }
        let previous = lastGeneration
        let task = Task {
            _ = await previous?.value
            return await generateAndStore(recording)
        }
        running[id] = task
        lastGeneration = task
        return await task.value
    }

    func discardThumbnail(for id: UUID) {
        unavailable.remove(id)
        memoryCache.removeObject(forKey: id as NSUUID)
        do {
            try FileManager.default.removeItem(at: fileURL(for: id))
        } catch CocoaError.fileNoSuchFile {
            // Nothing was cached for this recording.
        } catch {
            Self.logger.error("Could not remove a cached thumbnail: \(String(describing: error))")
        }
    }

    private func generateAndStore(_ recording: LibraryRecording) async -> Data? {
        defer { running[recording.id] = nil }
        let access = MediaFileAccess.open(recording.media)
        defer { access.close() }
        // A file that is only temporarily out of reach may come back, so this is not remembered as unavailable.
        guard access.availability == .available else {
            return nil
        }
        guard let image = await Self.image(from: access.media.url), let data = Self.jpegData(from: image) else {
            unavailable.insert(recording.id)
            return nil
        }
        memoryCache.setObject(data as NSData, forKey: recording.id as NSUUID)
        writeToDisk(data, id: recording.id)
        return data
    }

    private nonisolated static func image(from url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        // Any nearby keyframe will do; exact seeking would decode more than the thumbnail is worth.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        do {
            return try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        } catch {
            logger.notice("Could not generate a thumbnail: \(String(describing: error))")
            return nil
        }
    }

    private static func jpegData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private func readFromDisk(_ id: UUID) -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: id))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            Self.logger.notice("Could not read a cached thumbnail: \(String(describing: error))")
            return nil
        }
    }

    /// The thumbnail is still shown from memory if it cannot be stored, and generated again next launch.
    private func writeToDisk(_ data: Data, id: UUID) {
        do {
            try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: id), options: .atomic)
        } catch {
            Self.logger.notice("Could not cache a thumbnail: \(String(describing: error))")
        }
    }

    private func fileURL(for id: UUID) -> URL {
        cacheFolder.appending(path: "\(id.uuidString).jpg", directoryHint: .notDirectory)
    }

    /// Twice the 52 × 32 pt thumbnail, for Retina displays.
    private static let maximumSize = CGSize(width: 104, height: 64)
    private static let memoryCacheCount = 200
    private static let logger = Logger(category: "Library")
}
