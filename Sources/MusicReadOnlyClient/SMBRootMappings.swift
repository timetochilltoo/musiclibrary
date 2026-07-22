import Foundation

public struct SMBRootMapping: Codable, Equatable, Sendable {
    public let publishedRootID: String
    public let localURL: URL
    public let bookmarkData: Data?

    public init(publishedRootID: String, localURL: URL, bookmarkData: Data? = nil) {
        self.publishedRootID = publishedRootID
        self.localURL = localURL
        self.bookmarkData = bookmarkData
    }

    public func resolvedURL() throws -> URL {
        guard let bookmarkData else { return localURL }
        var stale = false
        return try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &stale)
    }
}

public final class SMBRootMappingStore {
    private let url: URL

    public init(url: URL) { self.url = url }

    public func mappings() throws -> [SMBRootMapping] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([SMBRootMapping].self, from: Data(contentsOf: url))
    }

    public func set(_ mapping: SMBRootMapping) throws {
        var values = try mappings()
        values.removeAll { $0.publishedRootID == mapping.publishedRootID }
        values.append(mapping)
        try persist(values)
    }

    public func set(publishedRootID: String, selectedDirectory: URL) throws {
        let bookmark = try selectedDirectory.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        try set(.init(publishedRootID: publishedRootID, localURL: selectedDirectory, bookmarkData: bookmark))
    }

    public func remove(publishedRootID: String) throws {
        try persist(try mappings().filter { $0.publishedRootID != publishedRootID })
    }

    private func persist(_ values: [SMBRootMapping]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: url, options: .atomic)
    }
}
