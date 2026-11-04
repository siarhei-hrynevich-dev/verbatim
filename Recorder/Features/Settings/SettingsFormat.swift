import Foundation

/// Text formats for Settings values.
enum SettingsFormat {
    /// `75 MB` below a gigabyte, otherwise one decimal: `1.5 GB`, `40.5 GB`.
    static func size(megabytes: Double) -> String {
        if megabytes >= 1000 {
            let gigabytes = (megabytes / 1000).formatted(.number.precision(.fractionLength(1)))
            return "\(gigabytes) GB"
        }
        return "\(Int(megabytes.rounded())) MB"
    }

    static func size(megabytes: Int) -> String {
        size(megabytes: Double(megabytes))
    }

    /// Free space as Finder shows it, such as `214 GB` or `1.6 TB`.
    static func freeSpace(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// `570 MB of 1.5 GB · less than a minute left`.
    static func downloadCaption(progress: Double, sizeMegabytes: Int, secondsLeft: Int) -> String {
        let done = size(megabytes: progress * Double(sizeMegabytes))
        let total = size(megabytes: sizeMegabytes)
        let remaining =
            secondsLeft < 60
            ? String(localized: "less than a minute left")
            : String(localized: "about \(Int((Double(secondsLeft) / 60).rounded())) min left")
        return "\(done) of \(total) · \(remaining)"
    }
}
