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
    public static func publish(json: String, revision: Int64, to directory: URL) throws -> SnapshotManifest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = Data(json.utf8); let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let fileName = "catalogue-\(revision).json"; let temporary = directory.appending(path: ".\(fileName).tmp"); let destination = directory.appending(path: fileName)
        try data.write(to: temporary, options: .atomic); try FileManager.default.moveItem(at: temporary, to: destination)
        let manifest = SnapshotManifest(format: "music-library-snapshot-json-v1", revision: revision, createdAt: Date(), fileName: fileName, sha256: hash)
        let manifestData = try JSONEncoder().encode(manifest); let manifestTemp = directory.appending(path: ".manifest.json.tmp"); try manifestData.write(to: manifestTemp, options: .atomic); let manifestURL = directory.appending(path: "manifest.json"); try? FileManager.default.removeItem(at: manifestURL); try FileManager.default.moveItem(at: manifestTemp, to: manifestURL)
        return manifest
    }
}
