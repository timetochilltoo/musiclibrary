import CryptoKit
import Foundation

public struct SnapshotManifest: Codable, Sendable {
    public let format: String
    public let revision: Int64
    public let createdAt: Date
    public let fileName: String
    public let sha256: String
}

public enum SnapshotPublisher {
    public static func publish(json: String, revision: Int64, to directory: URL, retainRevisions: Int = 4) throws -> SnapshotManifest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = Data(json.utf8); let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let fileName = "catalogue-\(revision).json"; let temporary = directory.appending(path: ".\(fileName).tmp"); let destination = directory.appending(path: fileName)
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: destination) }
        let manifest = SnapshotManifest(format: "music-library-snapshot-json-v1", revision: revision, createdAt: Date(), fileName: fileName, sha256: hash)
        let manifestData = try JSONEncoder().encode(manifest); let manifestTemp = directory.appending(path: ".manifest.json.tmp"); try manifestData.write(to: manifestTemp, options: .atomic); let manifestURL = directory.appending(path: "manifest.json"); try? FileManager.default.removeItem(at: manifestURL); try FileManager.default.moveItem(at: manifestTemp, to: manifestURL)
        try retainRevisionFiles(in: directory, keeping: max(1, retainRevisions), currentFileName: fileName)
        return manifest
    }

    private static func retainRevisionFiles(in directory: URL, keeping count: Int, currentFileName: String) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("catalogue-") && $0.pathExtension == "json" }
            .sorted { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast > (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        for file in files.dropFirst(count) where file.lastPathComponent != currentFileName { try? FileManager.default.removeItem(at: file) }
    }
}
