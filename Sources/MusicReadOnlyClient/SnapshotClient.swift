import CryptoKit
import Foundation

public struct ReadOnlySnapshotManifest: Codable, Sendable { public let format: String; public let revision: Int64; public let fileName: String; public let sha256: String }
public enum SnapshotClientError: Error, Equatable { case incompatibleFormat, unsafeFileName, checksumMismatch }

public final class SnapshotClient {
    public let cacheDirectory: URL
    public init(cacheDirectory: URL) { self.cacheDirectory = cacheDirectory }
    public func update(from directory: URL) throws -> Bool {
        let manifestURL = directory.appending(path: "manifest.json")
        let manifest = try JSONDecoder().decode(ReadOnlySnapshotManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.format == "music-library-snapshot-json-v1" else { throw SnapshotClientError.incompatibleFormat }
        guard !manifest.fileName.contains("/"), !manifest.fileName.contains("..") else { throw SnapshotClientError.unsafeFileName }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let localManifest = cacheDirectory.appending(path: "manifest.json")
        if let current = try? JSONDecoder().decode(ReadOnlySnapshotManifest.self, from: Data(contentsOf: localManifest)), current.revision >= manifest.revision { return false }
        let data = try Data(contentsOf: directory.appending(path: manifest.fileName)); let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(); guard hash == manifest.sha256 else { throw SnapshotClientError.checksumMismatch }
        let temporary = cacheDirectory.appending(path: ".\(manifest.fileName).tmp"); try data.write(to: temporary, options: .atomic); try? FileManager.default.removeItem(at: cacheDirectory.appending(path: manifest.fileName)); try FileManager.default.moveItem(at: temporary, to: cacheDirectory.appending(path: manifest.fileName)); try Data(contentsOf: manifestURL).write(to: localManifest, options: .atomic); return true
    }
}
