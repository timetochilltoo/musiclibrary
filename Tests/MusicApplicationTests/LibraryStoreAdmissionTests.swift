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
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
