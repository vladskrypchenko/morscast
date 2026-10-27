import Foundation

enum UpdateFailure: LocalizedError, Equatable {
    case downloadFailed(String)
    case extractFailed(String)
    case noAppInArchive
    case quarantined
    case bundleMismatch
    case identityMismatch
    case versionMismatch(expected: String, found: String)
    case replaceFailed(String)
    case translocated

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let detail):
            return String(localized: "The download did not finish. \(detail)")
        case .extractFailed(let detail):
            return String(localized: "The downloaded archive could not be expanded. \(detail)")
        case .noAppInArchive:
            return String(localized: "The downloaded archive does not contain Tinycast.")
        case .quarantined:
            return String(
                localized: "macOS quarantined the downloaded app and Tinycast could not clear the flag.")
        case .bundleMismatch:
            return String(localized: "The downloaded app is not this build of Tinycast.")
        case .identityMismatch:
            return String(
                localized: "The downloaded app is not signed by the identity this copy was signed with.")
        case .versionMismatch(let expected, let found):
            return String(localized: "The downloaded app is version \(found), not \(expected).")
        case .replaceFailed(let detail):
            return String(localized: "Tinycast could not be replaced. \(detail)")
        case .translocated:
            return String(localized: "\(Bundle.main.appDisplayName) is running from a read-only copy macOS made.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .identityMismatch, .bundleMismatch, .versionMismatch:
            return String(
                localized: """
                    Nothing was installed. Download the release from GitHub instead, so you can \
                    check it yourself.
                    """)
        case .replaceFailed:
            return String(
                localized: """
                    Nothing was installed. This usually means /Applications is not writable by \
                    your account.
                    """)
        case .quarantined:
            return String(localized: "Nothing was installed.")
        case .translocated:
            return String(
                localized: """
                    Nothing was installed. Quit \(Bundle.main.appDisplayName), drag it into the \
                    Applications folder in Finder, open it from there and update again.
                    """)
        default:
            return nil
        }
    }
}
