import Foundation

public struct ManagedArtworkStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
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
