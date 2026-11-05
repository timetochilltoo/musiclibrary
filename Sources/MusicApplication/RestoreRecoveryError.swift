import Foundation

public struct RestoreRecoveryError: LocalizedError, Sendable {
    public enum Outcome: Equatable, Sendable { case restoredPreviousCatalogue, recoveryIncomplete }
    public let outcome: Outcome
    public let restoreFailure: String
    public let recoveryFailure: String?
    public let recoveryURL: URL

    public var errorDescription: String? {
        switch outcome {
        case .restoredPreviousCatalogue:
            "Restore failed. The previous catalogue was restored and reopened.\n\(restoreFailure)"
        case .recoveryIncomplete:
            "Restore failed and automatic recovery is incomplete. Do not retry restore until the recovery data has been reviewed.\nRecovery data: \(recoveryURL.path)\nRestore: \(restoreFailure)\nRecovery: \(recoveryFailure ?? "Unknown failure")"
        }
    }
}
