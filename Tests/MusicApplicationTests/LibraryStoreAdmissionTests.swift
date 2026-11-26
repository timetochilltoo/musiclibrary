import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("LibraryStore partial admission integration", .timeLimit(.minutes(1)))
@MainActor
struct LibraryStoreAdmissionTests {
    @Test("Album edit retains its lease through nested reload/search and rejects new migrated work")
    func editDrain() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let store = LibraryStore(database: fixture.database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        await store.search("album")
        probe.holdNext = true
        let edit = Task { try await store.updateAlbum(fixture.album.id, with: .init(title: "Updated album")) }
        try await until { probe.gate.started }
        #expect(store.catalogueAdmission.activeOperationCount == 1)
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in
            #expect(store.albums.first?.title == "Updated album")
            #expect(store.catalogueAdmission.activeOperationCount == 0)
            await maintenance.hold()
        } }
        try await until { store.catalogueAdmission.phase == .draining }
        do { _ = try await store.discs(albumID: fixture.album.id); Issue.record("Disc read bypassed admission") }
        catch { #expect(error as? CatalogueAdmission.Failure == .maintenancePending) }
        do { _ = try await store.tracks(discID: fixture.disc.id); Issue.record("Track read bypassed admission") }
        catch { #expect(error as? CatalogueAdmission.Failure == .maintenancePending) }
        do { try await store.updateAlbum(fixture.album.id, with: .init(title: "Must refuse")); Issue.record("Edit bypassed admission") }
        catch { #expect(error as? CatalogueAdmission.Failure == .maintenancePending) }
        do { try await store.reload(); Issue.record("Reload bypassed admission") }
        catch { #expect(error as? CatalogueAdmission.Failure == .maintenancePending) }
        let requests = probe.requests
        await store.search("must not replace the admitted query")
        #expect(probe.requests == requests && store.errorMessage != nil)
        store.dismissError()
        #expect(try await fixture.database.albums().first?.title == "Updated album")
        #expect(!maintenance.started)
        probe.gate.open(); try await edit.value
        try await until { maintenance.started }
        #expect(store.errorMessage == nil)
        maintenance.open(); try await barrier.value
        try await store.reload()
        #expect(store.albums.first?.title == "Updated album") // Rejected query was not adopted.
        #expect(try await store.discs(albumID: fixture.album.id).map(\.id) == [fixture.disc.id])
        #expect(try await store.tracks(discID: fixture.disc.id).map(\.id) == [fixture.track.id])
        #expect(store.catalogueAdmission.activeOperationCount == 0)
    }

    @Test("Suspended search drains before maintenance, including parent cancellation", arguments: [false, true])
    func readerDrain(cancel: Bool) async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let store = LibraryStore(database: fixture.database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        // A deliberate fixture-only mutation distinguishes the held query's new
        // result from the earlier cache without touching production services.
        _ = try await fixture.database.createAlbum(.init(title: "Another album"))
        probe.holdNext = true
        let search = Task { await store.search("album") }
        try await until { probe.gate.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in
            #expect(store.albums.count == (cancel ? 1 : 2))
            await maintenance.hold()
        } }
        try await until { store.catalogueAdmission.phase == .draining }
        if cancel { search.cancel() }
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        probe.gate.open(); await search.value
        try await until { maintenance.started }
        #expect(store.errorMessage == nil)
        maintenance.open(); try await barrier.value
        #expect(store.catalogueAdmission.phase == .open)
    }

    @Test("Validation/provider failures release leases without changing the catalogue")
    func failures() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let probe = Probe()
        let store = LibraryStore(database: fixture.database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        let revision = try await fixture.database.currentRevision()
        do { try await store.updateAlbum(fixture.album.id, with: .init(title: "")); Issue.record("Invalid draft accepted") }
        catch { #expect(error is ValidationError) }
        probe.failNext = true
        await store.search("album")
        #expect(store.errorMessage != nil)
        #expect(store.catalogueAdmission.activeOperationCount == 0 && store.catalogueAdmission.phase == .open)
        #expect(try await fixture.database.currentRevision() == revision)
        #expect(try await fixture.database.albums().first?.title == "Original album")
        try await store.catalogueAdmission.withMaintenance { _ in }
        store.dismissError()
        await store.search("album")
        #expect(store.albums.count == 1 && store.errorMessage == nil)
    }

    @Test("Helper validates context before database capture and preserves unstarted cache behavior")
    func contextFoundation() async throws {
        let store = LibraryStore()
        try await store.reload()
        await store.search("not started")
        #expect(store.errorMessage == nil && !store.isReady)
        do { try await store.withCatalogueUse { _, _ in throw Harness.expected }; Issue.record("Missing database admitted") }
        catch { #expect(error as? DatabaseError != nil) }
        let foreign = CatalogueAdmission()
        let ended = try await foreign.withOperation { context in
            do { try await store.withCatalogueUse(using: context) { _, _ in _ = Issue.record("Foreign scope admitted") } }
            catch { #expect(error as? CatalogueAdmission.Failure == .invalidContext) }
            return context
        }
        do { try await store.withCatalogueUse(using: ended) { _, _ in _ = Issue.record("Expired scope admitted") } }
        catch { #expect(error as? CatalogueAdmission.Failure == .invalidContext) }
        #expect(store.catalogueAdmission.activeOperationCount == 0)
    }

    @Test("Detail edits drain through refresh and closed admission prevents catalogue changes")
    func detailEditDrain() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let store = LibraryStore(database: fixture.database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        await store.search("album")
        probe.holdNext = true
        let edit = Task {
            try await store.addTrackContributor(trackID: fixture.track.id, name: "Fixture conductor", role: .conductor, creditedName: nil)
        }
        try await until { probe.gate.started }
        #expect(store.catalogueAdmission.activeOperationCount == 1)
        let revision = try await fixture.database.currentRevision()
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.addDisc(albumID: fixture.album.id, title: "Refused disc")
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.updateTrack(fixture.track.id, draft: .init(title: "Refused track edit"))
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.addAlbumAlias(albumID: fixture.album.id, name: "Refused alias", kind: .alternate, locale: nil)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.addAlbumContributor(albumID: fixture.album.id, name: "Refused contributor", role: .composer, creditedName: nil)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.trackContributors(trackID: fixture.track.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.albumAliases(albumID: fixture.album.id)
        }
        #expect(try await fixture.database.currentRevision() == revision)
        #expect(try await fixture.database.contributors().map(\.name) == ["Fixture conductor"])
        #expect(!maintenance.started)
        probe.gate.open()
        try await edit.value
        try await until { maintenance.started }
        maintenance.open()
        try await barrier.value

        let credits = try await store.trackContributors(trackID: fixture.track.id)
        let credit = try #require(credits.first)
        #expect(credits.count == 1 && credit.role == .conductor)
        try await store.updateTrackContributorCredit(credit, in: fixture.track.id, creditedName: "Updated credit")
        #expect(try await store.trackContributors(trackID: fixture.track.id).first?.creditedName == "Updated credit")
        try await store.addAlbumAlias(albumID: fixture.album.id, name: "Alternate album", kind: .alternate, locale: nil)
        #expect(try await store.albumAliases(albumID: fixture.album.id).count == 1)
        #expect(store.catalogueAdmission.activeOperationCount == 0)
    }

    @Test("Location creation returns its published record after draining and placement operations refuse new admission")
    func placementDrain() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let store = LibraryStore(database: fixture.database, albumSearch: { db, term in try await probe.load(db, term) })
        let shelf = try await store.addLocation(.init(name: "Shelf"))
        try await store.addBoxSet(.init(title: "Fixture box", physicalLocationID: shelf.id))
        let box = try #require(store.boxSets.first)
        await store.search("album")

        probe.holdNext = true
        let creation = Task { try await store.addLocation(.init(name: "Second shelf")) }
        try await until { probe.gate.started }
        let revision = try await fixture.database.currentRevision()
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.renameLocation(shelf.id, to: "Refused name")
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.addBoxSet(.init(title: "Refused box", physicalLocationID: shelf.id))
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.moveAlbum(fixture.album.id, to: box.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.boxPlacement(for: fixture.album.id)
        }
        #expect(try await fixture.database.currentRevision() == revision)
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        probe.gate.open()
        let created = try await creation.value
        try await until { maintenance.started }
        #expect(store.locations.contains { $0.id == created.id && $0.name == created.name })
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.boxMembers(of: box.id)
        }
        maintenance.open()
        try await barrier.value

        try await store.updateAlbum(fixture.album.id, with: .init(title: fixture.album.title, hasCD: true, physicalLocationID: shelf.id))
        try await store.moveAlbum(fixture.album.id, to: box.id)
        #expect(try await store.boxPlacement(for: fixture.album.id) != nil)
        #expect(store.boxAlbumIDs[box.id] == [fixture.album.id])
        try await store.removeAlbum(fixture.album.id, from: box.id, assigning: created.id, locationUnknown: false)
        #expect(try await store.boxMembers(of: box.id).isEmpty)
        #expect(store.catalogueAlbums.first?.physicalLocationID == created.id)
    }

    @Test("Playlist batch addition drains through refresh and remains safe to retry")
    func playlistBatchDrain() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let store = LibraryStore(database: fixture.database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.addPlaylist(name: "Listening")
        let playlist = try #require(store.playlists.first)
        await store.search("album")
        let additions = (0..<2).map { _ in PlaylistTrackAddition(trackID: fixture.track.id) }
        let before = try await fixture.database.currentRevision()

        probe.holdNext = true
        let batch = Task { try await store.addTracks(additions, toPlaylist: playlist.id) }
        try await until { probe.gate.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        let expectedIDs = additions.map(\.id)
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.movePlaylistItem(expectedIDs[1], in: playlist.id, before: expectedIDs[0], expectedItemIDs: expectedIDs)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.renamePlaylist(playlist.id, to: "Refused rename")
        }
        #expect(try await fixture.database.playlistItems(playlistID: playlist.id).map(\.id) == expectedIDs)
        #expect(try await fixture.database.currentRevision() == before + 1)
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        probe.gate.open()
        try await batch.value
        try await until { maintenance.started }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.playlistItems(playlist.id)
        }
        #expect(store.playlistContents[playlist.id]?.map(\.id) == expectedIDs)
        maintenance.open()
        try await barrier.value

        try await store.addTracks(additions, toPlaylist: playlist.id)
        #expect(try await fixture.database.currentRevision() == before + 1)
        #expect(try await store.playlistItems(playlist.id).map(\.id) == expectedIDs)
        try await store.movePlaylistItem(expectedIDs[1], in: playlist.id, before: expectedIDs[0], expectedItemIDs: expectedIDs)
        #expect(try await store.playlistItems(playlist.id).map(\.id) == Array(expectedIDs.reversed()))
    }

    @Test("Album deletion drains through refresh and preserves lyrics for restoration")
    func albumDeletionDrain() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let store = LibraryStore(database: fixture.database, albumSearch: { db, term in try await probe.load(db, term) })
        let entry = LyricsEntry(trackID: fixture.track.id, text: "Fixture lyrics")
        try await store.saveLyrics(entry)
        await store.search("album")
        let before = try await fixture.database.currentRevision()

        probe.holdNext = true
        let deletion = Task { try await store.softDeleteAlbum(fixture.album.id) }
        try await until { probe.gate.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.restoreAlbum(fixture.album.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.permanentlyDeleteAlbum(fixture.album.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.deleteLyrics(entry.id)
        }
        #expect(try await fixture.database.currentRevision() == before + 1)
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        probe.gate.open()
        try await deletion.value
        try await until { maintenance.started }
        #expect(store.albums.isEmpty && store.deletedAlbums.map(\.id) == [fixture.album.id])
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.lyrics(trackID: fixture.track.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.nowPlayingLyrics(trackID: fixture.track.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.embeddedMetadata(trackID: fixture.track.id)
        }
        maintenance.open()
        try await barrier.value

        try await store.restoreAlbum(fixture.album.id)
        #expect(store.albums.map(\.id) == [fixture.album.id])
        #expect(try await store.nowPlayingLyrics(trackID: fixture.track.id)?.entries.map(\.id) == [entry.id])
        try await store.deleteLyrics(entry.id)
        #expect(try await store.lyrics(trackID: fixture.track.id).isEmpty)
    }

    @Test("Playback retains admission across root refresh and nested reads", arguments: [false, true])
    func playbackDrain(playlist: Bool) async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let root = try await fixture.database.createStorageRoot(.init(
            displayName: "Synthetic root",
            lastKnownPath: fixture.directory.path,
            bookmarkData: nil,
            status: .available
        ))
        let emptyDisc = try await fixture.database.createDisc(albumID: fixture.album.id)
        let queue = try await fixture.database.createPlaylist(name: "Listening")
        try await fixture.database.addTrack(fixture.track.id, to: queue.id)
        let store = LibraryStore(database: fixture.database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        await store.search("album")

        probe.holdNext = true
        let lookup = Task {
            if playlist {
                do {
                    _ = try await store.playbackURLs(playlistID: queue.id)
                    Issue.record("A playlist without audio should refuse playback")
                } catch DatabaseError.invalidOperation(let message) {
                    #expect(message == "This playlist has no currently playable tracks.")
                }
            } else {
                #expect(try await store.playbackURLs(discID: emptyDisc.id).isEmpty)
            }
        }
        try await until { probe.gate.started }
        #expect(store.storageRoots.first { $0.id == root.id }?.status == .permissionRequired)
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }

        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.playbackAlbumIDs(trackIDs: [fixture.track.id])
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.availableTrackIDs(albumID: fixture.album.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.playbackURL(for: fixture.track.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.refreshStorageRootAccess()
        }
        #expect(await store.playbackURLs(trackIDs: [fixture.track.id]).isEmpty)
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        probe.gate.open()
        try await lookup.value
        try await until { maintenance.started }
        maintenance.open()
        try await barrier.value
        #expect(try await store.playbackAlbumIDs(trackIDs: [fixture.track.id]) == [fixture.track.id: fixture.album.id])
    }

    @Test("Library health drains through root and availability refresh before maintenance")
    func libraryHealthDrain() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let root = try await fixture.database.createStorageRoot(.init(
            displayName: "Synthetic root",
            lastKnownPath: fixture.directory.path,
            bookmarkData: nil,
            status: .available
        ))
        let store = LibraryStore(database: fixture.database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        await store.search("album")
        let before = try await store.folderRecoveryManifest(rootID: root.id)
        let requestsBeforeRefresh = probe.requests

        probe.holdNext = true
        let health = Task { try await store.recheckLibraryHealth() }
        try await until { probe.gate.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.renameStorageRoot(root.id, to: "Refused rename")
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.updateStorageRootScope(root.id, to: .nasPublished)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.deleteStorageRoot(root.id)
        }
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        probe.gate.open()
        try await health.value
        try await until { maintenance.started }
        #expect(probe.requests == requestsBeforeRefresh + 2)
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.folderRecoveryManifest(rootID: root.id)
        }
        maintenance.open()
        try await barrier.value

        let refreshed = try await store.folderRecoveryManifest(rootID: root.id)
        #expect(refreshed.catalogueRevision == before.catalogueRevision + 1)
        #expect(refreshed.root.status == .permissionRequired)
        #expect(refreshed.root.displayName == before.root.displayName && refreshed.root.scope == before.root.scope)
        #expect(refreshed.references == before.references)
        try await store.renameStorageRoot(root.id, to: "Renamed root")
        #expect(try await store.folderRecoveryManifest(rootID: root.id).root.displayName == "Renamed root")
    }

    @Test("Fingerprint verification holds admission through the worker and final refresh")
    func fingerprintDrain() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let worker = Gate(), maintenance = Gate(), probe = Probe()
        defer { worker.open(); probe.gate.open(); maintenance.open() }
        let store = LibraryStore(database: fixture.database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        await store.search("album")
        let revision = try await fixture.database.currentRevision()

        let verification = Task {
            try await store.verifyFingerprints { jobs in
                await Task.detached {
                    #expect(jobs.isEmpty)
                    await worker.hold()
                    return []
                }.value
            }
        }
        try await until { worker.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.verifyFingerprints()
        }
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)

        probe.holdNext = true
        worker.open()
        try await until { probe.gate.started }
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        probe.gate.open()
        try await verification.value
        try await until { maintenance.started }
        #expect(try await fixture.database.currentRevision() == revision)
        maintenance.open()
        try await barrier.value
        #expect(store.catalogueAdmission.phase == .open)
    }

    @Test("Scan cancellation retains admission until worker exit and batch publication")
    func scanWorkerDrain() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let worker = Gate(), maintenance = Gate()
        defer { worker.open(); maintenance.open() }
        let root = try await fixture.database.createStorageRoot(.init(
            displayName: "Fixture root", lastKnownPath: fixture.directory.path, bookmarkData: nil, status: .available
        ))
        let batch = try await fixture.database.createImportBatch(storageRootID: root.id, sourceDescription: fixture.directory.path)
        let store = LibraryStore(database: fixture.database)
        try await store.reload()
        let context = try store.catalogueAdmission.beginOperation()
        store.registerImportScan(batchID: batch.id, database: fixture.database, context: context) {
            await worker.hold()
            #expect(Task.isCancelled)
            do {
                try await fixture.database.finishImportBatch(batch.id, status: .cancelled)
            } catch {
                Issue.record("Could not finish fixture scan: \(error)")
            }
        }
        try await until { worker.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in
            #expect(store.importBatches.first { $0.id == batch.id }?.status == .cancelled)
            #expect(store.importScanProgress[batch.id] == nil)
            await maintenance.hold()
        } }
        try await until { store.catalogueAdmission.phase == .draining }

        await store.cancelImportScan(batch.id)
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.startImportScan(rootID: root.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.startImportScan(containing: fixture.directory)
        }
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        worker.open()
        try await until { maintenance.started }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.retryImportScan(batch.id)
        }
        maintenance.open()
        try await barrier.value

        // Setup cannot reach the scanner without a grant, and the failure must release the lease.
        await #expect(throws: DatabaseError.self) {
            _ = try await store.retryImportScan(batch.id)
        }
        #expect(store.catalogueAdmission.activeOperationCount == 0)
        #expect(try await fixture.database.importBatches().map(\.id) == [batch.id])
    }

    @Test("Import analysis retains admission through root refresh and releases it on access failure")
    func importAnalysisDrain() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let root = try await fixture.database.createStorageRoot(.init(
            displayName: "Fixture root", lastKnownPath: fixture.directory.path, bookmarkData: nil, status: .available
        ))
        let batch = try await fixture.database.createImportBatch(storageRootID: root.id, sourceDescription: fixture.directory.path)
        let store = LibraryStore(database: fixture.database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        await store.search("album")

        probe.holdNext = true
        let analysis = Task { try await store.analyzeImportBatch(batch.id) }
        try await until { probe.gate.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.analyzeImportBatch(batch.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.importCandidates(batchID: batch.id)
        }
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)

        probe.gate.open()
        do {
            try await analysis.value
            Issue.record("Analysis unexpectedly succeeded without root access")
        } catch DatabaseError.invalidOperation(let message) {
            #expect(message == "The source storage root is not available.")
        }
        try await until { maintenance.started }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.importReleaseProposals(batchID: batch.id)
        }
        maintenance.open()
        try await barrier.value

        #expect(store.catalogueAdmission.activeOperationCount == 0)
        #expect(try await store.unregisteredImportCandidates(batchID: batch.id).isEmpty)
        #expect(try await store.importReleaseProposals(batchID: batch.id).isEmpty)
    }

    @Test("Proposal confirmation keeps admission through artwork lookup and publication")
    func proposalConfirmationDrain() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let database = fixture.database
        let proposal = try await fixture.makeImportProposal()
        let store = LibraryStore(database: database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        await store.search("album")
        let preview = try await store.importProposalPreview(proposal)
        #expect(preview.trackTitles == ["Fixture track"] && preview.artworkURL == nil)

        probe.holdNext = true
        let confirmation = Task { try await store.confirmImportReleaseProposal(proposal.id) }
        try await until { probe.gate.started }
        let committedRevision = try await database.currentRevision()
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.setImportReleaseProposal(proposal.id, status: .dismissed)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.attachImportReleaseProposal(proposal.id, to: fixture.album.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.importProposalPreview(proposal)
        }
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        #expect(try await database.currentRevision() == committedRevision)

        probe.gate.open()
        let albumID = try await confirmation.value
        try await until { maintenance.started }
        #expect(store.albums.contains { $0.id == albumID && $0.title == "Imported album" })
        maintenance.open()
        try await barrier.value
        #expect(try await store.confirmImportReleaseProposal(proposal.id) == albumID)
        #expect(try await database.currentRevision() == committedRevision)
    }

    @Test("Import metadata application drains through managed cover download and publication", arguments: [200, 404])
    func externalMetadataDrain(status: Int) async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let database = fixture.database
        let proposal = try await fixture.makeImportProposal()
        let albumID = try await database.confirmImportReleaseProposal(proposal.id)
        let download = Gate(), maintenance = Gate(), probe = Probe()
        defer { download.open(); maintenance.open(); probe.gate.open() }
        let artwork = ManagedArtworkStore(directory: fixture.directory.appending(path: "Artwork"))
        let cover = Data([0x01, 0x02, 0x03])
        let release = ExternalReleasePreview(
            id: UUID().uuidString.lowercased(), title: "Provider title", artist: "Provider artist",
            releaseDate: nil, countryCode: nil, catalogueNumber: nil, mediaCount: 1
        )
        let store = LibraryStore(
            database: database, albumSearch: { db, term in try await probe.load(db, term) },
            managedArtworkStore: artwork,
            coverDownload: { request in
                guard await !download.started else { throw Harness.expected }
                let url = try #require(request.url)
                #expect(url == release.coverArtworkURL)
                await download.hold()
                let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
                return (cover, response)
            }
        )
        try await store.reload()
        await store.search("album")
        try await store.saveMusicBrainzSelection(release, for: proposal.id)
        let selection = try #require(await store.externalMetadataSelection(for: proposal.id))
        let fields = ExternalMetadataFieldSelection(title: true, artist: false, discCount: false, frontArtwork: true)
        let revision = try await database.currentRevision()
        probe.holdNext = true
        let application = Task { try await store.applyExternalMetadataSelection(selection, fields: fields) }
        try await until { download.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }

        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.saveMusicBrainzSelection(release, for: proposal.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.applyExternalMetadataSelection(selection, fields: fields)
        }
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        #expect(try await database.currentRevision() == revision)
        #expect(!FileManager.default.fileExists(atPath: artwork.directory.path))
        #expect(store.albumFrontArtworkPaths[albumID] == nil)

        download.open()
        if status == 200 {
            try await until { probe.gate.started }
            #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)

            probe.gate.open()
            try await application.value
            let path = try #require(store.albumFrontArtworkPaths[albumID])
            let coverURL = URL(fileURLWithPath: path)
            #expect(artwork.contains(coverURL))
            #expect(try Data(contentsOf: coverURL) == cover)
            #expect(try await database.externalMetadataSelection(importProposalID: proposal.id)?.artworkLocalPath == path)
            let applied = try #require(await database.importReleaseProposals(batchID: proposal.batchID).first)
            #expect(applied.title == release.title && applied.artist == proposal.artist)
        } else {
            await #expect(throws: DatabaseError.self) { try await application.value }
            #expect(try await database.currentRevision() == revision)
            #expect(try await database.externalMetadataSelection(importProposalID: proposal.id) == selection)
            #expect(try await database.importReleaseProposals(batchID: proposal.batchID).first?.title == proposal.title)
            #expect(!probe.gate.started && !FileManager.default.fileExists(atPath: artwork.directory.path))
        }

        try await until { maintenance.started }
        #expect(store.catalogueAdmission.activeOperationCount == 0)
        maintenance.open()
        try await barrier.value
    }

    @Test("Album creation holds admission through cover download, commit and cleanup", arguments: [false, true])
    func albumCreationDrain(invalidBox: Bool) async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let database = fixture.database
        let download = Gate(), maintenance = Gate(), probe = Probe()
        defer { download.open(); maintenance.open(); probe.gate.open() }
        let artwork = ManagedArtworkStore(directory: fixture.directory.appending(path: "Artwork"))
        let cover = Data([0x01, 0x02, 0x03])
        let legacyURL = fixture.directory.appending(path: "legacy.jpg")
        try cover.write(to: legacyURL)
        let legacy = try await database.addAlbumArtwork(albumID: fixture.album.id, localPath: legacyURL.path)
        let releaseID = UUID().uuidString.lowercased()
        let coverURL = try #require(URL(string: "https://coverartarchive.org/release/\(releaseID)/front"))
        let store = LibraryStore(
            database: database, albumSearch: { db, term in try await probe.load(db, term) },
            managedArtworkStore: artwork,
            coverDownload: { request in
                #expect(request.url == coverURL)
                #expect(request.value(forHTTPHeaderField: "Accept") == "image/*")
                await download.hold()
                let response = try #require(HTTPURLResponse(url: coverURL, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (cover, response)
            }
        )
        try await store.reload()
        await store.search("album")
        let revision = try await database.currentRevision()
        probe.holdNext = true
        let creation = Task {
            try await store.addAlbum(
                .init(title: "Physical album", hasCD: true, isPhysicalLocationUnknown: true),
                toBoxSet: invalidBox ? BoxSetID() : nil, musicBrainzArtworkURL: coverURL, musicBrainzReleaseID: releaseID
            )
        }
        try await until { download.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }

        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.addAlbum(.init(title: "Must refuse"))
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.addAlbumArtwork(albumID: fixture.album.id, from: legacyURL, role: .front)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.migrateArtworkToManagedStorage(legacy)
        }
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        #expect(try await database.currentRevision() == revision)

        download.open()
        if invalidBox {
            await #expect(throws: DatabaseError.self) { _ = try await creation.value }
            #expect(try await database.currentRevision() == revision)
            #expect(try FileManager.default.contentsOfDirectory(atPath: artwork.directory.path).isEmpty)
            #expect(!probe.gate.started)
        } else {
            try await until { probe.gate.started }
            #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
            probe.gate.open()
            let album = try await creation.value
            #expect(store.albums.contains { $0.id == album.id })
            #expect(store.albumMusicBrainzReleaseIDs[album.id] == releaseID)
            let path = try #require(store.albumFrontArtworkPaths[album.id])
            let managedURL = URL(fileURLWithPath: path)
            #expect(artwork.contains(managedURL))
            #expect(try Data(contentsOf: managedURL) == cover)
        }

        try await until { maintenance.started }
        #expect(store.catalogueAdmission.activeOperationCount == 0)
        #expect(try Data(contentsOf: legacyURL) == cover)
        maintenance.open()
        try await barrier.value
    }

    @Test("Missing asset decisions retain admission through refresh and preserve the track", arguments: [false, true])
    func missingAssetDecisionDrain(removeReference: Bool) async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let database = fixture.database
        let (albumID, assetID) = try await fixture.makeImportedAsset()
        let rootID = try await database.storageRootID(for: assetID)
        let rescan = try await database.createImportBatch(storageRootID: rootID, sourceDescription: fixture.directory.path)
        try await database.finishImportBatch(rescan.id, status: .completed)
        try await database.reconcileCompletedScan(batchID: rescan.id, rootID: rootID, discoveredRelativePaths: [])
        let disc = try #require(await database.discs(albumID: albumID).first)
        let track = try #require(await database.tracks(discID: disc.id).first)
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let store = LibraryStore(database: database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        await store.search("album")
        #expect(try await store.missingAssetReviews(batchID: rescan.id).map(\.id) == [assetID])
        let revision = store.catalogueRevision

        probe.holdNext = true
        let decision = Task {
            if removeReference {
                try await store.removeMissingAssetReference(assetID, in: rescan.id)
            } else {
                try await store.confirmAssetMissing(assetID, in: rescan.id)
            }
        }
        try await until { probe.gate.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.confirmAssetMissing(assetID, in: rescan.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.removeMissingAssetReference(assetID, in: rescan.id)
        }
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        #expect(try await database.currentRevision() == revision + 1)

        probe.gate.open()
        try await decision.value
        try await until { maintenance.started }
        #expect(store.catalogueRevision == revision + 1)
        maintenance.open()
        try await barrier.value
        #expect(try await store.missingAssetReviews(batchID: rescan.id).isEmpty)
        #expect(try await store.tracks(discID: disc.id).map(\.id) == [track.id])
        #expect(try await database.digitalAssetIDs(albumID: albumID) == (removeReference ? [] : [assetID]))
        #expect(try await database.playbackAsset(trackID: track.id)?.availability == (removeReference ? nil : .missing))
    }

    @Test("Relink operations drain through root refresh and preserve the old path without access", arguments: [false, true])
    func relinkDrain(apply: Bool) async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let database = fixture.database
        let (_, assetID) = try await fixture.makeImportedAsset()
        let replacement = fixture.directory.appending(path: "replacement.flac")
        let proposal = try await database.proposeRelink(assetID: assetID, proposedRelativePath: replacement.lastPathComponent)
        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let store = LibraryStore(database: database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        await store.search("album")

        probe.holdNext = true
        let relink = Task {
            if apply {
                try await store.applyRelinkProposal(proposal.id)
            } else {
                try await store.proposeRelink(assetID: assetID, replacementURL: replacement)
            }
        }
        try await until { probe.gate.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.applyRelinkProposal(proposal.id)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.proposeRelink(assetID: assetID, replacementURL: replacement)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.discardRelinkProposal(proposal.id)
        }
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)

        probe.gate.open()
        await #expect(throws: DatabaseError.self) { try await relink.value }
        try await until { maintenance.started }
        #expect(store.storageRoots.first?.status == .permissionRequired)
        #expect(store.relinkProposals.map(\.id) == [proposal.id])
        #expect(try await database.assetFingerprintCandidates().first?.relativePath == "fixture.flac")
        maintenance.open()
        try await barrier.value

        try await store.discardRelinkProposal(proposal.id)
        #expect(store.relinkProposals.isEmpty)
        #expect(try await database.assetFingerprintCandidates().first?.relativePath == "fixture.flac")
    }

    @Test("Tag preview drains through root refresh and blocks new previews and exports")
    func previewsAndExportsDrain() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let database = fixture.database
        let (albumID, _) = try await fixture.makeImportedAsset()
        let album = try #require(await database.album(id: albumID))
        let disc = try #require(await database.discs(albumID: albumID).first)
        let tracks = try await database.tracks(discID: disc.id)
        _ = try await database.createContributor(.init(name: "Unused credit"))
        let jsonURL = fixture.directory.appending(path: "catalogue.json")
        let csvURL = fixture.directory.appending(path: "catalogue.csv")
        try "Existing export".write(to: jsonURL, atomically: true, encoding: .utf8)

        let probe = Probe(), maintenance = Gate()
        defer { probe.gate.open(); maintenance.open() }
        let store = LibraryStore(database: database, albumSearch: { db, term in try await probe.load(db, term) })
        try await store.reload()
        await store.search("album")
        probe.holdNext = true
        let preview = Task {
            try await store.tagWritePreviews(
                album: album, discs: [disc], tracksByDisc: [disc.id: tracks], albumCredits: [], trackCredits: [:]
            )
        }
        try await until { probe.gate.started }
        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.tagWritePreviews(album: album, discs: [], tracksByDisc: [:], albumCredits: [], trackCredits: [:])
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.catalogueCleanupPreview()
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.exportCatalogue(to: jsonURL)
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.exportCatalogueCSV(to: csvURL)
        }
        #expect(try String(contentsOf: jsonURL, encoding: .utf8) == "Existing export")
        #expect(!FileManager.default.fileExists(atPath: csvURL.path))
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)

        probe.gate.open()
        await #expect(throws: DatabaseError.invalidOperation("The asset's storage root is unavailable.")) {
            _ = try await preview.value
        }
        try await until { maintenance.started }
        #expect(store.catalogueAdmission.activeOperationCount == 0)
        maintenance.open()
        try await barrier.value

        let revision = try await database.currentRevision()
        let cleanup = try await store.catalogueCleanupPreview()
        #expect(cleanup.orphanContributorCount == 1)
        try await store.exportCatalogue(to: jsonURL)
        try await store.exportCatalogueCSV(to: csvURL)
        let exports = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any]
        let albums = try #require(exports?["albums"] as? [[String: Any]])
        #expect(albums.contains { $0["title"] as? String == album.title })
        #expect(try String(contentsOf: csvURL, encoding: .utf8).contains(album.title))
        #expect(try await database.currentRevision() == revision)
    }

    @Test("Queued backup admits after its turn and drains through the detached worker")
    func queuedCaptureDrain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "QueuedCapture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        let album = try await store.addAlbum(.init(title: "Captured album"))
        let revision = store.catalogueRevision
        let earlierTurn = Gate(), capture = Gate(), maintenance = Gate()
        defer { earlierTurn.open(); capture.open(); maintenance.open() }

        let earlier = Task { try await store.transferQueue.run(.sharing) { await earlierTurn.hold() } }
        try await until { earlierTurn.started }
        let backup = Task {
            try await store.createMasterBackupNow { database, archive in
                await capture.hold()
                return try await MasterBackupArchive.create(database: database, in: archive)
            }
        }
        try await until { store.transferActivity.waiting == [.databaseBackup] }
        #expect(store.catalogueAdmission.activeOperationCount == 0 && !capture.started)

        earlierTurn.open()
        try await earlier.value
        try await until { capture.started }
        #expect(store.transferActivity.active == .databaseBackup)
        let destination = root.appending(path: "Shared")
        let snapshot = Task { try await store.publishSnapshot(to: destination) }
        try await until { store.transferActivity.waiting == [.sharing] }
        #expect(store.catalogueAdmission.activeOperationCount == 1)

        let barrier = Task { try await store.catalogueAdmission.withMaintenance { _ in await maintenance.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        backup.cancel()
        #expect(store.catalogueAdmission.activeOperationCount == 1 && !maintenance.started)
        capture.open()
        try await backup.value
        try await until { maintenance.started }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) { _ = try await snapshot.value }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) { try await store.createMasterBackupNow() }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!store.transferActivity.isBusy)
        maintenance.open()
        try await barrier.value

        let archive = root.appending(path: "MasterBackups")
        let files = try FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil)
        let manifests = files.filter { $0.lastPathComponent.hasSuffix(".manifest.json") }
        #expect(manifests.count == 1)
        let manifestURL = try #require(manifests.first)
        let manifest = try JSONDecoder().decode(MasterBackupManifest.self, from: Data(contentsOf: manifestURL))
        #expect(manifest.revision == revision)
        try await MasterBackupArchive.verify(manifest, in: archive)
        let backupURL = try MasterBackupArchive.validatedBackupURL(for: manifest, in: archive)
        let inspectionURL = root.appending(path: "Backup inspection.sqlite")
        try FileManager.default.copyItem(at: backupURL, to: inspectionURL)
        let copiedCatalogue = try MusicDatabase(url: inspectionURL)
        #expect(try await copiedCatalogue.album(id: album.id)?.title == album.title)
        #expect(try await store.publishSnapshot(to: destination).revision == revision)
    }

    @Test("Complete archive capture drains catalogue work and excludes edits through capture")
    func completeArchiveCaptureDrain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ArchiveCapture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        let album = try await store.addAlbum(.init(title: "Archived album"))
        let cover = root.appending(path: "Artwork/cover.jpg")
        try FileManager.default.createDirectory(at: cover.deletingLastPathComponent(), withIntermediateDirectories: true)
        let coverBytes = Data([1, 2, 3])
        try coverBytes.write(to: cover)
        do {
            let database = try MusicDatabase(url: root.appending(path: "MusicLibrary.sqlite"))
            _ = try await database.addAlbumArtwork(albumID: album.id, localPath: cover.path)
        }
        try await store.reload()

        let admitted = Gate(), capture = Gate()
        defer { admitted.open(); capture.open() }
        let reader = Task { try await store.withCatalogueUse { _, _ in await admitted.hold() } }
        try await until { admitted.started }
        let exports = root.appending(path: "Exports")
        let export = Task { try await store.exportCompleteCatalogueArchive(to: exports) { await capture.hold() } }
        try await until { store.catalogueAdmission.phase == .draining }
        #expect(store.transferActivity.active == .archiveExport && !capture.started)
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.updateAlbum(album.id, with: .init(title: "Refused during drain"))
        }
        #expect(!FileManager.default.fileExists(atPath: exports.path))

        admitted.open()
        try await reader.value
        try await until { capture.started }
        #expect(store.catalogueAdmission.phase == .exclusive)
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.updateAlbum(album.id, with: .init(title: "Refused during capture"))
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.addAlbumArtwork(albumID: album.id, from: cover, role: .front)
        }

        capture.open()
        let archive = try await export.value
        let manifest = try CompleteCatalogueArchive.verify(at: archive)
        let copiedDatabase = archive.appending(path: CompleteCatalogueArchive.databaseFileName)
        let copiedMetadata = try MusicDatabase.standaloneBackupCatalogueMetadata(at: copiedDatabase)
        #expect(manifest.revision == copiedMetadata.revision && manifest.revision == store.catalogueRevision)
        #expect(manifest.artwork.flatMap(\.originalPaths) == copiedMetadata.artworkPaths)
        #expect(copiedMetadata.artworkPaths == [cover.path])
        #expect(try Data(contentsOf: archive.appending(path: "Artwork/cover.jpg")) == coverBytes)
        #expect(store.catalogueAdmission.phase == .open && !store.transferActivity.isBusy)
        try await store.updateAlbum(album.id, with: .init(title: "Changed after capture"))
        #expect(store.catalogueRevision == manifest.revision + 1)
    }

    @Test("Cleanup archives admitted writes and publishes before reopening after cancellation")
    func cleanupDrain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CleanupDrain-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = Gate(), probe = Probe()
        defer { writer.open(); probe.gate.open() }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, albumSearch: { db, term in
            try await probe.load(db, term)
        })
        let original = try await store.addAlbum(.init(title: "Original album"))
        await store.search("album")
        let priorRevision = store.catalogueRevision
        let edit = Task {
            try await store.withCatalogueUse { database, _ in
                await writer.hold()
                _ = try await database.createContributor(.init(name: "Unused credit"))
                return try await database.createAlbum(.init(title: "Late album"))
            }
        }
        try await until { writer.started }
        let archiveParent = root.appending(path: "Recovery/CatalogueArchives/before-cleanup")
        probe.holdNext = true
        let cleanup = Task { try await store.performCatalogueCleanup(.init()) }
        try await until { store.catalogueAdmission.phase == .draining }
        #expect(store.transferActivity.active == .cleanup)
        #expect(!FileManager.default.fileExists(atPath: archiveParent.path))
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.updateAlbum(original.id, with: .init(title: "Refused during drain"))
        }

        writer.open()
        let lateAlbum = try await edit.value
        try await until { probe.gate.started }
        #expect(store.catalogueAdmission.phase == .exclusive)
        #expect(store.contributors.isEmpty)
        #expect(!store.albums.contains { $0.id == lateAlbum.id })
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.catalogueCleanupPreview()
        }
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.updateAlbum(original.id, with: .init(title: "Refused during refresh"))
        }

        cleanup.cancel()
        probe.gate.open()
        let result = try await cleanup.value
        #expect(result.removedContributorCount == 1)
        #expect(store.albums.contains { $0.id == lateAlbum.id })
        #expect(store.catalogueMaintenanceStatus.contains("Removed 1 unused record"))
        #expect(store.catalogueAdmission.phase == .open && !store.transferActivity.isBusy)
        #expect(try await store.catalogueCleanupPreview().totalCount == 0)

        let archive = try #require(FileManager.default.contentsOfDirectory(at: archiveParent, includingPropertiesForKeys: nil).first)
        let manifest = try CompleteCatalogueArchive.verify(at: archive)
        #expect(manifest.revision > priorRevision && store.catalogueRevision == manifest.revision + 1)
        let inspection = root.appending(path: "Cleanup inspection.sqlite")
        try FileManager.default.copyItem(at: archive.appending(path: CompleteCatalogueArchive.databaseFileName), to: inspection)
        let archivedDatabase = try MusicDatabase(url: inspection)
        #expect(try await archivedDatabase.album(id: lateAlbum.id)?.title == lateAlbum.title)
        #expect(try await archivedDatabase.contributors().map(\.name) == ["Unused credit"])
    }

    @Test("Cleanup leaves eligible records alone when the recovery archive fails")
    func cleanupArchiveFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CleanupArchiveFailure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        let album = try await store.addAlbum(.init(title: "Missing cover"))
        do {
            let database = try MusicDatabase(url: root.appending(path: "MusicLibrary.sqlite"))
            _ = try await database.createContributor(.init(name: "Unused credit"))
            _ = try await database.addAlbumArtwork(albumID: album.id, localPath: root.appending(path: "Artwork/missing.jpg").path)
        }
        try await store.reload()
        let revision = store.catalogueRevision
        await #expect(throws: DatabaseError.self) { _ = try await store.performCatalogueCleanup(.init()) }
        #expect(store.catalogueAdmission.phase == .open && !store.transferActivity.isBusy)
        #expect(store.catalogueRevision == revision)
        #expect(try await store.catalogueCleanupPreview().orphanContributorCount == 1)
    }

    @Test("Reset archives admitted edits and publishes before reopening after cancellation")
    func resetDrain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ResetDrain-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = Gate(), probe = Probe()
        defer { writer.open(); probe.gate.open() }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, albumSearch: { db, term in
            try await probe.load(db, term)
        })
        let album = try await store.addAlbum(.init(title: "Original album"))
        await store.search("album")
        let edit = Task {
            try await store.withCatalogueUse { database, _ in
                await writer.hold()
                return try await database.updateAlbum(album.id, with: .init(title: "Edited album"))
            }
        }
        try await until { writer.started }
        probe.holdNext = true
        let reset = Task { try await store.resetCatalogue(confirmation: "RESET") }
        try await until { store.catalogueAdmission.phase == .draining }
        #expect(store.transferActivity.active == .reset)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Recovery").path))
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.addAlbum(.init(title: "Refused during drain"))
        }

        writer.open()
        let edited = try await edit.value
        try await until { probe.gate.started }
        #expect(store.catalogueAdmission.phase == .exclusive)
        #expect(store.catalogueAlbums.isEmpty && store.albums.count == 1)
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            _ = try await store.addAlbum(.init(title: "Refused during refresh"))
        }

        reset.cancel()
        probe.gate.open()
        let archive = try await reset.value
        let manifest = try CompleteCatalogueArchive.verify(at: archive)
        #expect(store.albums.isEmpty && store.catalogueRevision == manifest.revision + 1)
        #expect(store.catalogueMaintenanceStatus.contains("Catalogue reset"))
        #expect(store.catalogueAdmission.phase == .open && !store.transferActivity.isBusy)

        let inspection = root.appending(path: "Reset inspection.sqlite")
        try FileManager.default.copyItem(at: archive.appending(path: CompleteCatalogueArchive.databaseFileName), to: inspection)
        let archivedDatabase = try MusicDatabase(url: inspection)
        #expect(try await archivedDatabase.album(id: album.id)?.title == edited.title)
    }

    @Test("Reset restores displaced artwork on failure or retains it for recovery review", arguments: [false, true])
    func resetArtworkRollback(failRollback: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ResetRollback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, failRecoveryInstallation: true, failRecoveryRollback: failRollback)
        let album = try await store.addAlbum(.init(title: "Original album"))
        let revision = store.catalogueRevision
        let cover = root.appending(path: "Artwork/cover.jpg")
        let coverBytes = Data([1, 2, 3])
        try FileManager.default.createDirectory(at: cover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coverBytes.write(to: cover)

        await #expect(throws: DatabaseError.self) { _ = try await store.resetCatalogue(confirmation: "RESET") }
        #expect(store.catalogueRevision == revision && store.catalogueAlbums.map(\.id) == [album.id])
        #expect(!store.transferActivity.isBusy)
        let archiveParent = root.appending(path: "Recovery/CatalogueArchives/before-reset")
        let archive = try #require(FileManager.default.contentsOfDirectory(at: archiveParent, includingPropertiesForKeys: nil).first)
        #expect(try CompleteCatalogueArchive.verify(at: archive).revision == revision)
        #expect(try Data(contentsOf: archive.appending(path: "Artwork/cover.jpg")) == coverBytes)

        if failRollback {
            #expect(store.catalogueAdmission.phase == .reviewRequired)
            #expect(store.recoveryReviewMessage?.contains(archive.lastPathComponent) == true)
            let displaced = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix("ResetArtwork-") })
            #expect(try Data(contentsOf: displaced.appending(path: "cover.jpg")) == coverBytes)
            await #expect(throws: CatalogueAdmission.Failure.reviewRequired) {
                try await store.updateAlbum(album.id, with: .init(title: "Refused until review"))
            }
        } else {
            #expect(store.catalogueAdmission.phase == .open && store.recoveryReviewMessage == nil)
            #expect(try Data(contentsOf: cover) == coverBytes)
            try await store.updateAlbum(album.id, with: .init(title: "Still editable"))
        }
    }

    @Test("Complete archive restore drains edits and publishes restored search results after cancellation")
    func archiveRestoreDrain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "RestoreDrain-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = Gate(), probe = Probe()
        defer { writer.open(); probe.gate.open() }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, albumSearch: { db, term in
            try await probe.load(db, term)
        })
        let album = try await store.addAlbum(.init(title: "Archived album"))
        let cover = root.appending(path: "Artwork/cover.jpg")
        try FileManager.default.createDirectory(at: cover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: cover)
        let archive = try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
        try await store.updateAlbum(album.id, with: .init(title: "Live album"))
        try Data([2]).write(to: cover)
        await store.search("album")
        let edit = Task {
            try await store.withCatalogueUse { database, _ in
                await writer.hold()
                return try await database.updateAlbum(album.id, with: .init(title: "Last admitted album"))
            }
        }
        try await until { writer.started }
        probe.holdNext = true
        let restore = Task { try await store.restoreCompleteCatalogueArchive(from: archive) }
        try await until { store.catalogueAdmission.phase == .draining }
        #expect(store.transferActivity.active == .archiveRestore)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Recovery").path))
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.updateAlbum(album.id, with: .init(title: "Refused during drain"))
        }

        writer.open()
        let edited = try await edit.value
        try await until { probe.gate.started }
        #expect(store.catalogueAdmission.phase == .exclusive)
        #expect(store.catalogueAlbums.first?.title == "Archived album")
        #expect(store.albums.first?.title == "Live album")
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.updateAlbum(album.id, with: .init(title: "Refused during publication"))
        }

        restore.cancel()
        probe.gate.open()
        try await restore.value
        #expect(store.albums.first?.title == "Archived album")
        #expect(try Data(contentsOf: cover) == Data([1]))
        #expect(store.catalogueAdmission.phase == .open && !store.transferActivity.isBusy)

        let backups = root.appending(path: "Recovery/CatalogueArchives/before-archive-restore")
        let backup = try #require(FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).first)
        _ = try CompleteCatalogueArchive.verify(at: backup)
        #expect(try Data(contentsOf: backup.appending(path: "Artwork/cover.jpg")) == Data([2]))
        let inspection = root.appending(path: "Recovery inspection.sqlite")
        try FileManager.default.copyItem(at: backup.appending(path: CompleteCatalogueArchive.databaseFileName), to: inspection)
        let archivedDatabase = try MusicDatabase(url: inspection)
        #expect(try await archivedDatabase.album(id: album.id)?.title == edited.title)
    }

    @Test("Database-only restore keeps the last admitted edit in recovery and publishes after cancellation")
    func masterRestoreDrain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MasterRestoreDrain-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = Gate(), probe = Probe()
        defer { writer.open(); probe.gate.open() }
        let store = try await LibraryStore(recoveryFixtureDirectory: root, albumSearch: { db, term in
            try await probe.load(db, term)
        })
        let album = try await store.addAlbum(.init(title: "Backed up album"))
        try await store.createMasterBackupNow()
        let backups = root.appending(path: "MasterBackups")
        let manifestURL = try #require(FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasSuffix(".manifest.json") })
        let manifest = try JSONDecoder().decode(MasterBackupManifest.self, from: Data(contentsOf: manifestURL))
        try await store.updateAlbum(album.id, with: .init(title: "Live album"))
        let artwork = root.appending(path: "Artwork/current.jpg")
        try FileManager.default.createDirectory(at: artwork.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2]).write(to: artwork)
        let audio = root.appending(path: "source.flac")
        try Data([3, 4]).write(to: audio)
        await store.search("album")

        let edit = Task {
            try await store.withCatalogueUse { database, _ in
                await writer.hold()
                return try await database.updateAlbum(album.id, with: .init(title: "Last admitted album"))
            }
        }
        try await until { writer.started }
        probe.holdNext = true
        let restore = Task { try await store.restoreMasterBackup(from: manifestURL) }
        try await until { store.catalogueAdmission.phase == .draining }
        #expect(store.transferActivity.active == .databaseRestore)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Recovery").path))
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.updateAlbum(album.id, with: .init(title: "Refused during drain"))
        }

        writer.open()
        let edited = try await edit.value
        try await until { probe.gate.started }
        #expect(store.catalogueAdmission.phase == .exclusive)
        #expect(store.catalogueAlbums.first?.title == "Backed up album" && store.albums.first?.title == "Live album")
        await #expect(throws: CatalogueAdmission.Failure.maintenancePending) {
            try await store.updateAlbum(album.id, with: .init(title: "Refused during refresh"))
        }
        restore.cancel()
        probe.gate.open()
        try await restore.value
        #expect(store.albums.first?.title == "Backed up album")
        #expect(store.catalogueRevision == manifest.revision)
        #expect(store.catalogueAdmission.phase == .open && !store.transferActivity.isBusy)
        #expect(try Data(contentsOf: artwork) == Data([1, 2]))
        #expect(try Data(contentsOf: audio) == Data([3, 4]))
        try await MasterBackupArchive.verify(manifest, in: backups)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "RestoreStaging").path).isEmpty)

        let recovery = root.appending(path: "Recovery")
        let previous = try #require(FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "sqlite" })
        try MusicDatabase.verifyStandaloneBackupFile(at: previous)
        let inspection = root.appending(path: "Database recovery inspection.sqlite")
        try FileManager.default.copyItem(at: previous, to: inspection)
        let recovered = try MusicDatabase(url: inspection)
        #expect(try await recovered.album(id: album.id)?.title == edited.title)
    }

    @Test("Same-revision restore invalidates the previous attachment intent", arguments: [false, true])
    func sameRevisionRestore(archive: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "InstallationIdentity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LibraryStore(recoveryFixtureDirectory: root)
        let installation = store.catalogueInstallationID
        let album = try await store.addAlbum(.init(title: "Attachment target"))
        let proposal = try await store.withCatalogueUse { database, _ in
            try await Fixture.seedImportProposal(database: database, directory: root)
        }
        try await store.reload()
        let revision = store.catalogueRevision
        #expect(store.catalogueInstallationID == installation)
        if archive {
            let saved = try await store.exportCompleteCatalogueArchive(to: root.appending(path: "Exports"))
            try await store.restoreCompleteCatalogueArchive(from: saved)
        } else {
            try await store.createMasterBackupNow()
            let directory = root.appending(path: "MasterBackups")
            let manifest = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasSuffix(".manifest.json") })
            try await store.restoreMasterBackup(from: manifest)
        }

        #expect(store.catalogueRevision == revision)
        #expect(store.catalogueInstallationID != installation)
        await #expect(throws: DatabaseError.invalidOperation("The catalogue changed. Reopen the attachment review before linking files.")) {
            _ = try await store.attachImportReleaseProposal(proposal.id, to: album.id, expectedInstallationID: installation)
        }
        #expect(store.catalogueRevision == revision)
        let preview = try await store.importAttachmentPreview(proposalID: proposal.id, albumID: album.id)
        #expect(preview.isCompatible)
        #expect(try await store.attachImportReleaseProposal(
            proposal.id, to: album.id, expectedInstallationID: store.catalogueInstallationID
        ) == album.id)
    }

    private func until(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw Harness.timeout }
            await Task.yield()
        }
    }
    private enum Harness: Error { case expected, timeout }
    @MainActor private final class Gate {
        var started = false
        private var opened = false
        private var continuation: CheckedContinuation<Void, Never>?
        func hold() async {
            guard !opened else { return }
            await withCheckedContinuation { continuation = $0; started = true }
        }
        func open() { opened = true; let pending = continuation; continuation = nil; pending?.resume() }
    }
    @MainActor private final class Probe {
        let gate = Gate()
        var requests = 0
        var holdNext = false
        var failNext = false
        func load(_ database: MusicDatabase, _ term: String) async throws -> [Album] {
            requests += 1
            if holdNext { holdNext = false; await gate.hold() }
            if failNext { failNext = false; throw Harness.expected }
            return try await database.albums(matching: term)
        }
    }
    private struct Fixture {
        let directory: URL
        let database: MusicDatabase
        let album: Album
        let disc: Disc
        let track: Track
        static func make() async throws -> Self {
            let directory = FileManager.default.temporaryDirectory.appending(path: "StoreAdmission-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
            try await database.migrate()
            let album = try await database.createAlbum(.init(title: "Original album"))
            let disc = try await database.createDisc(albumID: album.id)
            let track = try await database.createTrack(discID: disc.id, draft: .init(title: "Synthetic track"))
            return .init(directory: directory, database: database, album: album, disc: disc, track: track)
        }
        func makeImportProposal() async throws -> ImportReleaseProposal {
            try await Self.seedImportProposal(database: database, directory: directory)
        }

        static func seedImportProposal(database: MusicDatabase, directory: URL) async throws -> ImportReleaseProposal {
            let root = try await database.createStorageRoot(.init(
                displayName: "Fixture root", lastKnownPath: directory.path, bookmarkData: nil, status: .available
            ))
            let batch = try await database.createImportBatch(storageRootID: root.id, sourceDescription: directory.path)
            try await database.recordImportCandidate(batchID: batch.id, payload: .init(
                relativePath: "fixture.flac", fileName: "fixture.flac", contentTypeIdentifier: "org.xiph.flac", fileSize: 1, modifiedAt: nil
            ))
            let candidate = try #require(await database.importCandidates(batchID: batch.id).first)
            try await database.saveEmbeddedMetadata(.init(
                title: "Fixture track", albumTitle: "Imported album", artist: nil, albumArtist: nil,
                discNumber: 1, trackNumber: 1, durationMilliseconds: 1000, rawTags: [:]
            ), for: candidate.id)
            try await database.rebuildImportReleaseProposals(batchID: batch.id, drafts: [
                .init(title: "Imported album", artist: nil, discCount: 1, confidence: 1, candidateIDs: [candidate.id])
            ])
            return try #require(await database.importReleaseProposals(batchID: batch.id).first)
        }
        func makeImportedAsset() async throws -> (AlbumID, DigitalAssetID) {
            let proposal = try await makeImportProposal()
            let albumID = try await database.confirmImportReleaseProposal(proposal.id)
            let assetID = try #require(await database.digitalAssetIDs(albumID: albumID).first)
            return (albumID, assetID)
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
