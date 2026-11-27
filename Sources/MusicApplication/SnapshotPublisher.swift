import CryptoKit
import Foundation

public struct SnapshotManifest: Codable, Sendable {
    public let format: String
    public let revision: Int64
    public let catalogueRevision: Int64?
    public let createdAt: Date
    public let fileName: String
    public let sha256: String
    public var sourceCatalogueRevision: Int64 { catalogueRevision ?? revision }
}

public enum SnapshotPublishError: Error, Equatable, LocalizedError {
    case conflictingRevision(Int64)

    public var errorDescription: String? {
        switch self {
        case .conflictingRevision(let revision):
            return "Snapshot revision \(revision) already exists with different content."
        }
    }
}

public enum SnapshotPublisher {
    public static func publish(json: String, revision: Int64, to directory: URL, retainRevisions: Int = 4) throws -> SnapshotManifest {
        let data = Data(json.utf8)
        return try publish(data: data, hash: digest(data), revision: revision, catalogueRevision: nil, to: directory, retainRevisions: retainRevisions)
    }

    // The manifest revision orders publications for existing companions. The
    // source catalogue revision can repeat or move backwards after restore.
    static func publishCatalogue(json: String, revision: Int64, to directory: URL) throws -> SnapshotManifest {
        let data = Data(json.utf8)
        let hash = digest(data)
        let manifestURL = directory.appending(path: "manifest.json")
        var sequence = revision
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let current = try JSONDecoder().decode(SnapshotManifest.self, from: Data(contentsOf: manifestURL))
            guard current.format == "music-library-snapshot-json-v1", current.revision >= 0,
                  current.fileName == "catalogue-\(current.revision).json" else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if current.sha256 == hash && current.sourceCatalogueRevision == revision {
                sequence = current.revision
                return try publish(data: data, hash: hash, revision: sequence, catalogueRevision: revision, to: directory, retainRevisions: 4)
            }
            sequence = max(revision, try nextRevision(after: current.revision))
        }
        while FileManager.default.fileExists(atPath: directory.appending(path: "catalogue-\(sequence).json").path) {
            sequence = try nextRevision(after: sequence)
        }
        return try publish(data: data, hash: hash, revision: sequence, catalogueRevision: revision, to: directory, retainRevisions: 4)
    }

    private static func nextRevision(after revision: Int64) throws -> Int64 {
        guard revision < Int64.max else { throw SnapshotPublishError.conflictingRevision(revision) }
        return revision + 1
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func publish(data: Data, hash: String, revision: Int64, catalogueRevision: Int64?, to directory: URL, retainRevisions: Int) throws -> SnapshotManifest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "catalogue-\(revision).json"
        let temporary = directory.appending(path: ".\(fileName).tmp")
        let destination = directory.appending(path: fileName)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: destination.path) {
            let existing = try Data(contentsOf: destination)
            let existingHash = digest(existing)
            guard existingHash == hash else { throw SnapshotPublishError.conflictingRevision(revision) }
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        let manifest = SnapshotManifest(format: "music-library-snapshot-json-v1", revision: revision, catalogueRevision: catalogueRevision, createdAt: Date(), fileName: fileName, sha256: hash)
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestTemp = directory.appending(path: ".manifest.json.tmp")
        let manifestURL = directory.appending(path: "manifest.json")
        defer { try? FileManager.default.removeItem(at: manifestTemp) }
        try manifestData.write(to: manifestTemp, options: .atomic)
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            _ = try FileManager.default.replaceItemAt(manifestURL, withItemAt: manifestTemp, backupItemName: nil, options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: manifestTemp, to: manifestURL)
        }
        try retainRevisionFiles(in: directory, keeping: max(1, retainRevisions), currentFileName: fileName)
        return manifest
    }

    private static func retainRevisionFiles(in directory: URL, keeping count: Int, currentFileName: String) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("catalogue-") && $0.pathExtension == "json" }
            .sorted { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast > (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        for file in files.dropFirst(count) where file.lastPathComponent != currentFileName { try? FileManager.default.removeItem(at: file) }
    }
}
