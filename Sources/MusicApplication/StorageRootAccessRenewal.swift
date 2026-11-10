import Foundation
import MusicDomain
import MusicPersistence

enum StorageRootAccessRenewal {
    static func validatePath(_ url: URL, for root: StorageRoot) throws {
        guard url.isFileURL,
              url.standardizedFileURL.path == URL(fileURLWithPath: root.lastKnownPath).standardizedFileURL.path else {
            throw DatabaseError.invalidOperation("Choose the registered folder at \(root.lastKnownPath). Renew Access cannot relocate a music folder.")
        }
    }

    static func validateVolume(_ identifier: String?, for root: StorageRoot) throws {
        if let expected = root.volumeIdentifier, identifier != expected {
            throw DatabaseError.invalidOperation("The selected folder's volume could not be matched to the registered volume. Its access permission was left unchanged.")
        }
    }
}
