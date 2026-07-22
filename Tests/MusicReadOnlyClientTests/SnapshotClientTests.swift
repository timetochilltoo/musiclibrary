import Foundation
import CryptoKit
import Testing
@testable import MusicReadOnlyClient

@Test("Snapshot client keeps last valid cache when checksum fails")
func snapshotValidation() throws {
    let source = FileManager.default.temporaryDirectory.appending(path: "snapshot-source-\(UUID().uuidString)"); let cache = FileManager.default.temporaryDirectory.appending(path: "snapshot-cache-\(UUID().uuidString)"); defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: cache) }; try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let payload = Data("{}".utf8); try payload.write(to: source.appending(path: "catalogue-1.json")); let good = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(); let manifest = ReadOnlySnapshotManifest(format: "music-library-snapshot-json-v1", revision: 1, fileName: "catalogue-1.json", sha256: good); try JSONEncoder().encode(manifest).write(to: source.appending(path: "manifest.json")); let client = SnapshotClient(cacheDirectory: cache); #expect(try client.update(from: source)); try JSONEncoder().encode(ReadOnlySnapshotManifest(format: manifest.format, revision: 2, fileName: "catalogue-1.json", sha256: "bad")).write(to: source.appending(path: "manifest.json")); #expect(throws: SnapshotClientError.checksumMismatch) { try client.update(from: source) }; #expect(FileManager.default.fileExists(atPath: cache.appending(path: "catalogue-1.json").path))
}

@Test("SMB mappings are device-local and replace only the matching published root")
func smbMappings() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "mappings-\(UUID().uuidString).json"); defer { try? FileManager.default.removeItem(at: file) }; let store = SMBRootMappingStore(url: file); try store.set(.init(publishedRootID: "root-a", localURL: URL(fileURLWithPath: "/Volumes/Music"))); try store.set(.init(publishedRootID: "root-a", localURL: URL(fileURLWithPath: "/Volumes/NewMusic"))); #expect(try store.mappings().map(\.localURL.path) == ["/Volumes/NewMusic"])
}

@Test("Snapshot source selection persists separately and can be cleared")
func snapshotSourceSelection() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "selected-source-\(UUID().uuidString)")
    let file = FileManager.default.temporaryDirectory.appending(path: "selected-source-\(UUID().uuidString).bookmark")
    defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: file) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = SnapshotSourceStore(url: file)
    try store.set(selectedDirectory: directory)
    #expect(try store.selectedDirectory()?.standardizedFileURL == directory.standardizedFileURL)
    try store.clear()
    #expect(try store.selectedDirectory() == nil)
}

@Test("Verified local snapshot decodes albums and supports read-only search")
func localCatalogueBrowsing() throws {
    let source = FileManager.default.temporaryDirectory.appending(path: "catalogue-source-\(UUID().uuidString)")
    let cache = FileManager.default.temporaryDirectory.appending(path: "catalogue-cache-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: cache) }
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let payload = ReadOnlyCatalogue(format: "music-library-json", schemaVersion: 7, catalogueRevision: 5, albums: [
        .init(id: "one", title: "宇多田ヒカル", editionLabel: "Japan Remaster", releaseYear: 2004, catalogueNumber: "TOCT-123", hasCD: true, hasDigital: true),
        .init(id: "two", title: "Other", hasCD: false, hasDigital: true)
    ])
    let data = try JSONEncoder().encode(payload)
    try data.write(to: source.appending(path: "catalogue-5.json"))
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let manifest = ReadOnlySnapshotManifest(format: "music-library-snapshot-json-v1", revision: 5, fileName: "catalogue-5.json", sha256: hash)
    try JSONEncoder().encode(manifest).write(to: source.appending(path: "manifest.json"))
    let client = SnapshotClient(cacheDirectory: cache)
    #expect(try client.update(from: source))
    let catalogue = try #require(try client.localCatalogue())
    #expect(catalogue.albums.first?.displayTitle == "宇多田ヒカル — Japan Remaster")
    #expect(catalogue.albums.filter { $0.matches("TOCT") }.map(\.id) == ["one"])
    #expect(catalogue.albums.filter { $0.matches("宇多田") }.map(\.id) == ["one"])
}

@Test("Read-only assets resolve only through matching safe device-local roots")
func rootRelativeAssetResolution() {
    let asset = ReadOnlyDigitalAsset(storageRootID: "root-a", relativePath: "Artist/Album/01.flac", availability: "available")
    let mappings = [SMBRootMapping(publishedRootID: "root-a", localURL: URL(fileURLWithPath: "/Volumes/Music"))]
    #expect(asset.resolve(using: mappings) == .mapped(URL(fileURLWithPath: "/Volumes/Music/Artist/Album/01.flac")))
    #expect(asset.resolve(using: []) == .unmappedRoot)
    #expect(ReadOnlyDigitalAsset(storageRootID: "root-a", relativePath: "../outside.flac", availability: "available").resolve(using: mappings) == .unsafeRelativePath)
    #expect(ReadOnlyDigitalAsset(storageRootID: "root-a", relativePath: "Artist/Album/01.flac", availability: "rootOffline").resolve(using: mappings) == .unavailable("rootOffline"))
}
