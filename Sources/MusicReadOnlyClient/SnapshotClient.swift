import CryptoKit
import Foundation

public struct ReadOnlySnapshotManifest: Codable, Sendable { public let format: String; public let revision: Int64; public let fileName: String; public let sha256: String }
public enum SnapshotClientError: Error, Equatable { case incompatibleFormat, incompatibleCatalogue, unsafeFileName, checksumMismatch }

public final class SnapshotClient {
    public let cacheDirectory: URL
    public init(cacheDirectory: URL) { self.cacheDirectory = cacheDirectory }
    static func isSafeSnapshotFileName(_ fileName: String) -> Bool {
        fileName.range(of: #"^catalogue-[0-9]+\.json$"#, options: .regularExpression) != nil
    }
    public func localManifestModificationDate() throws -> Date? {
        let manifest = cacheDirectory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        return try manifest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
    public func sourceManifestIsNewer(from directory: URL) throws -> Bool {
        let sourceManifest = directory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: sourceManifest.path) else { return false }
        let localManifest = cacheDirectory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: localManifest.path) else { return true }
        let sourceDate = try sourceManifest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let localDate = try localManifest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard let sourceDate else { return false }
        guard let localDate else { return true }
        return sourceDate > localDate
    }
    public func update(from directory: URL) throws -> Bool {
        let manifestURL = directory.appending(path: "manifest.json")
        let manifest = try JSONDecoder().decode(ReadOnlySnapshotManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.format == "music-library-snapshot-json-v1" else { throw SnapshotClientError.incompatibleFormat }
        guard Self.isSafeSnapshotFileName(manifest.fileName) else { throw SnapshotClientError.unsafeFileName }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let localManifest = cacheDirectory.appending(path: "manifest.json")
        if let current = try? JSONDecoder().decode(ReadOnlySnapshotManifest.self, from: Data(contentsOf: localManifest)), current.revision >= manifest.revision { return false }
        let data = try Data(contentsOf: directory.appending(path: manifest.fileName))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == manifest.sha256 else { throw SnapshotClientError.checksumMismatch }
        let payloadURL = cacheDirectory.appending(path: manifest.fileName)
        let temporary = cacheDirectory.appending(path: ".\(manifest.fileName).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: payloadURL.path) {
            let existing = try Data(contentsOf: payloadURL)
            let existingHash = SHA256.hash(data: existing).map { String(format: "%02x", $0) }.joined()
            guard existingHash == manifest.sha256 else { throw SnapshotClientError.checksumMismatch }
        } else {
            try FileManager.default.moveItem(at: temporary, to: payloadURL)
        }
        let manifestTemp = cacheDirectory.appending(path: ".manifest.json.tmp")
        defer { try? FileManager.default.removeItem(at: manifestTemp) }
        try Data(contentsOf: manifestURL).write(to: manifestTemp, options: .atomic)
        if FileManager.default.fileExists(atPath: localManifest.path) {
            _ = try FileManager.default.replaceItemAt(localManifest, withItemAt: manifestTemp, backupItemName: nil, options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: manifestTemp, to: localManifest)
        }
        return true
    }
}
