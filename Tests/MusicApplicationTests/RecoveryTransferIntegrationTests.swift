import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Isolated recovery transfer integration")
@MainActor
struct RecoveryTransferIntegrationTests {
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
