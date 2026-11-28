import Foundation
import CryptoKit
import Testing
@testable import MusicReadOnlyClient

@Test("Companion favourites are device-local and survive reload")
func companionFavourites() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "companion-preferences-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = CompanionPreferenceStore(url: url)
    try store.setFavourite(true, albumID: "album-1")
    try store.setFavourite(true, albumID: "album-2")
    try store.setFavourite(false, albumID: "album-1")
    try store.recordPlayed(albumID: "album-1")
    try store.recordPlayed(albumID: "album-2")
    try store.recordPlayed(albumID: "album-1")
    #expect(try store.favouriteAlbumIDs() == ["album-2"])
    #expect(try CompanionPreferenceStore(url: url).favouriteAlbumIDs() == ["album-2"])
    #expect(try CompanionPreferenceStore(url: url).recentlyPlayedAlbumIDs() == ["album-1", "album-2"])
    #expect(try CompanionPreferenceStore(url: url).playCountsByAlbumID() == ["album-1": 2, "album-2": 1])
    try store.clearRecentlyPlayed()
    #expect(try store.recentlyPlayedAlbumIDs().isEmpty)
    #expect(try store.favouriteAlbumIDs() == ["album-2"])
    #expect(try store.playCountsByAlbumID() == ["album-1": 2, "album-2": 1])
    try store.setResumePosition(42.5, for: "track-1")
    #expect(try store.resumePosition(for: "track-1") == 42.5)
    #expect(try CompanionPreferenceStore(url: url).resumePosition(for: "track-1") == 42.5)
    #expect(try CompanionPreferenceStore(url: url).resumePositions() == ["track-1": 42.5])
    try store.setResumePosition(nil, for: "track-1")
    #expect(try store.resumePosition(for: "track-1") == nil)
    try store.setResumePosition(12, for: "track-2")
    try store.clearPlaybackActivity()
    #expect(try store.recentlyPlayedAlbumIDs().isEmpty)
    #expect(try store.playCountsByAlbumID().isEmpty)
    #expect(try store.resumePosition(for: "track-2") == nil)
    #expect(try store.favouriteAlbumIDs() == ["album-2"])
    try store.clearFavourites()
    #expect(try store.favouriteAlbumIDs().isEmpty)
}

@Test("Snapshot client keeps last valid cache when checksum fails")
func snapshotValidation() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "SnapshotValidation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "Source")
    let client = SnapshotClient(cacheDirectory: root.appending(path: "Cache"))
    let good = try writeSnapshot("Verified", sequence: 1, to: source)
    #expect(try client.update(from: source))
    #expect(try client.localManifestModificationDate() != nil)
    let bad = ReadOnlySnapshotManifest(format: good.format, revision: 2, fileName: good.fileName, sha256: "bad")
    try JSONEncoder().encode(bad).write(to: source.appending(path: "manifest.json"))
    #expect(throws: SnapshotClientError.checksumMismatch) { try client.update(from: source) }
    #expect(try client.localCatalogue()?.albums.first?.title == "Verified")
}

