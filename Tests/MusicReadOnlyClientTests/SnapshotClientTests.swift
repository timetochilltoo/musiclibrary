import Foundation
import CryptoKit
import Testing
@testable import MusicReadOnlyClient

@Test("Snapshot client keeps last valid cache when checksum fails")
func snapshotValidation() throws {
    let source = FileManager.default.temporaryDirectory.appending(path: "snapshot-source-\(UUID().uuidString)"); let cache = FileManager.default.temporaryDirectory.appending(path: "snapshot-cache-\(UUID().uuidString)"); defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: cache) }; try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let payload = Data("{}".utf8); try payload.write(to: source.appending(path: "catalogue-1.json")); let good = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(); let manifest = ReadOnlySnapshotManifest(format: "music-library-snapshot-json-v1", revision: 1, fileName: "catalogue-1.json", sha256: good); try JSONEncoder().encode(manifest).write(to: source.appending(path: "manifest.json")); let client = SnapshotClient(cacheDirectory: cache); #expect(try client.update(from: source)); try JSONEncoder().encode(ReadOnlySnapshotManifest(format: manifest.format, revision: 2, fileName: "catalogue-1.json", sha256: "bad")).write(to: source.appending(path: "manifest.json")); #expect(throws: SnapshotClientError.checksumMismatch) { try client.update(from: source) }; #expect(FileManager.default.fileExists(atPath: cache.appending(path: "catalogue-1.json").path))
}
