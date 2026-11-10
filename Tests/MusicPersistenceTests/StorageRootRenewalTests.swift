import Foundation
import Testing
import MusicDomain
import MusicPersistence

@Suite("Storage root permission renewal")
struct StorageRootRenewalTests {
    @Test("Renewal preserves root identity, relative assets, scope and source bytes")
    func preservesReferences() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RootRenewal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sentinel = directory.appending(path: "source-sentinel.flac")
        try Data([4, 5, 6]).write(to: sentinel)
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "My collection", lastKnownPath: directory.path, bookmarkData: Data([1]), volumeIdentifier: "fixture-volume", status: .available, scope: .nasPublished))
        let batch = try await database.createImportBatch(storageRootID: root.id, sourceDescription: "Synthetic references only")
        try await database.recordImportCandidate(batchID: batch.id, payload: .init(relativePath: "Album/song.flac", fileName: "song.flac", contentTypeIdentifier: "org.xiph.flac", fileSize: 1, modifiedAt: nil))
        let candidate = try #require(await database.importCandidates(batchID: batch.id).first)
        try await database.saveEmbeddedMetadata(.init(title: "Song", albumTitle: "Album", artist: nil, albumArtist: nil, discNumber: 1, trackNumber: 1, durationMilliseconds: 1000, rawTags: [:]), for: candidate.id)
        try await database.rebuildImportReleaseProposals(batchID: batch.id, drafts: [.init(title: "Album", artist: nil, discCount: 1, confidence: 1, candidateIDs: [candidate.id])])
        let proposal = try #require(await database.importReleaseProposals(batchID: batch.id).first)
        let album = try await database.confirmImportReleaseProposal(proposal.id)
        let assets = try await database.digitalAssetIDs(albumID: album)
        try await database.updateStorageRootAccess(root.id, status: .permissionRequired, bookmarkNeedsRefresh: true)
        let revision = try await database.currentRevision()
        try await database.renewStorageRootBookmark(root.id, expectedPath: directory.path, bookmarkData: Data([9, 8]))
        let roots = try await database.storageRoots()
        let renewed = try #require(roots.first)
        #expect(roots.count == 1 && renewed.id == root.id)
        #expect(renewed.displayName == root.displayName && renewed.scope == root.scope)
        #expect(renewed.lastKnownPath == root.lastKnownPath && renewed.volumeIdentifier == root.volumeIdentifier)
        #expect(renewed.bookmarkData == Data([9, 8]) && renewed.status == .available)
        #expect(!renewed.bookmarkNeedsRefresh && renewed.lastSeenAt != nil)
        #expect(try await database.digitalAssetIDs(albumID: album) == assets)
        let reference = try #require(await database.assetFingerprintCandidates().first)
        #expect(reference.rootID == root.id && reference.relativePath == "Album/song.flac")
        #expect(try await database.currentRevision() == revision + 1)
        #expect(try Data(contentsOf: sentinel) == Data([4, 5, 6]))
    }

    @Test("Stale, missing or empty renewal requests leave the catalogue untouched", arguments: [0, 1, 2])
    func refusesInvalidRequests(kind: Int) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RootRenewal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Music", lastKnownPath: directory.path, bookmarkData: Data([1]), status: .offline))
        let revision = try await database.currentRevision()
        do {
            try await database.renewStorageRootBookmark(kind == 1 ? StorageRootID() : root.id, expectedPath: kind == 0 ? directory.appending(path: "wrong").path : directory.path, bookmarkData: kind == 2 ? Data() : Data([9]))
            Issue.record("Invalid renewal accepted")
        } catch {}
        let unchanged = try #require(await database.storageRoots().first)
        #expect(unchanged.id == root.id && unchanged.bookmarkData == Data([1]) && unchanged.status == .offline)
        #expect(try await database.currentRevision() == revision)
    }
}
