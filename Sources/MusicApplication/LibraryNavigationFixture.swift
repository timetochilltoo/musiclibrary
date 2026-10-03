#if DEBUG
import Foundation
import MusicDomain
import MusicPersistence

extension LibraryStore {
    /// Real services over disposable synthetic data; never calls live startup.
    /// The caller may remove the returned temporary directory after closing the fixture.
    public static func makeNavigationFixture(includeImportReview: Bool = false) async throws -> (store: LibraryStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MusicLibrary-Navigation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let location = try await database.createLocation(.init(name: "Fixture shelf"))
        let box = try await database.createBoxSet(.init(title: "Fixture collected editions", physicalLocationID: location.id))
        let contributor = try await database.createContributor(.init(name: "Fixture Orchestra"))
        for index in 1...240 {
            let album = try await database.createAlbum(.init(
                title: String(format: "Fixture Album %03d", index) + (index.isMultiple(of: 20) ? " — A long classical title with several movements" : ""),
                releaseYear: 1970 + index % 50,
                catalogueNumber: index == 1 ? "FIXTURE-001" : nil,
                barcode: index == 1 ? "0077" : nil, mediaFormat: "CD", hasCD: true,
                physicalLocationID: location.id
            ))
            try await database.addAlbumContributor(contributor.id, to: album.id, role: .albumArtist)
            if index <= 12 { try await database.addAlbum(album.id, to: box.id, at: index) }
        }
        if includeImportReview { try await seedImportReview(database: database, directory: directory) }
        let store = LibraryStore(database: database, metadataLookupProvider: NavigationMetadataFixture())
        try await store.reload()
        return (store, directory)
    }

    private static func seedImportReview(database: MusicDatabase, directory: URL) async throws {
        let rootDirectory = directory.appending(path: "Synthetic Imports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let root = try await database.createStorageRoot(.init(displayName: "Synthetic import root (no audio files)", lastKnownPath: rootDirectory.path, bookmarkData: nil))
        let batch = try await database.createImportBatch(storageRootID: root.id, sourceDescription: "Synthetic import review — no source audio files")
        for index in 1...4 {
            try await database.recordImportCandidate(batchID: batch.id, payload: .init(relativePath: "Candidate \(index)/01.flac", fileName: "01.flac", contentTypeIdentifier: "org.xiph.flac", fileSize: 1, modifiedAt: nil))
        }
        let candidates = try await database.importCandidates(batchID: batch.id)
        var drafts: [ImportReleaseProposalDraft] = []
        for (index, candidate) in candidates.enumerated() {
            let title = "Synthetic candidate \(index + 1)"
            try await database.saveEmbeddedMetadata(.init(title: "Synthetic movement", albumTitle: title, artist: "Fixture Orchestra", albumArtist: "Fixture Orchestra", discNumber: 1, trackNumber: 1, durationMilliseconds: 62000, rawTags: ["ALBUM": title], provenance: "synthetic-fixture"), for: candidate.id)
            drafts.append(.init(title: title, artist: "Fixture Orchestra", discCount: 1, confidence: 0.9, candidateIDs: [candidate.id], provenance: "synthetic-fixture"))
        }
        try await database.rebuildImportReleaseProposals(batchID: batch.id, drafts: drafts)
        let proposals = try await database.importReleaseProposals(batchID: batch.id)
        try await database.updateImportReleaseProposal(proposals[1].id, status: .approved)
        try await database.updateImportReleaseProposal(proposals[2].id, status: .dismissed)
        _ = try await database.confirmImportReleaseProposal(proposals[3].id)
        try await database.finishImportBatch(batch.id, status: .completed)
        // Fake references remain offline. No actual audio file or playback exists.
        try await database.updateStorageRootAccess(root.id, status: .offline)
    }
}

/// Deterministic, explicitly synthetic lookup for physical-entry acceptance.
/// Compiled out of Release and never used by normal catalogue startup.
private struct NavigationMetadataFixture: MetadataLookupProviding {
    func searchRelease(title: String, artist: String?) async throws -> [ExternalReleasePreview] {
        try await lookupRelease(.title(title, artist: artist))
    }
    func lookupRelease(_ lookup: MusicBrainzReleaseLookup) async throws -> [ExternalReleasePreview] {
        [try await releaseDetails(id: "9383a6f5-9607-4a36-9c68-8663aad3592b")]
    }
    func releaseDetails(id: String) async throws -> ExternalReleasePreview {
        try MusicBrainzMetadataProvider.decodeReleaseDetail(from: Data("""
        {"id":"9383a6f5-9607-4a36-9c68-8663aad3592b","title":"Synthetic two-disc release","artist-credit":[{"name":"Fixture Orchestra"}],"media":[
          {"position":1,"title":"Original","format":"CD","track-count":2,"tracks":[{"position":1,"number":"A1","title":"Synthetic opening","length":123456},{"position":2,"number":"A2","title":"Synthetic adagio","length":62000}]},
          {"position":2,"title":"Bonus","format":"CD","track-count":1,"tracks":[{"position":1,"number":"B1","title":"Synthetic finale","length":180000}]}]}
        """.utf8))
    }
}
#endif