@Test("Snapshot client rejects non-canonical payload names before touching its cache")
func rejectsUnsafeSnapshotFileName() throws {
    let source = FileManager.default.temporaryDirectory.appending(path: "unsafe-snapshot-source-\(UUID().uuidString)")
    let cache = FileManager.default.temporaryDirectory.appending(path: "unsafe-snapshot-cache-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: cache) }
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let manifest = ReadOnlySnapshotManifest(format: "music-library-snapshot-json-v1", revision: 1, fileName: "../outside.json", sha256: "unused")
    try JSONEncoder().encode(manifest).write(to: source.appending(path: "manifest.json"))
    let client = SnapshotClient(cacheDirectory: cache)
    #expect(throws: SnapshotClientError.unsafeFileName) { try client.update(from: source) }
    #expect(!FileManager.default.fileExists(atPath: cache.appending(path: "manifest.json").path))
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

@Test("A client refuses a snapshot from a newer unsupported schema")
func unsupportedSnapshotSchema() throws {
    let source = FileManager.default.temporaryDirectory.appending(path: "unsupported-schema-source-\(UUID().uuidString)")
    let cache = FileManager.default.temporaryDirectory.appending(path: "unsupported-schema-cache-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: cache) }
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let payload = ReadOnlyCatalogue(format: "music-library-json", schemaVersion: ReadOnlyCatalogue.maximumSupportedSchemaVersion + 1, catalogueRevision: 1, albums: [])
    let data = try JSONEncoder().encode(payload)
    let fileName = "catalogue-1.json"
    try data.write(to: source.appending(path: fileName))
    let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let manifest = ReadOnlySnapshotManifest(format: "music-library-snapshot-json-v1", revision: 1, fileName: fileName, sha256: checksum)
    try JSONEncoder().encode(manifest).write(to: source.appending(path: "manifest.json"))
    let client = SnapshotClient(cacheDirectory: cache)
    #expect(throws: SnapshotClientError.incompatibleCatalogue) { try client.update(from: source) }
    #expect(try client.localCatalogue() == nil)
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

@Test("A companion track selects only a resolved available asset for playback")
func companionPlayableURL() {
    let mappings = [SMBRootMapping(publishedRootID: "root-a", localURL: URL(fileURLWithPath: "/Volumes/Music"))]
    let track = ReadOnlyTrack(id: "track", number: 1, title: "Song", assets: [
        .init(storageRootID: "missing-root", relativePath: "Song.flac", availability: "available"),
        .init(storageRootID: "root-a", relativePath: "Song.flac", availability: "available")
    ])
    #expect(track.playableURL(using: mappings) == URL(fileURLWithPath: "/Volumes/Music/Song.flac"))
    #expect(ReadOnlyTrack(id: "offline", number: 2, title: "Offline", assets: [.init(storageRootID: "root-a", relativePath: "Song.flac", availability: "rootOffline")]).playableURL(using: mappings) == nil)
}

@Test("Companion accepts a later publication of the same catalogue revision regardless of file timestamps")
func sourceManifestSequenceCheck() throws {
    let source = FileManager.default.temporaryDirectory.appending(path: "sequence-source-\(UUID())")
    let cache = FileManager.default.temporaryDirectory.appending(path: "sequence-cache-\(UUID())")
    defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: cache) }
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let sourceManifest = source.appending(path: "manifest.json")
    let client = SnapshotClient(cacheDirectory: cache)

    func publish(_ title: String, sequence: Int) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: [
            "format": "music-library-json", "schemaVersion": 10, "catalogueRevision": 7,
            "albums": [["id": "album", "title": title, "hasCD": false, "hasDigital": true, "discs": []]]
        ])
        let name = "catalogue-\(sequence).json"
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        try payload.write(to: source.appending(path: name))
        let manifest = try JSONSerialization.data(withJSONObject: [
            "format": "music-library-snapshot-json-v1", "revision": sequence, "catalogueRevision": 7,
            "fileName": name, "sha256": digest
        ])
        try manifest.write(to: sourceManifest)
        return name
    }

    _ = try publish("Before restore", sequence: 7)
    #expect(try client.update(from: source))
    #expect(try client.localCatalogue()?.albums.first?.title == "Before restore")
    _ = try publish("After restore", sequence: 8)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10)], ofItemAtPath: sourceManifest.path)
    #expect(try client.sourceManifestIsNewer(from: source))
    #expect(try client.localCatalogue()?.albums.first?.title == "Before restore")
    #expect(try client.update(from: source))
    #expect(try client.localCatalogue()?.albums.first?.title == "After restore")
    #expect(try !client.sourceManifestIsNewer(from: source))
}


