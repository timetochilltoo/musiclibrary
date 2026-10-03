import Foundation
import Testing
import MusicPersistence
@testable import MusicApplication

@Suite("Structured MusicBrainz tracks")
struct MusicBrainzTrackListingTests {
    private func release(_ media: String) throws -> ExternalReleasePreview {
        try MusicBrainzMetadataProvider.decodeReleaseDetail(from: Data("""
        {"id":"9383a6f5-9607-4a36-9c68-8663aad3592b","title":"Two discs","media":\(media)}
        """.utf8))
    }

    @Test("Disc boundaries, printed numbers, pregaps and millisecond lengths survive decoding")
    func complete() throws {
        let preview = try release("""
        [{"position":2,"title":"Bonus","format":"CD","track-count":1,"tracks":[{"position":1,"number":"B1","recording":{"title":"Finale"}}]},
         {"position":1,"format":"CD","track-count":2,"pregap":{"position":0,"number":"00","title":"Hidden"},"tracks":[{"position":2,"number":"A2","title":"Adagio","length":62000},{"position":1,"number":"A1","title":" ","recording":{"title":"Opening"},"length":123456}]}]
        """)
        let discs = try #require(preview.physicalDiscs)
        #expect(discs.map(\.number) == [1, 2])
        #expect(discs[1].title == "Bonus")
        #expect(discs[0].tracks.map(\.number) == [0, 1, 2])
        #expect(discs[0].tracks[1].draft.displayPosition == "A1")
        #expect(discs[0].tracks[1].draft.durationMilliseconds == 123456)
        #expect(discs[0].tracks[1].draft.title == "Opening")
        #expect(discs[1].tracks[0].draft.durationMilliseconds == nil)
    }

    @Test("Partial or ambiguous lists remain inspectable but cannot be imported")
    func incomplete() throws {
        for media in [
            "[]",
            #"[{"format":"CD","track-count":1,"tracks":[{"position":1,"title":"One"}]}]"#,
            #"[{"position":1,"tracks":[{"position":1,"title":"One"}]}]"#,
            #"[{"position":1,"track-count":2,"tracks":[{"position":1,"title":"One"}]}]"#,
            #"[{"position":1,"track-count":2,"tracks":[{"position":1,"title":"One"},{"position":1,"title":"Duplicate"}]}]"#,
            #"[{"position":1,"track-count":1,"tracks":[{"number":"A1","title":"One"}]}]"#,
            #"[{"position":2,"track-count":1,"tracks":[{"position":1,"title":"One"}]}]"#,
            #"[{"position":1,"track-count":1,"tracks":[{"position":1}]}]"#,
            #"[{"position":1,"track-count":1,"tracks":[{"position":1,"title":"One","length":-1}]}]"#,
            #"[{"position":"bad","track-count":"bad","tracks":{}}]"#,
            #"[{"position":1,"track-count":1,"pregap":"bad","tracks":[{"position":1,"title":"One"}]}]"#,
            #"[{"position":1,"track-count":1,"data-track-count":1,"tracks":[{"position":1,"title":"One"}]}]"#
        ] { #expect(try release(media).physicalDiscs == nil) }
    }

    @Test("Search-only flat titles never qualify as complete media")
    func legacy() {
        let preview = ExternalReleasePreview(id: "id", title: "Title", artist: nil, releaseDate: nil, countryCode: nil, catalogueNumber: nil, mediaCount: 1, trackTitles: ["One"])
        #expect(preview.physicalDiscs == nil)
    }

    @Test("The application create use case forwards selected tracks and reloads physical availability")
    @MainActor
    func applicationSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "application-physical-tracks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let store = LibraryStore(database: database)
        let preview = try release(#"[{"position":1,"format":"CD","track-count":1,"tracks":[{"position":1,"number":"01","title":"Opening","length":1000}]}]"#)
        let discs = try #require(preview.physicalDiscs)
        let album = try await store.addAlbum(.init(title: preview.title, hasCD: true, isPhysicalLocationUnknown: true), musicBrainzReleaseID: preview.id, discs: discs)
        #expect(store.catalogueAlbums.map(\.id) == [album.id])
        #expect(store.albumMusicBrainzReleaseIDs[album.id] == preview.id)
        #expect(store.catalogueRevision == 1)
        let savedDiscs = try await database.discs(albumID: album.id)
        #expect(try await database.tracks(discID: savedDiscs[0].id).first?.displayPosition == "01")
        #expect(try await database.digitalAssetIDs(albumID: album.id).isEmpty)
    }
}
