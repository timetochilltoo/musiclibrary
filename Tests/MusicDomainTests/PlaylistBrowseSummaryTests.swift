import Foundation
import Testing
@testable import MusicDomain

@Suite("Playlist display summaries")
struct PlaylistBrowseSummaryTests {
    @Test("Recorded status distinguishes no-copy, offline, permission and unavailable without probing files")
    func availability() {
        #expect(TrackAudioStatus.derive(hasAsset: false, asset: nil, root: nil) == .noDigitalCopy)
        #expect(TrackAudioStatus.derive(hasAsset: true, asset: .available, root: .available) == .available)
        #expect(TrackAudioStatus.derive(hasAsset: true, asset: .missing, root: .offline) == .offline)
        #expect(TrackAudioStatus.derive(hasAsset: true, asset: .available, root: .permissionRequired) == .permissionRequired)
        #expect(TrackAudioStatus.derive(hasAsset: true, asset: .rootOffline, root: .available) == .offline)
        #expect(TrackAudioStatus.derive(hasAsset: true, asset: .permissionRequired, root: .available) == .permissionRequired)
        #expect(TrackAudioStatus.derive(hasAsset: true, asset: .missing, root: .available) == .unavailable)
        #expect(TrackAudioStatus.derive(hasAsset: true, asset: .invalid, root: .available) == .unavailable)
        #expect(TrackAudioStatus.derive(hasAsset: true, asset: nil, root: .available) == .unknown)
    }

    @Test("Duration totals count duplicates and label missing data and overflow")
    func duration() {
        let playlistID = PlaylistID(), trackID = TrackID()
        let track = TrackBrowseSummary(id: trackID, albumID: AlbumID(), title: "Track", albumTitle: "Album", discNumber: 1, trackNumber: 1, durationMilliseconds: 123456, audioStatus: .available)
        let entries = (1...2).map { PlaylistItem(id: UUID(), playlistID: playlistID, trackID: trackID, position: $0, title: "Track") }
        let full = PlaylistBrowseSummary(items: entries, tracks: [trackID: track])
        #expect(full.durationLabel == "Duration: 4:06" && full.knownDurationCount == 2)
        #expect(full.availableEntryCount == 2)
        let unknown = PlaylistItem(id: UUID(), playlistID: playlistID, trackID: TrackID(), position: 3, title: "Unknown")
        #expect(PlaylistBrowseSummary(items: entries + [unknown], tracks: [trackID: track]).durationLabel == "Known duration: 4:06 (2/3 entries)")
        #expect(PlaylistBrowseSummary(items: [unknown], tracks: [:]).durationLabel == "Duration not recorded")
        #expect(PlaylistBrowseSummary(items: [], tracks: [:]).durationLabel == nil)
        let huge = TrackBrowseSummary(id: trackID, albumID: track.albumID, title: "Track", albumTitle: "Album", discNumber: 1, trackNumber: 1, durationMilliseconds: Int.max)
        #expect(PlaylistBrowseSummary(items: entries, tracks: [trackID: huge]).totalMilliseconds == nil)
        #expect(huge.durationLabel?.hasPrefix(String((Int.max / 1000) / 60)) == true)
    }
}