@Test("Switching shares permits lower or equal sequences and keeps the verified cache on failure")
func switchesSnapshotSources() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "SnapshotSwitch-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appending(path: "A")
    let b = root.appending(path: "B")
    let cache = root.appending(path: "Cache")
    let client = SnapshotClient(cacheDirectory: cache)
    try writeSnapshot("First share", sequence: 80, to: a)
    #expect(try client.update(from: a))
    #expect(client.localSnapshotMatchesSource(a) == true)

    // Both shares can publish the same numeric filename.
    try writeSnapshot("Second share", sequence: 2, to: b)
    #expect(try client.update(from: b))
    #expect(try client.localCatalogue()?.albums.first?.title == "Second share")
    #expect(try client.update(from: a))

    let bad = try writeSnapshot("Bad schema", sequence: 2, to: b, schema: ReadOnlyCatalogue.maximumSupportedSchemaVersion + 1)
    #expect(try client.sourceManifestIsNewer(from: b))
    #expect(client.localSnapshotMatchesSource(b) == false)
    #expect(throws: SnapshotClientError.incompatibleCatalogue) { try client.update(from: b) }
    #expect(try client.localCatalogue()?.albums.first?.title == "First share")
    #expect(client.localSnapshotMatchesSource(a) == true)

    let corruptPayload = b.appending(path: bad.fileName)
    try Data([0]).write(to: corruptPayload)
    #expect(throws: SnapshotClientError.checksumMismatch) { try client.update(from: b) }
    #expect(try client.localCatalogue()?.albums.first?.title == "First share")

    try writeSnapshot("Updated second share", sequence: 2, to: b)
    let reopened = SnapshotClient(cacheDirectory: cache)
    #expect(try reopened.update(from: b))
    #expect(reopened.localSnapshotMatchesSource(b) == true)
    #expect(try reopened.localCatalogue()?.albums.first?.title == "Updated second share")
    try writeSnapshot("Older second share", sequence: 1, to: b)
    #expect(try !reopened.sourceManifestIsNewer(from: b))
    #expect(try !reopened.update(from: b))

    try writeSnapshot("Equal sequence first share", sequence: 2, to: a)
    #expect(try reopened.update(from: a))
    #expect(try reopened.localCatalogue()?.albums.first?.title == "Equal sequence first share")
}

@Test("Legacy numeric cache remains readable and acquires source attribution on refresh")
func adoptsLegacySnapshotCache() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "LegacySnapshot-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appending(path: "Cache")
    let source = root.appending(path: "Source")
    try writeSnapshot("Legacy cache", sequence: 80, to: cache)
    try writeSnapshot("Selected folder", sequence: 1, to: source)
    let client = SnapshotClient(cacheDirectory: cache)
    #expect(client.localSnapshotMatchesSource(source) == nil)
    #expect(try client.localCatalogue()?.albums.first?.title == "Legacy cache")
    #expect(try client.sourceManifestIsNewer(from: source))
    #expect(try client.update(from: source))
    #expect(client.localSnapshotMatchesSource(source) == true)
    #expect(try client.localCatalogue()?.albums.first?.title == "Selected folder")
}

