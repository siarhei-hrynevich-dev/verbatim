import Accelerate
import Foundation

/// The vectors of one embedding space, as one row-major matrix, for exact nearest-neighbor search.
///
/// Exact search reads every vector, as sqlite-vec's `vec0` does too: at 384 values a row, an hour of speech is about
/// 60 rows, and a thousand hours fit in under 100 MB and score in milliseconds with one matrix-vector product.
struct VectorMatrix: Sendable {
    let dimensions: Int
    private(set) var chunkIDs: [Int64] = []
    private var values: [Float] = []

    init(dimensions: Int) {
        self.dimensions = dimensions
    }

    var count: Int {
        chunkIDs.count
    }

    /// Ignores a vector of another length, which cannot belong to this space.
    mutating func append(chunkID: Int64, vector: [Float]) {
        guard vector.count == dimensions else {
            return
        }
        chunkIDs.append(chunkID)
        values.append(contentsOf: vector)
    }

    /// The `limit` rows with the largest dot product with `query`, among those `isAllowed` accepts, best first. For
    /// normalized vectors that is the cosine similarity.
    func nearest(to query: [Float], limit: Int, isAllowed: (Int64) -> Bool) -> [(chunkID: Int64, score: Float)] {
        guard query.count == dimensions, !chunkIDs.isEmpty, limit > 0 else {
            return []
        }
        var scores = [Float](repeating: 0, count: count)
        values.withUnsafeBufferPointer { matrix in
            query.withUnsafeBufferPointer { vector in
                scores.withUnsafeMutableBufferPointer { result in
                    guard let matrix = matrix.baseAddress, let vector = vector.baseAddress,
                        let result = result.baseAddress
                    else {
                        return
                    }
                    vDSP_mmul(matrix, 1, vector, 1, result, 1, vDSP_Length(count), 1, vDSP_Length(dimensions))
                }
            }
        }
        return scores.indices
            .filter { isAllowed(chunkIDs[$0]) }
            .sorted { (scores[$0], chunkIDs[$1]) > (scores[$1], chunkIDs[$0]) }
            .prefix(limit)
            .map { (chunkIDs[$0], scores[$0]) }
    }

    /// Little-endian Float32 values, as the database stores a vector.
    static func blob(from vector: [Float]) -> Data {
        var data = Data(capacity: vector.count * MemoryLayout<UInt32>.size)
        for value in vector {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// `nil` when the blob does not hold whole Float32 values.
    static func vector(from blob: Data) -> [Float]? {
        let size = MemoryLayout<UInt32>.size
        guard blob.count.isMultiple(of: size) else {
            return nil
        }
        return blob.withUnsafeBytes { bytes in
            (0..<(blob.count / size)).map { index in
                let bits = bytes.loadUnaligned(fromByteOffset: index * size, as: UInt32.self)
                return Float(bitPattern: UInt32(littleEndian: bits))
            }
        }
    }
}
