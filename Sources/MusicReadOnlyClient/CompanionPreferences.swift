import Foundation

public final class CompanionPreferenceStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func favouriteAlbumIDs() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: url)))
    }

    public func setFavourite(_ isFavourite: Bool, albumID: String) throws {
        var values = try favouriteAlbumIDs()
        if isFavourite { values.insert(albumID) }
        else { values.remove(albumID) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(values.sorted()).write(to: url, options: .atomic)
    }
}
