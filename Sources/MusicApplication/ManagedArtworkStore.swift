import Foundation

public struct ManagedArtworkStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Returns whether a file URL is inside this store's directory.
    ///
    /// Both paths are standardized and symlink-resolved so a legacy record
    /// cannot be mistaken for managed artwork merely because it uses a
    /// different spelling of the same path. The directory-boundary check also
    /// avoids treating a sibling such as `Artwork-old` as managed storage.
    public func contains(_ fileURL: URL) -> Bool {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let candidate = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    public func importArtwork(from sourceURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let extensionName = sourceURL.pathExtension.nilIfBlank ?? "image"
        let destination = directory.appending(path: "\(UUID().uuidString.lowercased()).\(extensionName)")
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
