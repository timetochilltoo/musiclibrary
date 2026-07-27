import Foundation
import Testing
@testable import MusicApplication
@testable import MusicDomain
@testable import MusicPersistence

@Suite("Import scanner")
struct ImportScannerTests {
    @Test("Scanner discovers audio by content type and skips hidden files")
    func discoversAudioAndSkipsHidden() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let nested = root.appending(path: "Nested", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try? Data([0]).write(to: nested.appending(path: "song.mp3"))
        try? Data([0]).write(to: root.appending(path: ".hidden.mp3"))
        try? Data("not audio".utf8).write(to: root.appending(path: "notes.txt"))

        let result = ImportScanner().scan(rootURL: root)
        #expect(result.candidates.map(\.relativePath) == ["Nested/song.mp3"])
        #expect(result.candidates.first?.contentTypeIdentifier.isEmpty == false)
    }

    @Test("Scanner stops before enumerating when cancelled")
    func cancellation() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? Data([0]).write(to: root.appending(path: "song.mp3"))

        let result = ImportScanner().scan(rootURL: root, isCancelled: { true })
        #expect(result.wasCancelled)
        #expect(result.candidates.isEmpty)
    }

    @Test("Metadata grouping keeps Unicode multi-disc candidates in one proposal")
    func groupsMetadata() {
        let batchID = ImportBatchID()
        let first = ImportCandidate(id: ImportCandidateID(), batchID: batchID, status: .proposed, payload: .init(relativePath: "宇多田/アルバム/01.mp3", fileName: "01.mp3", contentTypeIdentifier: "public.mp3", fileSize: 1, modifiedAt: nil), errorMessage: nil, metadata: .init(title: "曲一", albumTitle: "アルバム", artist: "宇多田", albumArtist: nil, discNumber: 1, trackNumber: 1, durationMilliseconds: nil, rawTags: [:]))
        let second = ImportCandidate(id: ImportCandidateID(), batchID: batchID, status: .proposed, payload: .init(relativePath: "宇多田/アルバム/02.mp3", fileName: "02.mp3", contentTypeIdentifier: "public.mp3", fileSize: 1, modifiedAt: nil), errorMessage: nil, metadata: .init(title: "曲二", albumTitle: "アルバム", artist: "宇多田", albumArtist: nil, discNumber: 2, trackNumber: 1, durationMilliseconds: nil, rawTags: [:]))
        let proposals = MetadataProposalGrouper().group(candidates: [first, second])
        #expect(proposals.count == 1)
        #expect(proposals.first?.title == "アルバム")
        #expect(proposals.first?.discCount == 2)
        #expect(proposals.first?.candidateIDs.count == 2)
    }

    @Test("Path fallback joins disc folders and derives ordered track titles")
    func pathFallbackMetadata() {
        let first = EmbeddedMetadataExtractor.pathFallback(relativePath: "Andrew Lloyd Webber/The Phantom Of The Opera [Disc 1]/01 Prologue - The Stage Of Paris.flac")
        let second = EmbeddedMetadataExtractor.pathFallback(relativePath: "Andrew Lloyd Webber/The Phantom Of The Opera [Disc 2]/02 Overture.flac")
        #expect(first.title == "Prologue - The Stage Of Paris")
        #expect(first.trackNumber == 1)
        #expect(first.albumTitle == "The Phantom Of The Opera")
        #expect(first.artist == "Andrew Lloyd Webber")
        #expect(first.discNumber == 1)
        let batchID = ImportBatchID()
        let candidates = [first, second].enumerated().map { index, metadata in
            ImportCandidate(id: ImportCandidateID(), batchID: batchID, status: .proposed, payload: .init(relativePath: "artist/album/\(index).flac", fileName: "\(index).flac", contentTypeIdentifier: "public.audio", fileSize: 1, modifiedAt: nil), errorMessage: nil, metadata: metadata)
        }
        let proposals = MetadataProposalGrouper().group(candidates: candidates)
        #expect(proposals.count == 1)
        #expect(proposals.first?.discCount == 2)
    }

    @Test("FLAC Vorbis comments provide catalogue metadata and technical details")
    func readsFLACVorbisComments() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "01 ignored.flac")
        try makeTaggedFLAC().write(to: file)

        let metadata = await EmbeddedMetadataExtractor().extract(url: file, relativePath: "容祖兒/Joey/01 ignored.flac")
        #expect(metadata.title == "痛愛")
        #expect(metadata.artist == "容祖兒")
        #expect(metadata.albumTitle == "Joey")
        #expect(metadata.albumArtist == "容祖兒")
        #expect(metadata.trackNumber == 1)
        #expect(metadata.discNumber == 1)
        #expect(metadata.releaseYear == 2001)
        #expect(metadata.genre == "Chinese Pop")
        #expect(metadata.codec == "FLAC")
        #expect(metadata.sampleRateHz == 44_100)
        #expect(metadata.bitDepth == 16)
        #expect(metadata.channelCount == 2)
        #expect(metadata.durationMilliseconds == 3_000)
    }

    @Test("Snapshot publisher writes a checksummed manifest after the revision file")
    func publishesSnapshot() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = try SnapshotPublisher.publish(json: "{\"format\":\"music-library-json\"}", revision: 42, to: directory)
        #expect(manifest.fileName == "catalogue-42.json")
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: manifest.fileName).path))
        let decoded = try JSONDecoder().decode(SnapshotManifest.self, from: Data(contentsOf: directory.appending(path: "manifest.json")))
        #expect(decoded.sha256 == manifest.sha256)
    }

    @Test("Managed artwork import copies the selected image into catalogue storage")
    func importsManagedArtwork() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appending(path: "cover.jpg")
        try Data([1, 2, 3]).write(to: source)
        let destination = try ManagedArtworkStore(directory: directory.appending(path: "Artwork")).importArtwork(from: source)
        #expect(destination.deletingLastPathComponent().lastPathComponent == "Artwork")
        #expect(destination != source)
        #expect(try Data(contentsOf: destination) == Data([1, 2, 3]))
    }

    @Test("Master archive writes a checksummed verified SQLite backup")
    func writesMasterArchive() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MusicDatabase(url: directory.appending(path: "source.sqlite"))
        try await database.migrate()
        _ = try await database.createAlbum(.init(title: "Archived"))

        let archiveDirectory = directory.appending(path: "Backups")
        let manifest = try await MasterBackupArchive.create(database: database, in: archiveDirectory, now: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(FileManager.default.fileExists(atPath: archiveDirectory.appending(path: manifest.fileName).path))
        try await MasterBackupArchive.verify(manifest, in: archiveDirectory)
    }

    @Test("Master backup retention keeps the newest backup from each recent day")
    func retainsDailyMasterBackups() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for day in 0..<8 {
            let createdAt = calendar.date(byAdding: .day, value: day, to: start)!
            let fileName = "MusicLibrary-master-r\(day)-\(day).sqlite"
            try Data([UInt8(day)]).write(to: directory.appending(path: fileName))
            let manifest = MasterBackupManifest(revision: Int64(day), createdAt: createdAt, fileName: fileName, sha256: "unused")
            try JSONEncoder().encode(manifest).write(to: directory.appending(path: "\(fileName).manifest.json"))
        }
        try MasterBackupArchive.retain(in: directory, daily: 7, monthly: 0)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".sqlite") }
        #expect(backups.count == 7)
        #expect(!backups.contains("MusicLibrary-master-r0-0.sqlite"))
    }

    @Test("Snapshot publisher retains only the configured recent revisions")
    func retainsSnapshotRevisions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for revision in 1...4 { _ = try SnapshotPublisher.publish(json: "{\"format\":\"music-library-json\",\"revision\":\(revision)}", revision: Int64(revision), to: directory, retainRevisions: 2) }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("catalogue-") && $0.hasSuffix(".json") }
        #expect(files.sorted() == ["catalogue-3.json", "catalogue-4.json"])
        let manifest = try JSONDecoder().decode(SnapshotManifest.self, from: Data(contentsOf: directory.appending(path: "manifest.json")))
        #expect(manifest.fileName == "catalogue-4.json")
    }

    @Test("Snapshot publisher keeps the current revision and three prior revisions by default")
    func retainsDefaultSnapshotRevisions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for revision in 1...5 { _ = try SnapshotPublisher.publish(json: "{\"format\":\"music-library-json\",\"revision\":\(revision)}", revision: Int64(revision), to: directory) }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("catalogue-") && $0.hasSuffix(".json") }
        #expect(files.sorted() == ["catalogue-2.json", "catalogue-3.json", "catalogue-4.json", "catalogue-5.json"])
    }

    @Test("Publication scheduling ignores initial and read-only observations but coalesces mutations")
    func publicationScheduling() {
        var schedule = SnapshotPublicationSchedule()
        let initial = schedule.observe(4)
        #expect(!initial)
        let readOnly = schedule.observe(4)
        #expect(!readOnly)
        let mutation = schedule.observe(5)
        #expect(mutation)
        #expect(schedule.needsPublication)
        schedule.markPublished(5)
        #expect(!schedule.needsPublication)
        let sameRevision = schedule.observe(5)
        #expect(!sameRevision)
        let nextMutation = schedule.observe(6)
        #expect(nextMutation)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ImportScannerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeTaggedFLAC() -> Data {
        func littleEndian(_ value: UInt32) -> [UInt8] { [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)] }
        func metadataBlock(type: UInt8, isLast: Bool, payload: [UInt8]) -> [UInt8] {
            [isLast ? type | 0x80 : type, UInt8((payload.count >> 16) & 0xff), UInt8((payload.count >> 8) & 0xff), UInt8(payload.count & 0xff)] + payload
        }
        let packed = (UInt64(44_100) << 44) | (UInt64(1) << 41) | (UInt64(15) << 36) | UInt64(132_300)
        var streamInfo = Array(repeating: UInt8(0), count: 34)
        for offset in 0..<8 { streamInfo[10 + offset] = UInt8((packed >> UInt64((7 - offset) * 8)) & 0xff) }
        let comments = ["TITLE=痛愛", "ARTIST=容祖兒", "ALBUM=Joey", "ALBUMARTIST=容祖兒", "DATE=2001", "TRACKNUMBER=1/10", "DISCNUMBER=1", "GENRE=Chinese Pop"]
        var vorbis = littleEndian(0) + littleEndian(UInt32(comments.count))
        for comment in comments {
            let bytes = Array(comment.utf8)
            vorbis += littleEndian(UInt32(bytes.count)) + bytes
        }
        return Data(Array("fLaC".utf8) + metadataBlock(type: 0, isLast: false, payload: streamInfo) + metadataBlock(type: 4, isLast: true, payload: vorbis))
    }
}
