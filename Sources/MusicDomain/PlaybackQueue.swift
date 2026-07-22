import Foundation

public enum RepeatMode: String, Codable, CaseIterable, Sendable { case off, all, one }

public struct PlaybackQueue: Codable, Equatable, Sendable {
    public var trackIDs: [TrackID]
    public var currentIndex: Int?
    public var repeatMode: RepeatMode
    public var isShuffled: Bool

    public init(trackIDs: [TrackID] = [], currentIndex: Int? = nil, repeatMode: RepeatMode = .off, isShuffled: Bool = false) { self.trackIDs = trackIDs; self.currentIndex = currentIndex; self.repeatMode = repeatMode; self.isShuffled = isShuffled }
    public var currentTrackID: TrackID? { currentIndex.flatMap { trackIDs.indices.contains($0) ? trackIDs[$0] : nil } }
    public mutating func replace(with ids: [TrackID], startingAt index: Int = 0) { trackIDs = ids; currentIndex = ids.isEmpty ? nil : min(max(0, index), ids.count - 1) }
    public mutating func next() -> TrackID? { guard let index = currentIndex else { return nil }; if repeatMode == .one { return currentTrackID }; if index + 1 < trackIDs.count { currentIndex = index + 1; return currentTrackID }; if repeatMode == .all, !trackIDs.isEmpty { currentIndex = 0; return currentTrackID }; return nil }
    public mutating func previous() -> TrackID? { guard let index = currentIndex else { return nil }; if index > 0 { currentIndex = index - 1; return currentTrackID }; if repeatMode == .all, !trackIDs.isEmpty { currentIndex = trackIDs.count - 1; return currentTrackID }; return nil }
    public mutating func shuffle(using generator: inout some RandomNumberGenerator) { trackIDs.shuffle(using: &generator); currentIndex = trackIDs.isEmpty ? nil : 0; isShuffled = true }
}
