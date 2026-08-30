import Foundation
import Testing
@testable import MusicApplication
@testable import MusicDomain
@testable import MusicPersistence

@Suite("Complete catalogue archive")
struct CompleteCatalogueArchiveTests {
    @Test("Archive includes a verified database and every managed artwork file")
    func createsAndStagesCompleteArchive() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MusicDatabase(url: directory.appending(path: "source.sqlite"))
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Archived album"))
        let artworkDirectory = directory.appending(path: "Artwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        let artworkURL = artworkDirectory.appending(path: "cover.jpg")
        try Data([1, 2, 3, 4]).write(to: artworkURL)
        _ = try await database.addAlbumArtwork(albumID: album.id, localPath: artworkURL.path, role: .front, source: "test")

        let exports = directory.appending(path: "Exports", directoryHint: .isDirectory)
        let archive = try await CompleteCatalogueArchive.create(
            database: database,
            managedArtworkDirectory: artworkDirectory,
            in: exports,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let manifest = try CompleteCatalogueArchive.verify(at: archive)
        let revision = try await database.currentRevision()
        #expect(manifest.revision == revision)
        #expect(manifest.artwork.map(\.fileName) == ["cover.jpg"])
        #expect(manifest.artwork.first?.originalPaths == [artworkURL.path])

        let liveArtwork = directory.appending(path: "RestoredArtwork", directoryHint: .isDirectory)
        let staged = try CompleteCatalogueArchive.stageRestore(
            from: archive,
            in: directory.appending(path: "Staging", directoryHint: .isDirectory),
            liveArtworkDirectory: liveArtwork
        )
        #expect(FileManager.default.fileExists(atPath: staged.databaseURL.path))
        #expect(try Data(contentsOf: staged.artworkDirectory.appending(path: "cover.jpg")) == Data([1, 2, 3, 4]))
        #expect(staged.artworkPathMappings[artworkURL.path] == liveArtwork.appending(path: "cover.jpg").path)
        let stagedDatabase = try MusicDatabase(url: staged.databaseURL)
        try await stagedDatabase.migrate()
        #expect(try await stagedDatabase.albums().map(\.title) == ["Archived album"])
    }

    @Test("Archive verification rejects changed managed artwork")
    func rejectsTamperedArchive() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MusicDatabase(url: directory.appending(path: "source.sqlite"))
        try await database.migrate()
        let artworkDirectory = directory.appending(path: "Artwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        try Data([9, 8, 7]).write(to: artworkDirectory.appending(path: "cover.png"))
        let archive = try await CompleteCatalogueArchive.create(
            database: database,
            managedArtworkDirectory: artworkDirectory,
            in: directory.appending(path: "Exports", directoryHint: .isDirectory)
        )
        try Data([0]).write(to: archive.appending(path: "Artwork/cover.png"))
        #expect(throws: (any Error).self) {
            try CompleteCatalogueArchive.verify(at: archive)
        }
    }

    @Test("Complete archive refuses a missing managed artwork payload")
    func rejectsMissingManagedArtwork() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MusicDatabase(url: directory.appending(path: "source.sqlite"))
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Missing cover"))
        let artworkDirectory = directory.appending(path: "Artwork", directoryHint: .isDirectory)
        let missingArtwork = artworkDirectory.appending(path: "missing.jpg")
        _ = try await database.addAlbumArtwork(albumID: album.id, localPath: missingArtwork.path, role: .front, source: "test")

        do {
            _ = try await CompleteCatalogueArchive.create(
                database: database,
                managedArtworkDirectory: artworkDirectory,
                in: directory.appending(path: "Exports", directoryHint: .isDirectory)
            )
            Issue.record("An archive with missing managed artwork must not be created.")
        } catch let error as DatabaseError {
            #expect(error.errorDescription?.contains("Managed artwork is missing") == true)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "CompleteCatalogueArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
