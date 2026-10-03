import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Physical album duplicate suggestions")
struct PhysicalAlbumDuplicateTests {
    @Test("Exact ID wins; identifier plus identity is required and title alone never matches")
    func evidence() {
        let exact = Album(id: AlbumID(), from: .init(title: "Different title"))
        let barcode = Album(id: AlbumID(), from: .init(title: "The Piano", barcode: "0077"))
        let catalogue = Album(id: AlbumID(), from: .init(title: "The Piano", catalogueNumber: "CAT-001"))
        let otherArtist = Album(id: AlbumID(), from: .init(title: "The Piano", barcode: "0077"))
        let titleOnly = Album(id: AlbumID(), from: .init(title: "The Piano"))
        let leadingZeros = Album(id: AlbumID(), from: .init(title: "The Piano", barcode: "77"))
        let albums = [titleOnly, catalogue, otherArtist, barcode, exact, leadingZeros]
        let summaries = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, AlbumBrowseSummary(artist: $0.id == otherArtist.id ? "Other artist" : "Michael Nyman")) })
        let matches = PhysicalAlbumDuplicates.suggestions(title: " the piano ", artist: "Michael Nyman", barcode: "0077", catalogueNumber: "cat 001", releaseID: "release-id", albums: albums, summaries: summaries, releaseIDs: [exact.id: "release-id"])
        #expect(matches.map(\.id) == [exact.id, barcode.id, catalogue.id])
        #expect(matches.map(\.reason) == ["Same MusicBrainz release ID", "Same barcode, title and artist", "Same catalogue number, title and artist"])
    }

    @Test("Selected release ID commits with credits, survives reload, and permits separate editions")
    @MainActor
    func persistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "duplicates-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let store = LibraryStore(database: database)
        let release = "9383A6F5-9607-4A36-9C68-8663AAD3592B"
        let first = try await store.addAlbum(.init(title: "One", hasCD: true, isPhysicalLocationUnknown: true), contributors: [.init(name: "Artist", role: .albumArtist)], musicBrainzReleaseID: release)
        let second = try await store.addAlbum(.init(title: "Two", hasCD: true, isPhysicalLocationUnknown: true), musicBrainzReleaseID: release)
        try await store.reload()
        #expect(store.albumMusicBrainzReleaseIDs == [first.id: release.lowercased(), second.id: release.lowercased()])
        let revision = try await database.currentRevision()
        do {
            _ = try await store.addAlbum(.init(title: "Invalid"), musicBrainzReleaseID: "../invalid")
            Issue.record("Expected invalid release ID rejection")
        } catch {}
        do {
            _ = try await store.addAlbum(.init(title: "Bad box"), toBoxSet: BoxSetID(), contributors: [.init(name: "Must rollback", role: .albumArtist)], musicBrainzReleaseID: release)
            Issue.record("Expected missing box rollback")
        } catch {}
        #expect(try await database.currentRevision() == revision)
        #expect(try await database.albums().count == 2)
        #expect(try await database.musicBrainzReleaseIDs().count == 2)
        #expect(try await database.contributors().map(\.name) == ["Artist"])
        #expect(try await database.discs(albumID: first.id).isEmpty)
    }
}