@Test("Refresh repairs a missing or damaged payload from the same publication", arguments: [false, true])
func repairsCurrentSnapshot(damage: Bool) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "SnapshotRepair-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "Source")
    let cache = root.appending(path: "Cache")
    let client = SnapshotClient(cacheDirectory: cache)
    let published = try writeSnapshot("Verified album", sequence: 7, to: source)
    #expect(try client.update(from: source))
    #expect(try !client.update(from: source))

    let localManifest = cache.appending(path: "manifest.json")
    let manifestBytes = try Data(contentsOf: localManifest)
    let cached = try JSONDecoder().decode(ReadOnlySnapshotManifest.self, from: manifestBytes)
    let localPayload = cache.appending(path: cached.fileName)
    let original = try Data(contentsOf: localPayload)
    if damage {
        try Data("damaged".utf8).write(to: localPayload)
    } else {
        try FileManager.default.removeItem(at: localPayload)
    }
    #expect(throws: (any Error).self) { _ = try client.localCatalogue() }

    try writeSnapshot("Older album", sequence: 6, to: source)
    #expect(try !client.update(from: source))
    try writeSnapshot("Conflicting album", sequence: 7, to: source)
    #expect(throws: SnapshotClientError.checksumMismatch) { try client.update(from: source) }
    #expect(try Data(contentsOf: localManifest) == manifestBytes)

    let remotePayload = source.appending(path: published.fileName)
    try JSONEncoder().encode(published).write(to: source.appending(path: "manifest.json"))
    #expect(throws: SnapshotClientError.checksumMismatch) { try client.update(from: source) }
    try original.write(to: remotePayload)
    #expect(try client.update(from: source))
    #expect(try client.localCatalogue()?.albums.first?.title == "Verified album")
    #expect(try Data(contentsOf: localPayload) == original)
    #expect(client.localSnapshotMatchesSource(source) == true)
    #expect(try !client.sourceManifestIsNewer(from: source))
    #expect(try !client.update(from: source))
}

@Test("Verified activation prunes obsolete local payloads while preserving the share and unrelated entries")
func snapshotCacheRetention() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "SnapshotRetention-\(UUID())")
    let files = FileManager.default
    defer { try? files.removeItem(at: root) }
    let cache = root.appending(path: "Cache")
    let source = root.appending(path: "Source")
    let client = SnapshotClient(cacheDirectory: cache)
    let legacy = try writeSnapshot("Legacy cache", sequence: 50, to: cache)
    let first = try writeSnapshot("First publication", sequence: 1, to: source)
    let invalid = try writeSnapshot("Unsupported publication", sequence: 2, to: source, schema: 999)
    let remotePayload = source.appending(path: invalid.fileName)
    let legacyPayload = cache.appending(path: legacy.fileName)
    let unrelated = cache.appending(path: "catalogue-notes.json")
    let newline = cache.appending(path: "catalogue-90.json\n")
    let nested = cache.appending(path: "catalogue-91.json", directoryHint: .isDirectory)
    let link = cache.appending(path: "catalogue-92.json")
    try Data([1]).write(to: unrelated)
    try Data([2]).write(to: newline)
    try files.createDirectory(at: nested, withIntermediateDirectories: false)
    try files.createSymbolicLink(at: link, withDestinationURL: remotePayload)

    #expect(throws: SnapshotClientError.incompatibleCatalogue) { try client.update(from: source) }
    #expect(files.fileExists(atPath: legacyPayload.path))
    #expect(try client.localCatalogue()?.albums.first?.title == "Legacy cache")

    let sourceManifest = source.appending(path: "manifest.json")
    try JSONEncoder().encode(first).write(to: sourceManifest)
    #expect(try client.update(from: source))
    #expect(!files.fileExists(atPath: legacyPayload.path))
    let firstCachedPayload = cache.appending(path: "catalogue-\(first.sha256).json")
    #expect(files.fileExists(atPath: firstCachedPayload.path))

    let latest = try writeSnapshot("Latest publication", sequence: 3, to: source)
    let publishedEntries = try files.contentsOfDirectory(atPath: source.path).sorted()
    let publishedBytes = try publishedEntries.map { try Data(contentsOf: source.appending(path: $0)) }
    #expect(try client.update(from: source))
    #expect(!files.fileExists(atPath: firstCachedPayload.path))
    #expect(try SnapshotClient(cacheDirectory: cache).localCatalogue()?.albums.first?.title == "Latest publication")
    #expect(try files.contentsOfDirectory(atPath: cache.path).sorted() == [
        "catalogue-\(latest.sha256).json", "manifest.json",
        unrelated.lastPathComponent, newline.lastPathComponent, nested.lastPathComponent, link.lastPathComponent
    ].sorted())
    #expect(try files.destinationOfSymbolicLink(atPath: link.path) == remotePayload.path)
    #expect(try files.contentsOfDirectory(atPath: source.path).sorted() == publishedEntries)
    #expect(try publishedEntries.map { try Data(contentsOf: source.appending(path: $0)) } == publishedBytes)
}

