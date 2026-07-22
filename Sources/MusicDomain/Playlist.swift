import Foundation

public struct Playlist: Identifiable, Equatable, Sendable { public let id: PlaylistID; public let name: String; public init(id: PlaylistID, name: String) { self.id = id; self.name = name } }
public struct PlaylistItem: Identifiable, Equatable, Sendable { public let id: UUID; public let playlistID: PlaylistID; public let trackID: TrackID; public let position: Int; public let title: String; public init(id: UUID, playlistID: PlaylistID, trackID: TrackID, position: Int, title: String) { self.id = id; self.playlistID = playlistID; self.trackID = trackID; self.position = position; self.title = title } }
