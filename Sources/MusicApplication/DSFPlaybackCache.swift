import Foundation

public struct DSFPlaybackCacheStatus: Sendable, Equatable {
    public let usageBytes: Int64
    public let fileCount: Int
    public let maximumBytes: Int64

    public init(usageBytes: Int64, fileCount: Int, maximumBytes: Int64) {
        self.usageBytes = usageBytes
        self.fileCount = fileCount
        self.maximumBytes = maximumBytes
    }
}

public enum DSFPlaybackCachePreferences {
    public static let defaultMaximumGiB = 10
    public static let allowedMaximumGiB = 2...100
    private static let maximumGiBKey = "MusicLibrary.dsfPlaybackCacheMaximumGiB"

    public static func maximumGiB(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: maximumGiBKey) as? Int ?? defaultMaximumGiB
        return min(max(stored, allowedMaximumGiB.lowerBound), allowedMaximumGiB.upperBound)
    }

    public static func setMaximumGiB(_ value: Int, defaults: UserDefaults = .standard) {
        defaults.set(min(max(value, allowedMaximumGiB.lowerBound), allowedMaximumGiB.upperBound), forKey: maximumGiBKey)
    }

    public static func maximumBytes(defaults: UserDefaults = .standard) -> Int64 {
        Int64(maximumGiB(defaults: defaults)) * 1_073_741_824
    }
}

/// Manages only replaceable PCM files created for DSF playback.
/// Source music files and in-progress `.partial` conversions are never removed.
public struct DSFPlaybackCache: Sendable {
    private let configuredDirectoryURL: URL?

    public init(directoryURL: URL? = nil) {
        configuredDirectoryURL = directoryURL
    }

    public func directoryURL(create: Bool = true) throws -> URL {
        let directory: URL
        if let configuredDirectoryURL {
            directory = configuredDirectoryURL
        } else {
            let root = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: create
            )
            directory = root.appending(path: "MusicLibrary/DSFPlayback", directoryHint: .isDirectory)
        }
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    public func status(maximumBytes: Int64 = DSFPlaybackCachePreferences.maximumBytes()) throws -> DSFPlaybackCacheStatus {
        let entries = try cachedPCMEntries()
        return .init(
            usageBytes: entries.reduce(0) { $0 + $1.size },
            fileCount: entries.count,
            maximumBytes: maximumBytes
        )
    }

    @discardableResult
    public func trim(
        toMaximumBytes maximumBytes: Int64 = DSFPlaybackCachePreferences.maximumBytes(),
        excluding protectedURLs: Set<URL> = []
    ) throws -> DSFPlaybackCacheStatus {
        let protectedPaths = Set(protectedURLs.map(canonicalPath))
        var entries = try cachedPCMEntries()
        var usage = entries.reduce(0) { $0 + $1.size }
        guard usage > maximumBytes else {
            return .init(usageBytes: usage, fileCount: entries.count, maximumBytes: maximumBytes)
        }

        entries.sort {
            if $0.lastUsed == $1.lastUsed { return $0.url.lastPathComponent < $1.url.lastPathComponent }
            return $0.lastUsed < $1.lastUsed
        }
        for entry in entries where usage > maximumBytes && !protectedPaths.contains(canonicalPath(entry.url)) {
            try FileManager.default.removeItem(at: entry.url)
            usage -= entry.size
        }
        return try status(maximumBytes: maximumBytes)
    }

    @discardableResult
    public func clear(excluding protectedURLs: Set<URL> = []) throws -> DSFPlaybackCacheStatus {
        let protectedPaths = Set(protectedURLs.map(canonicalPath))
        for entry in try cachedPCMEntries() where !protectedPaths.contains(canonicalPath(entry.url)) {
            try FileManager.default.removeItem(at: entry.url)
        }
        return try status()
    }

    public func markUsed(_ url: URL) throws {
        guard isManagedPCM(url) else { return }
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func cachedPCMEntries() throws -> [CacheEntry] {
        let directory = try directoryURL()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            .compactMap { url in
                guard isManagedPCM(url) else { return nil }
                let values = try url.resourceValues(forKeys: keys)
                guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
                return CacheEntry(
                    url: url,
                    size: Int64(values.fileSize ?? 0),
                    lastUsed: values.contentModificationDate ?? .distantPast
                )
            }
    }

    private func isManagedPCM(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path == (try? directoryURL())?.standardizedFileURL.path &&
            url.pathExtension.caseInsensitiveCompare("wav") == .orderedSame
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private struct CacheEntry {
        let url: URL
        let size: Int64
        let lastUsed: Date
    }
}
