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

public enum SnapshotClientError: Error, Equatable {
    case incompatibleFormat, incompatibleCatalogue, unsafeFileName, checksumMismatch, sourceIsCache
}

public final class SnapshotClient {
    // Separate client instances can use the same cache. Keep readers from
    // capturing an old manifest while its payload is being pruned.
    private static let cacheLock = NSLock()
    public let cacheDirectory: URL
    public init(cacheDirectory: URL) { self.cacheDirectory = cacheDirectory }

    private var localManifestURL: URL { cacheDirectory.appending(path: "manifest.json") }

    static func isSafeSnapshotFileName(_ fileName: String) -> Bool {
        fileName.range(of: #"\Acatalogue-[0-9]+\.json\z"#, options: .regularExpression) != nil
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
        try refreshCatalogue(from: directory).updated
    }

    func refreshCatalogue(from directory: URL) throws -> (updated: Bool, catalogue: ReadOnlyCatalogue?) {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }

        guard !isCacheDirectory(directory) else { throw SnapshotClientError.sourceIsCache }
        let manifest = try Self.readSourceManifest(at: directory.appending(path: "manifest.json"))
        let sourceID = Self.sourceID(directory)
        if let current = cachedManifest(), current.cacheSourceID == sourceID {
            guard manifest.revision >= current.revision else { return (false, nil) }
            if manifest.revision == current.revision {
                guard manifest.sha256 == current.sha256 else { throw SnapshotClientError.checksumMismatch }
                // Refresh can repair this publication even when the share has
                // no newer manifest. A readable current payload needs no copy.
                if let catalogue = try? readCachedCatalogue(current) { return (false, catalogue) }
            }
        }
        let data = try Data(contentsOf: directory.appending(path: manifest.fileName))
        let hash = Self.digest(data)
        guard hash == manifest.sha256 else { throw SnapshotClientError.checksumMismatch }
        let catalogue = try Self.decodeCatalogue(data)

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
        pruneInactivePayloads(keeping: name)
        return (true, catalogue)
    }

    public func localCatalogue() throws -> ReadOnlyCatalogue? {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }

        guard FileManager.default.fileExists(atPath: localManifestURL.path) else { return nil }
        let manifest = try JSONDecoder().decode(ReadOnlySnapshotManifest.self, from: Data(contentsOf: localManifestURL))
        return try readCachedCatalogue(manifest)
    }

    private func readCachedCatalogue(_ manifest: ReadOnlySnapshotManifest) throws -> ReadOnlyCatalogue {
        guard manifest.format == "music-library-snapshot-json-v1" else { throw SnapshotClientError.incompatibleFormat }
        let contentAddressed = manifest.sha256.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil
            && manifest.fileName == Self.cachePayloadName(manifest.sha256)
        guard contentAddressed || Self.isSafeSnapshotFileName(manifest.fileName) else { throw SnapshotClientError.unsafeFileName }
        let data = try Data(contentsOf: cacheDirectory.appending(path: manifest.fileName))
        guard Self.digest(data) == manifest.sha256 else { throw SnapshotClientError.checksumMismatch }
        return try Self.decodeCatalogue(data)
    }

    private func isCacheDirectory(_ directory: URL) -> Bool {
        if cacheDirectory.resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path {
            return true
        }
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let cacheID = (try? cacheDirectory.resourceValues(forKeys: keys))?.fileResourceIdentifier else {
            return false
        }
        return cacheID.isEqual((try? directory.resourceValues(forKeys: keys))?.fileResourceIdentifier)
    }

    private func pruneInactivePayloads(keeping activeName: String) {
        let files = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let entries = try? files.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: Array(keys)
        ) else { return }
        for entry in entries {
            let name = entry.lastPathComponent
            guard name != activeName,
                  Self.isSafeSnapshotFileName(name) ||
                  name.range(of: #"\Acatalogue-[0-9a-f]{64}\.json\z"#, options: .regularExpression) != nil,
                  let values = try? entry.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink == false else { continue }
            // Activation already succeeded. An inaccessible stale copy can
            // be retried on a later successful activation.
            try? files.removeItem(at: entry)
        }
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
