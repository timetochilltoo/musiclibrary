import Foundation
import MusicDomain

/// Preflight only: no file reads and no verified/missing evidence is produced here.
public struct FolderRecoveryReferencePlan: Equatable, Sendable {
    public enum Eligibility: Equatable, Sendable {
        case readyToVerify
        case unverified
        case unsafePath
        case conflictingHashes
    }

    public struct Group: Equatable, Sendable {
        public let relativePath: String
        public let references: [FolderRecoveryReference]
        public let eligibility: Eligibility
        public let expectedContentHash: String?
    }

    public let manifest: FolderRecoveryManifest
    public let groups: [Group]

    public init(manifest: FolderRecoveryManifest) {
        self.manifest = manifest
        let byPath = Dictionary(grouping: manifest.references, by: \.relativePath)
        self.groups = byPath.keys.sorted().map { path in
            let references = byPath[path, default: []].sorted { $0.assetID.description < $1.assetID.description }
            let validHashes = references.compactMap { Self.fullHash($0.expectedContentHash) }
            let hashes = Set(validHashes)
            let eligibility: Eligibility
            if Self.isUnsafe(path) { eligibility = .unsafePath }
            else if hashes.count > 1 { eligibility = .conflictingHashes }
            else if validHashes.count != references.count { eligibility = .unverified }
            else { eligibility = .readyToVerify }
            return Group(relativePath: path, references: references, eligibility: eligibility,
                         expectedContentHash: eligibility == .readyToVerify ? hashes.first : nil)
        }
    }

    private static func fullHash(_ value: String?) -> String? {
        guard let value, value.utf8.count == 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return value.lowercased()
    }

    private static func isUnsafe(_ path: String) -> Bool {
        guard !RegisteredPathSecurity.isUnsafeRelativeReference(path), !path.contains("\\") else { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." }) else { return true }
        let bytes = Array(path.utf8.prefix(2))
        return bytes.count == 2 && bytes[1] == 58 && ((65...90).contains(bytes[0]) || (97...122).contains(bytes[0]))
    }
}
