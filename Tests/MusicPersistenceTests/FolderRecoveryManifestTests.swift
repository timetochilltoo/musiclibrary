import Foundation
import Testing
import MusicDomain
import MusicPersistence

@Suite("Read-only folder recovery manifest")
struct FolderRecoveryManifestTests {
    @Test("Snapshot isolates one root and preserves CUE references without mutations")
    func rootSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RecoveryManifest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Original", lastKnownPath: directory.appending(path: "A").path, bookmarkData: Data([1, 2, 3]), volumeIdentifier: "fixture-volume", scope: .nasPublished))
        let other = try await database.createStorageRoot(.init(displayName: "Other", lastKnownPath: directory.appending(path: "B").path, bookmarkData: nil))
        let (assets, tracks) = try await seed(database, root: root.id)
        _ = try await seed(database, root: other.id)
        for asset in assets { try await database.recordAssetFingerprint(asset, contentHash: String(repeating: "a", count: 64), quickSignature: "fixture") }
        try await database.updateStorageRootAccess(root.id, status: .offline)
        let before = try await database.storageRoots()
        let revision = try await database.currentRevision()
        let snapshot = try await database.folderRecoveryManifest(rootID: root.id)
        #expect(snapshot.root.id == root.id && snapshot.root.registeredPath == root.lastKnownPath)
        #expect(snapshot.root.displayName == root.displayName && snapshot.root.scope == .nasPublished)
        #expect(snapshot.root.status == .offline && snapshot.root.volumeIdentifier == "fixture-volume")
        #expect(snapshot.root.bookmarkDigest == "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")
        #expect(snapshot.catalogueRevision == revision)
        #expect(Set(snapshot.references.map(\.assetID)) == Set(assets))
        #expect(Set(snapshot.references.map(\.trackID)) == Set(tracks))
        #expect(snapshot.references.allSatisfy { $0.relativePath == "Album/source.flac" && $0.expectedContentHash == String(repeating: "a", count: 64) })
        #expect(Set(snapshot.references.compactMap(\.cueStartMilliseconds)) == Set([Int64(0), 1000]))
        #expect(Set(snapshot.references.compactMap(\.cueEndMilliseconds)) == Set([Int64(1000), 2000]))
        #expect(try await database.folderRecoveryManifest(rootID: root.id) == snapshot)
        #expect(try await database.storageRoots() == before)
        #expect(try await database.currentRevision() == revision)
    }

    @Test("Empty and missing roots do not change state or leave a transaction open")
    func emptyAndMissing() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RecoveryManifest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Empty", lastKnownPath: directory.path, bookmarkData: nil, status: .offline))
        let revision = try await database.currentRevision()
        do { _ = try await database.folderRecoveryManifest(rootID: .init()); Issue.record("Missing root accepted") }
        catch { #expect(error as? DatabaseError == .notFound("Storage root")) }
        let snapshot = try await database.folderRecoveryManifest(rootID: root.id)
        #expect(snapshot.references.isEmpty && snapshot.root.bookmarkDigest == nil)
        #expect(snapshot.root.status == .offline)
        #expect(try await database.currentRevision() == revision)
        try await database.renameStorageRoot(root.id, to: "Writable after snapshot")
    }

    private func seed(_ database: MusicDatabase, root: StorageRootID) async throws -> ([DigitalAssetID], [TrackID]) {
        let batch = try await database.createImportBatch(storageRootID: root, sourceDescription: "Synthetic CUE references; no audio files")
        for index in 0...1 {
            try await database.recordImportCandidate(batchID: batch.id, payload: .init(relativePath: "Album/source.flac", fileName: "source.flac", contentTypeIdentifier: "org.xiph.flac", fileSize: 1, modifiedAt: nil, cueStartMilliseconds: index * 1000, cueEndMilliseconds: (index + 1) * 1000, cueTrackNumber: index + 1))
        }
        let candidates = try await database.importCandidates(batchID: batch.id)
        for candidate in candidates {
            try await database.saveEmbeddedMetadata(.init(title: "Synthetic track", albumTitle: "Synthetic album", artist: nil, albumArtist: nil, discNumber: 1, trackNumber: candidate.payload?.cueTrackNumber, durationMilliseconds: 1000, rawTags: [:]), for: candidate.id)
        }
        try await database.rebuildImportReleaseProposals(batchID: batch.id, drafts: [.init(title: "Synthetic album", artist: nil, discCount: 1, confidence: 1, candidateIDs: candidates.map(\.id))])
        let proposal = try #require(await database.importReleaseProposals(batchID: batch.id).first)
        let album = try await database.confirmImportReleaseProposal(proposal.id)
        let disc = try #require(await database.discs(albumID: album).first)
        return (try await database.digitalAssetIDs(albumID: album), try await database.tracks(discID: disc.id).map(\.id))
    }
}
