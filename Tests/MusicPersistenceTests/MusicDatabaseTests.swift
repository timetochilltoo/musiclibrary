import Foundation
import Testing
@testable import MusicDomain
@testable import MusicPersistence

@Suite("Music database")
struct MusicDatabaseTests {
    @Test("Migration creates the latest schema")
    func migrationCreatesSchema() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        #expect(try await database.schemaVersion() == 7)
        #expect(try await database.currentRevision() == 0)
    }

    @Test("Creating an album persists it and increments the revision")
    func albumCreation() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Kind of Blue", editionLabel: "Japan version", releaseYear: 1980, hasCD: true))
        let loaded = try await database.album(id: album.id)
        #expect(loaded?.displayTitle == "Kind of Blue — Japan version")
        #expect(loaded?.hasCD == true)
        #expect(try await database.currentRevision() == 1)
    }

    @Test("Adding an album to a box clears its direct location")
    func boxMembershipInheritsLocation() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let location = try await database.createLocation(.init(name: "Shelf 2"))
        let album = try await database.createAlbum(.init(title: "Album", hasCD: true, physicalLocationID: location.id))
        let box = try await database.createBoxSet(.init(title: "Collection", physicalLocationID: location.id))
        try await database.addAlbum(album.id, to: box.id, at: 1)
        let updated = try await database.album(id: album.id)
        #expect(updated?.hasCD == true)
        #expect(updated?.physicalLocationID == nil)
        #expect(try await database.currentRevision() == 4)
    }

    @Test("Locations can be listed and renamed")
    func locationManagement() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let location = try await database.createLocation(.init(name: "Shelf 2"))
        try await database.renameLocation(location.id, to: "Shelf 3")
        let locations = try await database.locations()
        #expect(locations.map(\.name) == ["Shelf 3"])
        #expect(try await database.currentRevision() == 2)
    }

    @Test("An invalid box set leaves album creation atomic")
    func invalidBoxSetRollsBackAlbum() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        await #expect(throws: DatabaseError.notFound("Box set")) {
            _ = try await database.createAlbum(.init(title: "Album", hasCD: true), in: BoxSetID())
        }
        #expect(try await database.albums().isEmpty)
        #expect(try await database.currentRevision() == 0)
    }

    @Test("Editing an album preserves identity and increments revision once")
    func albumEditing() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Original", editionLabel: "1980 pressing"))
        var draft = album.draft
        draft.title = "Corrected"
        draft.editionLabel = "Japan version"
        let updated = try await database.updateAlbum(album.id, with: draft)
        #expect(updated.id == album.id)
        #expect(updated.displayTitle == "Corrected — Japan version")
        #expect(try await database.currentRevision() == 2)
    }

    @Test("Moving, reordering, and removing box members preserves placement rules")
    func boxMembershipManagement() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let shelf = try await database.createLocation(.init(name: "Shelf"))
        let box = try await database.createBoxSet(.init(title: "Collection", physicalLocationID: shelf.id))
        let first = try await database.createAlbum(.init(title: "First", hasCD: true), in: box.id)
        let second = try await database.createAlbum(.init(title: "Second", hasCD: true))
        try await database.moveAlbum(second.id, to: box.id)
        #expect(try await database.boxMembers(of: box.id).map(\.album.id) == [first.id, second.id])
        try await database.reorderAlbum(second.id, in: box.id, to: 1)
        #expect(try await database.boxMembers(of: box.id).map(\.album.id) == [second.id, first.id])
        try await database.removeAlbum(second.id, from: box.id, assigning: nil, locationUnknown: true)
        let removed = try #require(await database.album(id: second.id))
        #expect(removed.hasCD)
        #expect(removed.physicalLocationID == nil)
        #expect(removed.isPhysicalLocationUnknown)
        #expect(try await database.boxMembers(of: box.id).map(\.album.id) == [first.id])
    }

    @Test("Removing a box member without a location rolls back")
    func invalidBoxRemovalRollsBack() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let shelf = try await database.createLocation(.init(name: "Shelf"))
        let box = try await database.createBoxSet(.init(title: "Collection", physicalLocationID: shelf.id))
        let album = try await database.createAlbum(.init(title: "Album", hasCD: true), in: box.id)
        await #expect(throws: DatabaseError.invalidOperation("Choose a physical location or explicitly mark the location unknown before removing an album from its box.")) {
            try await database.removeAlbum(album.id, from: box.id, assigning: nil, locationUnknown: false)
        }
        #expect(try await database.boxMembers(of: box.id).map(\.album.id) == [album.id])
    }

    @Test("Discs, tracks, aliases, and contributor roles preserve catalogue order")
    func catalogueContent() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Album"))
        let firstDisc = try await database.createDisc(albumID: album.id, title: "Disc One")
        let secondDisc = try await database.createDisc(albumID: album.id, title: "Disc Two")
        #expect(try await database.discs(albumID: album.id).map(\.id) == [firstDisc.id, secondDisc.id])
        let firstTrack = try await database.createTrack(discID: firstDisc.id, draft: .init(title: "First"))
        let secondTrack = try await database.createTrack(discID: firstDisc.id, draft: .init(title: "Second", durationMilliseconds: 210_000))
        #expect(try await database.tracks(discID: firstDisc.id).map(\.id) == [firstTrack.id, secondTrack.id])
        let alias = try await database.addAlbumAlias(albumID: album.id, name: "別名", kind: .original, locale: "ja")
        #expect(alias.name == "別名")
        let contributor = try await database.createContributor(.init(name: "Miles Davis"))
        try await database.addAlbumContributor(contributor.id, to: album.id, role: .albumArtist)
        #expect(try await database.albumContributors(albumID: album.id).first?.contributor.name == "Miles Davis")
    }

    @Test("Track credits, artwork selection, and content removal are persisted safely")
    func detailedCatalogueContent() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Album"))
        let disc = try await database.createDisc(albumID: album.id, title: nil)
        let first = try await database.createTrack(discID: disc.id, draft: .init(title: "First"))
        let second = try await database.createTrack(discID: disc.id, draft: .init(title: "Second"))
        let contributor = try await database.createContributor(.init(name: "Guest"))
        try await database.addTrackContributor(contributor.id, to: first.id, role: .performer, creditedName: "G. Artist")
        #expect(try await database.trackContributors(trackID: first.id).first?.creditedName == "G. Artist")
        _ = try await database.addAlbumArtwork(albumID: album.id, localPath: "/art/first.jpg")
        let selected = try await database.addAlbumArtwork(albumID: album.id, localPath: "/art/second.jpg")
        #expect(try await database.albumArtwork(albumID: album.id).filter(\.isSelected).map(\.id) == [selected.id])
        try await database.deleteTrack(first.id)
        #expect(try await database.tracks(discID: disc.id).map(\.number) == [1])
        #expect(try await database.tracks(discID: disc.id).first?.id == second.id)
        let alias = try await database.addAlbumAlias(albumID: album.id, name: "Alternate", kind: .alternate)
        try await database.deleteAlbumAlias(alias.id)
        #expect(try await database.albumAliases(albumID: album.id).isEmpty)
    }

    @Test("Storage roots preserve bookmarks and offline state without deletion")
    func storageRoots() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let bookmark = Data([0x01, 0x02, 0x03])
        let root = try await database.createStorageRoot(.init(displayName: "NAS Music", lastKnownPath: "/Volumes/Music", bookmarkData: bookmark))
        #expect(try await database.storageRoots().first?.bookmarkData == bookmark)
        try await database.updateStorageRootAccess(root.id, status: .offline)
        let offline = try #require(await database.storageRoots().first)
        #expect(offline.status == .offline)
        #expect(offline.lastKnownPath == "/Volumes/Music")
        #expect(offline.bookmarkData == bookmark)
        try await database.renameStorageRoot(root.id, to: "NAS")
        #expect(try await database.storageRoots().first?.displayName == "NAS")
        try await database.deleteStorageRoot(root.id)
        #expect(try await database.storageRoots().isEmpty)
        #expect(try await database.currentRevision() == 4)
    }

    @Test("Import Inbox persists scan candidates without changing the catalogue")
    func importInboxPersistence() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Music", lastKnownPath: "/Music", bookmarkData: Data([1])))
        let batch = try await database.createImportBatch(storageRootID: root.id, sourceDescription: "/Music")
        let payload = ImportCandidatePayload(relativePath: "Artist/Album/song.mp3", fileName: "song.mp3", contentTypeIdentifier: "public.mp3", fileSize: 123, modifiedAt: nil)
        try await database.recordImportCandidate(batchID: batch.id, payload: payload)
        try await database.recordImportError(batchID: batch.id, message: "Unreadable item")
        try await database.finishImportBatch(batch.id, status: .completed)
        let loaded = try #require(await database.importBatches().first)
        #expect(loaded.status == .completed)
        #expect(loaded.processedCount == 2)
        #expect(loaded.candidateCount == 1)
        #expect(loaded.errorCount == 1)
        #expect(try await database.importCandidates(batchID: batch.id).first?.payload == payload)
        #expect(try await database.albums().isEmpty)
        #expect(try await database.currentRevision() == 1)
    }

    @Test("Metadata proposals persist approval without creating catalogue records")
    func metadataProposalReview() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Music", lastKnownPath: "/Music", bookmarkData: Data([1])))
        let batch = try await database.createImportBatch(storageRootID: root.id, sourceDescription: "/Music")
        try await database.recordImportCandidate(batchID: batch.id, payload: .init(relativePath: "Album/song.mp3", fileName: "song.mp3", contentTypeIdentifier: "public.mp3", fileSize: 123, modifiedAt: nil))
        let candidate = try #require(await database.importCandidates(batchID: batch.id).first)
        try await database.saveEmbeddedMetadata(.init(title: "Song", albumTitle: "Album", artist: "Artist", albumArtist: nil, discNumber: 1, trackNumber: 1, durationMilliseconds: 1000, rawTags: ["album": "Album"]), for: candidate.id)
        try await database.rebuildImportReleaseProposals(batchID: batch.id, drafts: [.init(title: "Album", artist: "Artist", discCount: 1, confidence: 0.9, candidateIDs: [candidate.id])])
        let proposal = try #require(await database.importReleaseProposals(batchID: batch.id).first)
        #expect(proposal.status == .proposed)
        try await database.updateImportReleaseProposal(proposal.id, status: .approved)
        #expect(try await database.importReleaseProposals(batchID: batch.id).first?.status == .approved)
        #expect(try await database.albums().isEmpty)
        #expect(try await database.currentRevision() == 1)
    }

    @Test("Approved proposal confirmation is idempotent and derives offline health")
    func confirmedDigitalAssets() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Music", lastKnownPath: "/Music", bookmarkData: Data([1])))
        let batch = try await database.createImportBatch(storageRootID: root.id, sourceDescription: "/Music")
        try await database.recordImportCandidate(batchID: batch.id, payload: .init(relativePath: "Album/song.mp3", fileName: "song.mp3", contentTypeIdentifier: "public.mp3", fileSize: 123, modifiedAt: nil))
        let candidate = try #require(await database.importCandidates(batchID: batch.id).first)
        try await database.saveEmbeddedMetadata(.init(title: "Song", albumTitle: "Album", artist: "Artist", albumArtist: nil, discNumber: 1, trackNumber: 1, durationMilliseconds: 1000, rawTags: [:]), for: candidate.id)
        try await database.rebuildImportReleaseProposals(batchID: batch.id, drafts: [.init(title: "Album", artist: "Artist", discCount: 1, confidence: 0.9, candidateIDs: [candidate.id])])
        let proposal = try #require(await database.importReleaseProposals(batchID: batch.id).first)
        try await database.updateImportReleaseProposal(proposal.id, status: .approved)
        try await database.updateStorageRootAccess(root.id, status: .offline)
        let firstAlbumID = try await database.confirmImportReleaseProposal(proposal.id)
        let secondAlbumID = try await database.confirmImportReleaseProposal(proposal.id)
        #expect(firstAlbumID == secondAlbumID)
        #expect(try await database.albums().map(\.id) == [firstAlbumID])
        #expect(try await database.libraryHealthIssues().map(\.kind) == [.offline])
    }

    @Test("Applying a relink proposal changes only the stored catalogue path")
    func applyRelinkProposal() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Music", lastKnownPath: "/Music", bookmarkData: Data([1])))
        let batch = try await database.createImportBatch(storageRootID: root.id, sourceDescription: "/Music")
        try await database.recordImportCandidate(batchID: batch.id, payload: .init(relativePath: "Album/old-song.mp3", fileName: "old-song.mp3", contentTypeIdentifier: "public.mp3", fileSize: 123, modifiedAt: nil))
        let candidate = try #require(await database.importCandidates(batchID: batch.id).first)
        try await database.saveEmbeddedMetadata(.init(title: "Song", albumTitle: "Album", artist: "Artist", albumArtist: nil, discNumber: 1, trackNumber: 1, durationMilliseconds: 1000, rawTags: [:]), for: candidate.id)
        try await database.rebuildImportReleaseProposals(batchID: batch.id, drafts: [.init(title: "Album", artist: "Artist", discCount: 1, confidence: 0.9, candidateIDs: [candidate.id])])
        let importProposal = try #require(await database.importReleaseProposals(batchID: batch.id).first)
        try await database.updateImportReleaseProposal(importProposal.id, status: .approved)
        let albumID = try await database.confirmImportReleaseProposal(importProposal.id)
        let assetID = try #require(await database.digitalAssetIDs(albumID: albumID).first)
        let relink = try await database.proposeRelink(assetID: assetID, proposedRelativePath: "Album/new-song.mp3")
        let revisionBeforeApply = try await database.currentRevision()

        try await database.applyRelinkProposal(relink.id)

        #expect(try await database.relinkProposals().isEmpty)
        #expect(try await database.assetFingerprintCandidates().first(where: { $0.id == assetID })?.relativePath == "Album/new-song.mp3")
        #expect(try await database.currentRevision() == revisionBeforeApply + 1)
    }

    @Test("Albums can be soft-deleted, restored, and exported")
    func recoveryAndExport() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL()); try await database.migrate(); let album = try await database.createAlbum(.init(title: "Exported", editionLabel: "1980 version", hasCD: true)); try await database.softDeleteAlbum(album.id); #expect(try await database.albums().isEmpty); try await database.restoreAlbum(album.id); #expect(try await database.albums().map(\.id) == [album.id]); let object = try JSONSerialization.jsonObject(with: Data((try await database.catalogueExportJSON()).utf8)) as? [String: Any]; #expect(object?["format"] as? String == "music-library-json"); let rows = object?["albums"] as? [[String: Any]]; #expect(rows?.first?["editionLabel"] as? String == "1980 version"); #expect(rows?.first?["hasCD"] as? Bool == true); #expect(rows?.first?["hasDigital"] as? Bool == false)
    }

    @Test("Playlists preserve ordered track membership")
    func playlists() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Album"))
        let disc = try await database.createDisc(albumID: album.id, title: nil)
        let first = try await database.createTrack(discID: disc.id, draft: .init(title: "First"))
        let second = try await database.createTrack(discID: disc.id, draft: .init(title: "Second"))
        let playlist = try await database.createPlaylist(name: "Favourites")
        try await database.addTrack(second.id, to: playlist.id)
        try await database.addTrack(first.id, to: playlist.id)
        #expect(try await database.playlistItems(playlistID: playlist.id).map(\.trackID) == [second.id, first.id])
    }

    @Test("Published catalogue contains ordered read-only disc and track rows")
    func publishedTrackRows() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Published"))
        let disc = try await database.createDisc(albumID: album.id, title: "Main")
        _ = try await database.createTrack(discID: disc.id, draft: .init(title: "First", durationMilliseconds: 1234))
        let object = try JSONSerialization.jsonObject(with: Data((try await database.catalogueExportJSON()).utf8)) as? [String: Any]
        let albums = try #require(object?["albums"] as? [[String: Any]])
        let discs = try #require(albums.first?["discs"] as? [[String: Any]])
        let tracks = try #require(discs.first?["tracks"] as? [[String: Any]])
        #expect(discs.first?["title"] as? String == "Main")
        #expect(tracks.first?["title"] as? String == "First")
        #expect((tracks.first?["assets"] as? [[String: Any]])?.isEmpty == true)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "MusicDatabaseTests-\(UUID().uuidString).sqlite")
    }
}
