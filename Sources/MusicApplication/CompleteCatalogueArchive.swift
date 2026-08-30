import CryptoKit
import Foundation
import MusicPersistence

public struct CompleteCatalogueArchiveFile: Codable, Equatable, Sendable {
    public let fileName: String
    public let originalPaths: [String]
    public let byteCount: Int64
    public let sha256: String

    public init(fileName: String, originalPaths: [String], byteCount: Int64, sha256: String) {
        self.fileName = fileName
        self.originalPaths = originalPaths
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct CompleteCatalogueArchiveManifest: Codable, Equatable, Sendable {
    public let format: String
    public let revision: Int64
    public let createdAt: Date
    public let database: CompleteCatalogueArchiveFile
    public let artwork: [CompleteCatalogueArchiveFile]

    public init(
        revision: Int64,
        createdAt: Date,
        database: CompleteCatalogueArchiveFile,
        artwork: [CompleteCatalogueArchiveFile]
    ) {
        self.format = "music-library-complete-archive-v1"
        self.revision = revision
        self.createdAt = createdAt
        self.database = database
        self.artwork = artwork
    }
}

public struct StagedCatalogueRestore: Sendable {
    public let manifest: CompleteCatalogueArchiveManifest
    public let databaseURL: URL
    public let artworkDirectory: URL
    public let artworkPathMappings: [String: String]
}

public enum CompleteCatalogueArchive {
    public static let manifestFileName = "manifest.json"
    public static let databaseFileName = "MusicLibrary.sqlite"
    public static let artworkDirectoryName = "Artwork"

    public static func create(
        database: MusicDatabase,
        managedArtworkDirectory: URL,
        in destinationDirectory: URL,
        now: Date = .now
    ) async throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let revision = try await database.currentRevision()
        let stamp = Int64((now.timeIntervalSince1970 * 1_000).rounded())
        let archiveName = "MusicLibraryCatalogue-r\(revision)-\(stamp).musiclibraryarchive"
        let destination = destinationDirectory.appending(path: archiveName, directoryHint: .isDirectory)
        guard !manager.fileExists(atPath: destination.path) else {
            throw DatabaseError.invalidOperation("A catalogue archive with this name already exists.")
        }

        let staging = destinationDirectory.appending(path: ".\(archiveName).\(UUID().uuidString).tmp", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: staging) }
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        let stagedDatabase = staging.appending(path: databaseFileName)
        try await database.createConsistentBackup(at: stagedDatabase)
        try MusicDatabase.verifyDatabaseFile(at: stagedDatabase)
        let recordedArtworkPaths = try await database.managedArtworkLocalPaths().filter {
            RegisteredPathSecurity.contains(URL(fileURLWithPath: $0), within: managedArtworkDirectory)
        }

        let artworkDestination = staging.appending(path: artworkDirectoryName, directoryHint: .isDirectory)
        try manager.createDirectory(at: artworkDestination, withIntermediateDirectories: false)
        var artworkFiles: [CompleteCatalogueArchiveFile] = []
        if manager.fileExists(atPath: managedArtworkDirectory.path) {
            for source in try manager.contentsOfDirectory(
                at: managedArtworkDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ).sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw DatabaseError.invalidOperation("Managed artwork contains an unsupported item: \(source.lastPathComponent).")
                }
                try validateSingleFileName(source.lastPathComponent)
                let copied = artworkDestination.appending(path: source.lastPathComponent)
                try manager.copyItem(at: source, to: copied)
                let digest = try fileDigest(at: copied)
                let originalPaths = recordedArtworkPaths.filter { URL(fileURLWithPath: $0).lastPathComponent == source.lastPathComponent }
                artworkFiles.append(.init(
                    fileName: source.lastPathComponent,
                    originalPaths: originalPaths.isEmpty ? [source.path] : originalPaths,
                    byteCount: digest.byteCount,
                    sha256: digest.sha256
                ))
            }
        }
        let archivedArtworkNames = Set(artworkFiles.map(\CompleteCatalogueArchiveFile.fileName))
        let requiredArtworkNames = Set(recordedArtworkPaths.map { URL(fileURLWithPath: $0).lastPathComponent })
        guard requiredArtworkNames.isSubset(of: archivedArtworkNames) else {
            let missing = requiredArtworkNames.subtracting(archivedArtworkNames).sorted().joined(separator: ", ")
            throw DatabaseError.invalidOperation("Managed artwork is missing and the complete archive was not created: \(missing).")
        }

        let databaseDigest = try fileDigest(at: stagedDatabase)
        let manifest = CompleteCatalogueArchiveManifest(
            revision: revision,
            createdAt: now,
            database: .init(fileName: databaseFileName, originalPaths: [], byteCount: databaseDigest.byteCount, sha256: databaseDigest.sha256),
            artwork: artworkFiles
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: staging.appending(path: manifestFileName), options: .atomic)
        try manager.moveItem(at: staging, to: destination)
        return destination
    }

    @discardableResult
    public static func verify(at archiveURL: URL) throws -> CompleteCatalogueArchiveManifest {
        let manager = FileManager.default
        let values = try archiveURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw DatabaseError.invalidOperation("Choose a complete catalogue archive folder.")
        }
        let manifestURL = archiveURL.appending(path: manifestFileName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(CompleteCatalogueArchiveManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.format == "music-library-complete-archive-v1" else {
            throw DatabaseError.invalidOperation("Unsupported complete catalogue archive format.")
        }
        guard manifest.database.fileName == databaseFileName, manifest.database.originalPaths.isEmpty else {
            throw DatabaseError.invalidOperation("The catalogue archive database entry is unsafe.")
        }
        let databaseURL = archiveURL.appending(path: databaseFileName)
        try verify(manifest.database, at: databaseURL)
        try MusicDatabase.verifyDatabaseFile(at: databaseURL)

        let artworkDirectory = archiveURL.appending(path: artworkDirectoryName, directoryHint: .isDirectory)
        let declaredNames = Set(manifest.artwork.map(\CompleteCatalogueArchiveFile.fileName))
        guard declaredNames.count == manifest.artwork.count else {
            throw DatabaseError.invalidOperation("The catalogue archive declares duplicate artwork files.")
        }
        for artwork in manifest.artwork {
            try validateSingleFileName(artwork.fileName)
            try verify(artwork, at: artworkDirectory.appending(path: artwork.fileName))
        }
        let actualNames = Set(try manager.contentsOfDirectory(atPath: artworkDirectory.path).filter { !$0.hasPrefix(".") })
        guard actualNames == declaredNames else {
            throw DatabaseError.invalidOperation("The catalogue archive artwork list is incomplete or contains unexpected files.")
        }
        return manifest
    }

    public static func stageRestore(
        from archiveURL: URL,
        in stagingParent: URL,
        liveArtworkDirectory: URL
    ) throws -> StagedCatalogueRestore {
        let manager = FileManager.default
        let manifest = try verify(at: archiveURL)
        let staging = stagingParent.appending(path: "CatalogueRestore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let databaseURL = staging.appending(path: databaseFileName)
            try manager.copyItem(at: archiveURL.appending(path: databaseFileName), to: databaseURL)
            let artworkDirectory = staging.appending(path: artworkDirectoryName, directoryHint: .isDirectory)
            try manager.copyItem(at: archiveURL.appending(path: artworkDirectoryName), to: artworkDirectory)
            var mappings: [String: String] = [:]
            for artwork in manifest.artwork {
                for originalPath in artwork.originalPaths {
                    mappings[originalPath] = liveArtworkDirectory.appending(path: artwork.fileName).path
                }
            }
            return .init(
                manifest: manifest,
                databaseURL: databaseURL,
                artworkDirectory: artworkDirectory,
                artworkPathMappings: mappings
            )
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    private static func validateSingleFileName(_ fileName: String) throws {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              !fileName.hasPrefix("."),
              !fileName.contains("/"),
              !fileName.contains("\\"),
              !fileName.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw DatabaseError.invalidOperation("The catalogue archive contains an unsafe file name.")
        }
    }

    private static func verify(_ file: CompleteCatalogueArchiveFile, at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw DatabaseError.invalidOperation("A required catalogue archive file is missing or unsafe.")
        }
        let digest = try fileDigest(at: url)
        guard digest.byteCount == file.byteCount, digest.sha256 == file.sha256 else {
            throw DatabaseError.invalidOperation("Catalogue archive checksum verification failed for \(file.fileName).")
        }
    }

    private static func fileDigest(at url: URL) throws -> (byteCount: Int64, sha256: String) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            byteCount += Int64(data.count)
            hasher.update(data: data)
        }
        return (byteCount, hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