@Test("Refresh refuses the cache directory as a source even through a symbolic link", arguments: [false, true])
func snapshotCacheCannotBeItsOwnSource(viaLink: Bool) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "SnapshotSourceAlias-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appending(path: "Cache")
    try writeSnapshot("Legacy cache", sequence: 1, to: cache)
    let manifestURL = cache.appending(path: "manifest.json")
    let manifest = try Data(contentsOf: manifestURL)
    let source = viaLink ? root.appending(path: "Alias") : cache
    if viaLink {
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: cache)
    }
    let client = SnapshotClient(cacheDirectory: cache)
    #expect(throws: SnapshotClientError.sourceIsCache) { try client.update(from: source) }
    #expect(try Data(contentsOf: manifestURL) == manifest)
    #expect(try client.localCatalogue()?.albums.first?.title == "Legacy cache")
}

@MainActor
@Test("A pending companion refresh rejects repeat submissions and preserves the visible catalogue until verification",
      arguments: [false, true])
func backgroundSnapshotRefresh(corrupt: Bool) async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "SnapshotBackground-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appending(path: "Cache")
    let source = root.appending(path: "Source")
    let client = SnapshotClient(cacheDirectory: cache)
    try writeSnapshot("Offline album", sequence: 1, to: source)
    #expect(try client.update(from: source))
    let publication = try writeSnapshot("New album", sequence: 2, to: source)
    if corrupt {
        try Data([0]).write(to: source.appending(path: publication.fileName))
    }

    let (started, signal) = AsyncStream<Void>.makeStream()
    let (resume, release) = AsyncStream<Void>.makeStream()
    defer { release.finish() }
    let refresh = SnapshotRefresh { directory in
        signal.yield(())
        signal.finish()
        for await _ in resume { break }
        return try SnapshotRefresh.perform(from: directory, cacheDirectory: cache)
    }
    var visible = try client.localCatalogue()
    var result: Result<SnapshotRefreshResult, any Error>?
    let request = try #require(refresh.start(from: source) { completed in
        result = completed
        if case .success(let snapshot) = completed { visible = snapshot.catalogue }
    })
    #expect(refresh.isRefreshing)
    for await _ in started { break }
    #expect(refresh.start(from: source) { _ in Issue.record("Duplicate refresh completed") } == nil)
    #expect(visible?.albums.first?.title == "Offline album")
    #expect(result == nil)

    release.yield(())
    release.finish()
    await request.value
    #expect(!refresh.isRefreshing)
    let completed = try #require(result)
    if corrupt {
        #expect(throws: SnapshotClientError.checksumMismatch) { try completed.get() }
        #expect(visible?.albums.first?.title == "Offline album")
    } else {
        let snapshot = try completed.get()
        #expect(snapshot.updated)
        #expect(snapshot.verifiedAt != nil)
        #expect(visible?.albums.first?.title == "New album")
    }
    #expect(try client.localCatalogue() == visible)
}

@discardableResult
private func writeSnapshot(
    _ title: String, sequence: Int64, to directory: URL, schema: Int = 10
) throws -> ReadOnlySnapshotManifest {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let catalogue = ReadOnlyCatalogue(format: "music-library-json", schemaVersion: schema, catalogueRevision: sequence, albums: [
        .init(id: "album", title: title, hasCD: false, hasDigital: true)
    ])
    let data = try JSONEncoder().encode(catalogue)
    let fileName = "catalogue-\(sequence).json"
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let manifest = ReadOnlySnapshotManifest(format: "music-library-snapshot-json-v1", revision: sequence, fileName: fileName, sha256: hash)
    try data.write(to: directory.appending(path: fileName))
    try JSONEncoder().encode(manifest).write(to: directory.appending(path: "manifest.json"))
    return manifest
}
