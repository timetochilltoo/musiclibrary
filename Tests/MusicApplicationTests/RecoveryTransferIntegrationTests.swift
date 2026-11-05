import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Isolated recovery transfer integration")
@MainActor
struct RecoveryTransferIntegrationTests {
    @Test("Reset requires exact confirmation, preserves roots and audio, and verifies complete recovery")
    func resetPreservesRoots() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        try await seedPublishedAlbum(in: root)
        try await store.reload()
        let roots = store.storageRoots
        let revision = store.catalogueRevision
        let audio = root.appending(path: "AudioReferences/synthetic.flac")
        try FileManager.default.createDirectory(at: audio.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sentinel = Data("Disposable source sentinel".utf8)
        try sentinel.write(to: audio)
        let artwork = root.appending(path: "Artwork/cover.jpg")
        try FileManager.default.createDirectory(at: artwork.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: artwork)
        for confirmation in ["reset", " RESET", "RESET ", ""] {
            do { _ = try await store.resetCatalogue(confirmation: confirmation); Issue.record("Invalid reset accepted") } catch {}
        }
        #expect(store.catalogueRevision == revision)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Recovery").path))
        let archive = try await store.resetCatalogue(confirmation: "RESET")
        let manifest = try CompleteCatalogueArchive.verify(at: archive)
        #expect(manifest.revision == revision)
        #expect(manifest.artwork.map(\.fileName) == ["cover.jpg"])
        #expect(store.storageRoots == roots)
        #expect(store.catalogueAlbums.isEmpty)
        #expect(try Data(contentsOf: audio) == sentinel)
        #expect(try FileManager.default.contentsOfDirectory(atPath: artwork.deletingLastPathComponent().path).isEmpty)
        let archived = try MusicDatabase(url: archive.appending(path: CompleteCatalogueArchive.databaseFileName))
        #expect(try await archived.albums().first?.title == "Archived original")
        #expect(!store.transferActivity.isBusy)
    }

    @Test("Database-only restore preserves current artwork/audio and keeps the prior database")
    func databaseRestore() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        let album = try await store.addAlbum(.init(title: "Backed up title"))
        let backup = try await createDatabaseBackup(in: root)
        try await store.updateAlbum(album.id, with: .init(title: "Before restore"))
        let artwork = root.appending(path: "Artwork/current.jpg")
        try FileManager.default.createDirectory(at: artwork.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([9, 8, 7]).write(to: artwork)
        let audio = root.appending(path: "source-sentinel.flac")
        try Data([4, 5]).write(to: audio)
        try await store.restoreMasterBackup(from: backup)
        #expect(store.catalogueAlbums.first?.title == "Backed up title")
        #expect(try Data(contentsOf: artwork) == Data([9, 8, 7]))
        #expect(try Data(contentsOf: audio) == Data([4, 5]))
        let recovery = root.appending(path: "Recovery")
        let saved = try #require(FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "sqlite" }))
        try MusicDatabase.verifyStandaloneBackupFile(at: saved)
        let previous = try MusicDatabase(url: saved)
        #expect(try await previous.albums().first?.title == "Before restore")
        #expect(!store.transferActivity.isBusy)
    }

