import MusicDomain

/// Resolves labels without accessing source files, preserving actual queue order.
public enum PlaybackQueuePresentation {
    public static func titles(for queue: PlaybackQueue, resolvedTitles: [(TrackID, String)]) -> [String] {
        var titlesByID: [TrackID: String] = [:]
        for (id, title) in resolvedTitles { titlesByID[id] = title }
        return queue.trackIDs.map { titlesByID[$0] ?? "Unavailable track" }
    }
}
