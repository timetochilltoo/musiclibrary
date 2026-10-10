import Foundation
import Testing
@testable import MusicDomain

@Suite("Playlist artwork selection")
struct PlaylistArtworkSelectionTests {
    private func fixture() -> (items: [PlaylistItem], tracks: [TrackID: TrackBrowseSummary], fronts: [AlbumID: String]) {
        let playlistID = PlaylistID()
        let tracks = (1...6).map { number in
            TrackBrowseSummary(id: TrackID(), albumID: AlbumID(), title: "Track \(number)", albumTitle: "Album \(number)", discNumber: 1, trackNumber: 1, durationMilliseconds: nil)
        }
        let items = tracks.enumerated().map { index, track in
            PlaylistItem(id: UUID(), playlistID: playlistID, trackID: track.id, position: index + 1, title: track.title)
        }
        return (items, Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) }), Dictionary(uniqueKeysWithValues: tracks.enumerated().map { ($0.element.albumID, "/fixture/front\($0.offset).jpg") }))
    }

    @Test("First four distinct albums follow displayed entry order, not dictionary order")
    func orderAndLimit() {
        let fixture = fixture()
        let ordered = [fixture.items[4], fixture.items[2], fixture.items[0], fixture.items[5], fixture.items[1]]
        #expect(PlaylistArtworkSelection(items: ordered, tracks: fixture.tracks, frontPaths: fixture.fronts).paths == ["/fixture/front4.jpg", "/fixture/front2.jpg", "/fixture/front0.jpg", "/fixture/front5.jpg"])
    }

    @Test("Repeated entries and different tracks on the same album use one tile")
    func distinctAlbums() {
        var fixture = fixture()
        let original = fixture.tracks[fixture.items[0].trackID]!
        let otherID = TrackID()
        fixture.tracks[otherID] = TrackBrowseSummary(id: otherID, albumID: original.albumID, title: "Other track", albumTitle: original.albumTitle, discNumber: 1, trackNumber: 2, durationMilliseconds: nil)
        let other = PlaylistItem(id: UUID(), playlistID: fixture.items[0].playlistID, trackID: otherID, position: 2, title: "Other track")
        #expect(PlaylistArtworkSelection(items: [fixture.items[0], fixture.items[0], other, fixture.items[1]], tracks: fixture.tracks, frontPaths: fixture.fronts).paths == ["/fixture/front0.jpg", "/fixture/front1.jpg"])
    }

    @Test("Missing metadata and absent or blank fronts are skipped; empty selection stays empty")
    func fallback() {
        var fixture = fixture()
        fixture.tracks.removeValue(forKey: fixture.items[0].trackID)
        fixture.fronts.removeValue(forKey: fixture.tracks[fixture.items[1].trackID]!.albumID)
        fixture.fronts[fixture.tracks[fixture.items[2].trackID]!.albumID] = " \n "
        #expect(PlaylistArtworkSelection(items: fixture.items, tracks: fixture.tracks, frontPaths: fixture.fronts).paths == ["/fixture/front3.jpg", "/fixture/front4.jpg", "/fixture/front5.jpg"])
        #expect(PlaylistArtworkSelection(items: [], tracks: fixture.tracks, frontPaths: fixture.fronts).paths.isEmpty)
        #expect(PlaylistArtworkSelection(items: fixture.items, tracks: fixture.tracks, frontPaths: [:]).paths.isEmpty)
    }
}
