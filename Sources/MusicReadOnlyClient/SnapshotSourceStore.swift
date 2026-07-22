import Foundation

public final class SnapshotSourceStore {
    private let url: URL

    public init(url: URL) { self.url = url }

    public func selectedDirectory() throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bookmarkData = try Data(contentsOf: url)
        var stale = false
        return try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &stale)
    }

    public func set(selectedDirectory: URL) throws {
        let bookmark = try selectedDirectory.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bookmark.write(to: url, options: .atomic)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