    @Test("Tampered database backup refuses before recovery or replacement and leaves queue reusable")
    func tamperedDatabaseRestore() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        _ = try await store.addAlbum(.init(title: "Keep live title"))
        let manifestURL = try await createDatabaseBackup(in: root)
        let manifest = try JSONDecoder().decode(MasterBackupManifest.self, from: Data(contentsOf: manifestURL))
        let payload = try MasterBackupArchive.validatedBackupURL(for: manifest, in: manifestURL.deletingLastPathComponent())
        try Data([0]).write(to: payload)
        let revision = store.catalogueRevision
        do { try await store.restoreMasterBackup(from: manifestURL); Issue.record("Tampered backup accepted") } catch {}
        #expect(store.catalogueRevision == revision)
        #expect(store.catalogueAlbums.first?.title == "Keep live title")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Recovery").path))
        #expect(!store.transferActivity.isBusy)
        _ = try await store.publishSnapshot(to: root.appending(path: "Shared"))
    }

    private func createDatabaseBackup(in root: URL) async throws -> URL {
        let database = try MusicDatabase(url: root.appending(path: "MusicLibrary.sqlite"))
        let destination = root.appending(path: "Database Backups #? fixture")
        let manifest = try await MasterBackupArchive.create(database: database, in: destination)
        let payload = try MasterBackupArchive.validatedBackupURL(for: manifest, in: destination)
        let original = try Data(contentsOf: payload)
        try await MasterBackupArchive.verify(manifest, in: destination)
        #expect(try Data(contentsOf: payload) == original)
        try await MasterBackupArchive.verify(manifest, in: destination)
        return destination.appending(path: manifest.fileName + ".manifest.json")
    }

    @Test("Queued real restore replaces catalogue and artwork before later publication")
    func restoreThenPublish() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        try await seedPublishedAlbum(in: root)
        try await store.reload()
        let album = try #require(store.catalogueAlbums.first)
        let art = root.appending(path: "Artwork/cover.jpg")
        try FileManager.default.createDirectory(at: art.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: art)
        let archive = try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
        try await store.updateAlbum(album.id, with: .init(title: "Later correction"))
        try Data([9]).write(to: art)
        var release: CheckedContinuation<Void, Never>?
        let writer = Task { try await store.transferQueue.run(.sharing) {
            await withCheckedContinuation { release = $0 }
        } }
        while release == nil { await Task.yield() }
        let restore = Task { try await store.restoreCompleteCatalogueArchive(from: archive) }
        while !store.transferActivity.waiting.contains(.archiveRestore) { await Task.yield() }
        let destination = root.appending(path: "Shared")
        let publish = Task { try await store.publishSnapshot(to: destination) }
        while store.transferActivity.waiting.count < 2 { await Task.yield() }
        #expect(store.catalogueAlbums.first?.title == "Later correction")
        release?.resume()
        try await writer.value
        try await restore.value
        let manifest = try await publish.value
        #expect(store.catalogueAlbums.first?.title == "Archived original")
        #expect(try Data(contentsOf: art) == Data([1, 2, 3]))
        let json = try String(contentsOf: destination.appending(path: manifest.fileName), encoding: .utf8)
        #expect(json.contains("Archived original") && !json.contains("Later correction"))
        #expect(manifest.revision == store.catalogueRevision)
        #expect(store.transferActivity == LibraryTransferActivity())
        let recovery = root.appending(path: "Recovery/CatalogueArchives/before-archive-restore")
        let saved = try #require(FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil).first)
        _ = try CompleteCatalogueArchive.verify(at: saved)
    }

    private func seedPublishedAlbum(in root: URL) async throws {
        let database = try MusicDatabase(url: root.appending(path: "MusicLibrary.sqlite"))
        let storage = try await database.createStorageRoot(.init(displayName: "Synthetic published root", lastKnownPath: root.appending(path: "AudioReferences").path, bookmarkData: nil, scope: .nasPublished))
        let batch = try await database.createImportBatch(storageRootID: storage.id, sourceDescription: "No audio files")
        try await database.recordImportCandidate(batchID: batch.id, payload: .init(relativePath: "synthetic.flac", fileName: "synthetic.flac", contentTypeIdentifier: "org.xiph.flac", fileSize: 1, modifiedAt: nil))
        let candidate = try #require(await database.importCandidates(batchID: batch.id).first)
        try await database.saveEmbeddedMetadata(.init(title: "Synthetic track", albumTitle: "Archived original", artist: nil, albumArtist: nil, discNumber: 1, trackNumber: 1, durationMilliseconds: 1000, rawTags: [:]), for: candidate.id)
        try await database.rebuildImportReleaseProposals(batchID: batch.id, drafts: [.init(title: "Archived original", artist: nil, discCount: 1, confidence: 1, candidateIDs: [candidate.id])])
        let proposal = try #require(await database.importReleaseProposals(batchID: batch.id).first)
        _ = try await database.confirmImportReleaseProposal(proposal.id)
    }

    @Test("Tampered restore refuses replacement and releases the queue for publication")
    func tamperThenPublish() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        _ = try await store.addAlbum(.init(title: "Live catalogue"))
        let archive = try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
        try Data([0]).write(to: archive.appending(path: CompleteCatalogueArchive.databaseFileName))
        let revision = store.catalogueRevision
        do { try await store.restoreCompleteCatalogueArchive(from: archive); Issue.record("Tampered archive accepted") } catch {}
        let destination = root.appending(path: "Shared")
        let manifest = try await store.publishSnapshot(to: destination)
        #expect(manifest.revision == revision)
        #expect(store.catalogueAlbums.first?.title == "Live catalogue")
        #expect(!store.transferActivity.isBusy)
    }

    @Test("Fixture refuses outside paths and persistent sharing configuration")
    func boundary() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        do { try store.setSnapshotDestination(root); Issue.record("Fixture preferences enabled") } catch {}
        do { _ = try await store.publishSnapshot(to: root.deletingLastPathComponent()); Issue.record("Outside path accepted") } catch {}
        do { _ = try await LibraryStore(recoveryFixtureDirectory: FileManager.default.temporaryDirectory); Issue.record("Temporary root accepted") } catch {}
        #expect(!store.transferActivity.isBusy)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "RecoveryIntegration-\(UUID().uuidString)")
    }
}
