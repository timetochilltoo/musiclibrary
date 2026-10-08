import Foundation
import MusicDomain
import MusicPersistence

/// Resolved entries keep playlist identity until the controller's queue is built.
public struct PlaylistPlaybackPlan {
    public typealias QueueItem = (url: URL, trackID: TrackID, title: String, cueStartMilliseconds: Int?, cueEndMilliseconds: Int?)
    public typealias Entry = (itemID: UUID, audio: QueueItem)
    public let items: [QueueItem]
    public let startingIndex: Int

    public init(entries: [Entry], selectedItemID: UUID? = nil) throws {
        guard !entries.isEmpty else { throw DatabaseError.invalidOperation("This playlist has no currently playable tracks.") }
        if let selectedItemID {
            guard let index = entries.firstIndex(where: { $0.itemID == selectedItemID }) else {
                throw DatabaseError.invalidOperation("This playlist entry has no currently playable audio file or is no longer in the playlist.")
            }
            startingIndex = index
        } else { startingIndex = 0 }
        items = entries.map(\.audio)
    }
}
