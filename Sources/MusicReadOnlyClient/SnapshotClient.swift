import CryptoKit
import Foundation

public struct ReadOnlySnapshotManifest: Codable, Sendable {
    public let format: String
    public let revision: Int64
    public let fileName: String
    public let sha256: String
    // Written by the device when it activates a verified payload. Legacy
    // cache manifests and manifests from the Mac have no source identity.
    let cacheSourceID: String?

    init(format: String, revision: Int64, fileName: String, sha256: String, cacheSourceID: String? = nil) {
        self.format = format
        self.revision = revision
        self.fileName = fileName
        self.sha256 = sha256
        self.cacheSourceID = cacheSourceID
    }
}

public enum SnapshotClientError: Error, Equatable { case incompatibleFormat, incompatibleCatalogue, unsafeFileName, checksumMismatch }

public final class SnapshotClient {
    public let cacheDirectory: URL
    public init(cacheDirectory: URL) { self.cacheDirectory = cacheDirectory }

    private var localManifestURL: URL { cacheDirectory.appending(path: "manifest.json") }

    static func isSafeSnapshotFileName(_ fileName: String) -> Bool {
        fileName.range(of: #"^catalogue-[0-9]+\.json$"#, options: .regularExpression) != nil
    }

    public func localManifestModificationDate() throws -> Date? {
        guard FileManager.default.fileExists(atPath: localManifestURL.path) else { return nil }
        return try localManifestURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    public func localSnapshotMatchesSource(_ directory: URL) -> Bool? {
        guard let cachedID = cachedManifest()?.cacheSourceID else { return nil }
        return cachedID == Self.sourceID(directory)
    }

    public func sourceManifestIsNewer(from directory: URL) throws -> Bool {
        let url = directory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let manifest = try Self.readSourceManifest(at: url)
        return shouldLoad(manifest, sourceID: Self.sourceID(directory))
    }

    public func update(from directory: URL) throws -> Bool {
        let manifest = try Self.readSourceManifest(at: directory.appending(path: "manifest.json"))
        let sourceID = Self.sourceID(directory)
        if let current = cachedManifest(), current.cacheSourceID == sourceID {
            guard manifest.revision >= current.revision else { return false }
            if manifest.revision == current.revision {
                guard manifest.sha256 == current.sha256 else { throw SnapshotClientError.checksumMismatch }
                // Refresh can repair this publication even when the share has
                // no newer manifest. A readable current payload needs no copy.
                guard (try? readCachedCatalogue(current)) == nil else { return false }
            }
        }
        let data = try Data(contentsOf: directory.appending(path: manifest.fileName))
        let hash = Self.digest(data)
        guard hash == manifest.sha256 else { throw SnapshotClientError.checksumMismatch }
        _ = try Self.decodeCatalogue(data)

        // Two sources can publish the same filename. Key local payloads by
        // their verified bytes and atomically activate source and payload
        // together, leaving the previous manifest usable if activation fails.
        let name = Self.cachePayloadName(hash)
        let installed = ReadOnlySnapshotManifest(
            format: manifest.format, revision: manifest.revision, fileName: name,
            sha256: hash, cacheSourceID: sourceID
        )
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cacheDirectory.appending(path: name), options: .atomic)
        try JSONEncoder().encode(installed).write(to: localManifestURL, options: .atomic)
        return true
    }

    public func localCatalogue() throws -> ReadOnlyCatalogue? {
        guard FileManager.default.fileExists(atPath: localManifestURL.path) else { return nil }
        let manifest = try JSONDecoder().decode(ReadOnlySnapshotManifest.self, from: Data(contentsOf: localManifestURL))
        return try readCachedCatalogue(manifest)
    }

    private func readCachedCatalogue(_ manifest: ReadOnlySnapshotManifest) throws -> ReadOnlyCatalogue {
        guard manifest.format == "music-library-snapshot-json-v1" else { throw SnapshotClientError.incompatibleFormat }
        let contentAddressed = manifest.sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
            && manifest.fileName == Self.cachePayloadName(manifest.sha256)
        guard contentAddressed || Self.isSafeSnapshotFileName(manifest.fileName) else { throw SnapshotClientError.unsafeFileName }
        let data = try Data(contentsOf: cacheDirectory.appending(path: manifest.fileName))
        guard Self.digest(data) == manifest.sha256 else { throw SnapshotClientError.checksumMismatch }
        return try Self.decodeCatalogue(data)
    }

    private func cachedManifest() -> ReadOnlySnapshotManifest? {
        guard let data = try? Data(contentsOf: localManifestURL) else { return nil }
        return try? JSONDecoder().decode(ReadOnlySnapshotManifest.self, from: data)
    }

    private func shouldLoad(_ manifest: ReadOnlySnapshotManifest, sourceID: String) -> Bool {
        // A legacy cache has no source attribution. Verify its next explicit
        // refresh without comparing revisions from an unknown destination.
        guard let current = cachedManifest(), current.cacheSourceID == sourceID else { return true }
        return manifest.revision > current.revision
    }

    private static func readSourceManifest(at url: URL) throws -> ReadOnlySnapshotManifest {
        let manifest = try JSONDecoder().decode(ReadOnlySnapshotManifest.self, from: Data(contentsOf: url))
        guard manifest.format == "music-library-snapshot-json-v1" else { throw SnapshotClientError.incompatibleFormat }
        guard isSafeSnapshotFileName(manifest.fileName) else { throw SnapshotClientError.unsafeFileName }
        return manifest
    }

    private static func decodeCatalogue(_ data: Data) throws -> ReadOnlyCatalogue {
        let catalogue = try JSONDecoder().decode(ReadOnlyCatalogue.self, from: data)
        guard catalogue.format == "music-library-json",
              (1...ReadOnlyCatalogue.maximumSupportedSchemaVersion).contains(catalogue.schemaVersion) else {
            throw SnapshotClientError.incompatibleCatalogue
        }
        return catalogue
    }

    private static func sourceID(_ directory: URL) -> String {
        digest(Data(directory.standardizedFileURL.path.utf8))
    }

    private static func cachePayloadName(_ hash: String) -> String { "catalogue-\(hash).json" }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
