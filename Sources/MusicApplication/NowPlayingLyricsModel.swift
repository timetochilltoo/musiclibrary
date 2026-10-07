import Combine
import Foundation
import MusicDomain

public struct NowPlayingLyrics: Equatable, Sendable {
    public let track: Track
    public let entries: [LyricsEntry]
    public init(track: Track, entries: [LyricsEntry]) { self.track = track; self.entries = entries }
}

@MainActor
public final class NowPlayingLyricsModel: ObservableObject {
    @Published public private(set) var snapshot: NowPlayingLyrics?
    @Published public private(set) var timelines: [UUID: SynchronizedLyrics] = [:]
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    public private(set) var revision: Int64?
    public private(set) var trackID: TrackID?
    private var generation = 0

    public init() {}

    public func load(trackID: TrackID?, revision: Int64,
                     read: (TrackID) async throws -> NowPlayingLyrics?) async {
        generation += 1
        let request = generation
        snapshot = nil
        timelines = [:]
        errorMessage = nil
        self.revision = revision
        self.trackID = trackID
        guard let trackID else { isLoading = false; return }
        isLoading = true
        do {
            let value = try await read(trackID)
            guard request == generation else { return }
            guard !Task.isCancelled else { isLoading = false; return }
            // Never display a reader response belonging to another track.
            snapshot = value?.track.id == trackID && value?.entries.allSatisfy { $0.trackID == trackID } == true ? value : nil
            for entry in snapshot?.entries ?? [] where entry.kind == .synchronized {
                if let timeline = SynchronizedLyrics(text: entry.text) { timelines[entry.id] = timeline }
            }
            isLoading = false
        } catch {
            guard request == generation else { return }
            guard !Task.isCancelled else { isLoading = false; return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
