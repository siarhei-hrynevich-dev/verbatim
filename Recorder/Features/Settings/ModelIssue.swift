import Foundation

/// A model problem as the user reads it: what happened, and what to do about it.
struct ModelIssue: Identifiable, Equatable {
    let title: String
    let message: String

    var id: String {
        title + message
    }

    init(_ error: any Error) {
        guard let error = error as? ModelManagementError else {
            self.init(title: String(localized: "Something went wrong"), message: error.localizedDescription)
            return
        }
        switch error {
        case .noNetwork, .downloadFailed, .insufficientDiskSpace, .modelUnavailable, .unsupportedOnThisMac:
            self = Self.download(error)
        case .verificationFailed, .interruptedDownload, .damagedInstallation:
            self = Self.installation(error)
        case .storageAccessDenied, .removalFailed, .modelInUse:
            self = Self.files(error)
        case .modelNotInstalled, .noModelSelected, .selectedModelUnavailable:
            self = Self.selection(error)
        }
    }

    private init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    private static func download(_ error: ModelManagementError) -> ModelIssue {
        switch error {
        case .noNetwork:
            ModelIssue(
                title: String(localized: "No internet connection"),
                message: String(
                    localized: "Connect to the internet and try again. Anything already downloaded is kept."
                )
            )
        case .insufficientDiskSpace(let required, _) where required > 0:
            ModelIssue(
                title: String(localized: "Not enough disk space"),
                message: String(
                    localized:
                        "This download needs \(SettingsFormat.size(bytes: required)) free. Free up space and try again."
                )
            )
        case .insufficientDiskSpace:
            ModelIssue(
                title: String(localized: "Not enough disk space"),
                message: String(localized: "The disk filled up during the download. Free up space and try again.")
            )
        case .modelUnavailable:
            ModelIssue(
                title: String(localized: "This model is no longer available"),
                message: String(
                    localized: "Its repository doesn’t offer it right now. Try later, or choose another model."
                )
            )
        case .unsupportedOnThisMac:
            ModelIssue(
                title: String(localized: "This model isn’t supported on this Mac"),
                message: String(localized: "Choose another model.")
            )
        case .downloadFailed(let detail):
            ModelIssue(
                title: String(localized: "The download failed"),
                message: String(localized: "\(detail) Anything already downloaded is kept, so trying again continues.")
            )
        default:
            ModelIssue(title: String(localized: "The download failed"), message: "")
        }
    }

    private static func installation(_ error: ModelManagementError) -> ModelIssue {
        switch error {
        case .interruptedDownload:
            ModelIssue(
                title: String(localized: "The download didn’t finish"),
                message: String(localized: "Trying again continues from where it stopped.")
            )
        case .damagedInstallation:
            ModelIssue(
                title: String(localized: "This model’s files have changed"),
                message: String(
                    localized: "Some are missing or modified, so it can’t be used. Retry to download it again."
                )
            )
        default:
            ModelIssue(
                title: String(localized: "The downloaded files failed verification"),
                message: String(localized: "They were discarded, because they can’t be trusted. Try downloading again.")
            )
        }
    }

    private static func files(_ error: ModelManagementError) -> ModelIssue {
        switch error {
        case .storageAccessDenied:
            ModelIssue(
                title: String(localized: "Verbatim can’t access model storage"),
                message: String(localized: "Check the permissions of the model storage folder, then try again.")
            )
        case .removalFailed(let detail):
            ModelIssue(
                title: String(localized: "The model couldn’t be removed"),
                message: String(localized: "\(detail) Recordings and transcripts weren’t touched.")
            )
        default:
            ModelIssue(
                title: String(localized: "This model is in use"),
                message: String(localized: "Wait until transcription finishes, then remove it.")
            )
        }
    }

    private static func selection(_ error: ModelManagementError) -> ModelIssue {
        switch error {
        case .modelNotInstalled:
            ModelIssue(
                title: String(localized: "This model isn’t installed"),
                message: String(localized: "Download it first.")
            )
        case .noModelSelected:
            ModelIssue(
                title: String(localized: "No model selected"),
                message: String(localized: "Select an installed model.")
            )
        default:
            ModelIssue(
                title: String(localized: "The selected model isn’t available"),
                message: String(localized: "Download it again, or select another installed model.")
            )
        }
    }
}
