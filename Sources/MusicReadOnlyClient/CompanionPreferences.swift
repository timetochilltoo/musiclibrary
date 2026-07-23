import Foundation

public final class CompanionPreferenceStore {
    private let url: URL

    private struct Preferences: Codable {
        var favouriteAlbumIDs: [String]
        var recentlyPlayedAlbumIDs: [String]
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
        try save(updated)
    }

    public func clearRecentlyPlayed() throws {
        var updated = try preferences()
        updated.recentlyPlayedAlbumIDs = []
        try save(updated)
    }

    private func preferences() throws -> Preferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init(favouriteAlbumIDs: [], recentlyPlayedAlbumIDs: []) }
        let data = try Data(contentsOf: url)
        if let preferences = try? JSONDecoder().decode(Preferences.self, from: data) { return preferences }
        return .init(favouriteAlbumIDs: try JSONDecoder().decode([String].self, from: data), recentlyPlayedAlbumIDs: [])
    }

    private func save(_ preferences: Preferences) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(preferences).write(to: url, options: .atomic)
    }
}
