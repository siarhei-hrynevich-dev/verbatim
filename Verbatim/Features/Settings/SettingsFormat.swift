import Foundation

/// Text formats for Settings values.
enum SettingsFormat {
    /// `75 MB` below a gigabyte, otherwise one decimal: `1.5 GB`, `40.5 GB`. Decimal units, as Finder shows them.
    static func size(bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_000_000
        if megabytes >= 1000 {
            let gigabytes = (megabytes / 1000).formatted(.number.precision(.fractionLength(1)))
            return "\(gigabytes) GB"
        }
        return "\(Int(megabytes.rounded())) MB"
    }

    /// Free space as Finder shows it, such as `214 GB` or `1.6 TB`.
    static func freeSpace(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// `570 MB of 1.5 GB`.
    static func downloadCaption(_ progress: ModelDownloadProgress) -> String {
        "\(size(bytes: min(progress.completedBytes, progress.totalBytes))) of \(size(bytes: progress.totalBytes))"
    }
}
