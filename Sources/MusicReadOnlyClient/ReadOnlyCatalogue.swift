import CryptoKit
import Foundation

public struct ReadOnlyCatalogue: Codable, Equatable, Sendable {
    public let format: String
    public let schemaVersion: Int
    public let catalogueRevision: Int64
    public let albums: [ReadOnlyAlbum]

    public init(format: String, schemaVersion: Int, catalogueRevision: Int64, albums: [ReadOnlyAlbum]) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.catalogueRevision = catalogueRevision
        self.albums = albums
    }
}

public struct ReadOnlyAlbum: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let editionLabel: String?
    public let releaseYear: Int?
    public let catalogueNumber: String?
    public let hasCD: Bool
    public let hasDigital: Bool

    public init(id: String, title: String, editionLabel: String? = nil, releaseYear: Int? = nil, catalogueNumber: String? = nil, hasCD: Bool, hasDigital: Bool) {
        self.id = id
        self.title = title
        self.editionLabel = editionLabel
        self.releaseYear = releaseYear
        self.catalogueNumber = catalogueNumber
        self.hasCD = hasCD
        self.hasDigital = hasDigital
    }

    public var displayTitle: String {
        guard let editionLabel, !editionLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return title }
        return "\(title) — \(editionLabel)"
    }

    public func matches(_ term: String) -> Bool {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return [title, editionLabel, catalogueNumber].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(normalized) }
    }
}

public extension SnapshotClient {
    func localCatalogue() throws -> ReadOnlyCatalogue? {
        let manifestURL = cacheDirectory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        let manifest = try JSONDecoder().decode(ReadOnlySnapshotManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.format == "music-library-snapshot-json-v1" else { throw SnapshotClientError.incompatibleFormat }
        guard !manifest.fileName.contains("/"), !manifest.fileName.contains("..") else { throw SnapshotClientError.unsafeFileName }
        let data = try Data(contentsOf: cacheDirectory.appending(path: manifest.fileName))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == manifest.sha256 else { throw SnapshotClientError.checksumMismatch }
        let catalogue = try JSONDecoder().decode(ReadOnlyCatalogue.self, from: data)
        guard catalogue.format == "music-library-json" else { throw SnapshotClientError.incompatibleCatalogue }
        return catalogue
    }
}
