import Foundation

public final class CompanionPreferenceStore {
    private let url: URL

    private struct Preferences: Codable {
        var favouriteAlbumIDs: [String]
        var recentlyPlayedAlbumIDs: [String]
        var playCountsByAlbumID: [String: Int]
        var resumePositionsByTrackID: [String: Double]

        init(favouriteAlbumIDs: [String] = [], recentlyPlayedAlbumIDs: [String] = [], playCountsByAlbumID: [String: Int] = [:], resumePositionsByTrackID: [String: Double] = [:]) {
            self.favouriteAlbumIDs = favouriteAlbumIDs
            self.recentlyPlayedAlbumIDs = recentlyPlayedAlbumIDs
            self.playCountsByAlbumID = playCountsByAlbumID
            self.resumePositionsByTrackID = resumePositionsByTrackID
        }

        private enum CodingKeys: String, CodingKey { case favouriteAlbumIDs, recentlyPlayedAlbumIDs, playCountsByAlbumID, resumePositionsByTrackID }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            favouriteAlbumIDs = try values.decodeIfPresent([String].self, forKey: .favouriteAlbumIDs) ?? []
            recentlyPlayedAlbumIDs = try values.decodeIfPresent([String].self, forKey: .recentlyPlayedAlbumIDs) ?? []
            playCountsByAlbumID = try values.decodeIfPresent([String: Int].self, forKey: .playCountsByAlbumID) ?? [:]
            resumePositionsByTrackID = try values.decodeIfPresent([String: Double].self, forKey: .resumePositionsByTrackID) ?? [:]
        }
    }

    public init(url: URL) {
        self.url = url
    }

    public func favouriteAlbumIDs() throws -> Set<String> {
        Set(try preferences().favouriteAlbumIDs)
    }

    public func setFavourite(_ isFavourite: Bool, albumID: String) throws {
        var values = try favouriteAlbumIDs()
        if isFavourite { values.insert(albumID) }
        else { values.remove(albumID) }
        var updated = try preferences()
        updated.favouriteAlbumIDs = values.sorted()
        try save(updated)
    }

    public func recentlyPlayedAlbumIDs() throws -> [String] {
        try preferences().recentlyPlayedAlbumIDs
    }

    public func recordPlayed(albumID: String) throws {
        var updated = try preferences()
        updated.recentlyPlayedAlbumIDs.removeAll { $0 == albumID }
        updated.recentlyPlayedAlbumIDs.insert(albumID, at: 0)
        updated.recentlyPlayedAlbumIDs = Array(updated.recentlyPlayedAlbumIDs.prefix(20))
        updated.playCountsByAlbumID[albumID, default: 0] += 1
        try save(updated)
    }

    public func clearRecentlyPlayed() throws {
        var updated = try preferences()
        updated.recentlyPlayedAlbumIDs = []
        try save(updated)
    }

    public func playCountsByAlbumID() throws -> [String: Int] {
        try preferences().playCountsByAlbumID
    }

    public func resumePosition(for trackID: String) throws -> TimeInterval? {
        try preferences().resumePositionsByTrackID[trackID]
    }

    public func setResumePosition(_ position: TimeInterval?, for trackID: String) throws {
        var updated = try preferences()
        guard let position, position > 0 else {
            updated.resumePositionsByTrackID.removeValue(forKey: trackID)
            try save(updated)
            return
        }
        updated.resumePositionsByTrackID[trackID] = position
        try save(updated)
    }

    private func preferences() throws -> Preferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let data = try Data(contentsOf: url)
        if let preferences = try? JSONDecoder().decode(Preferences.self, from: data) { return preferences }
        return .init(favouriteAlbumIDs: try JSONDecoder().decode([String].self, from: data))
    }

    private func save(_ preferences: Preferences) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(preferences).write(to: url, options: .atomic)
    }
}
