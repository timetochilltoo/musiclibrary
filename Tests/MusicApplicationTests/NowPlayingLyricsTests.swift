import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Now Playing lyrics")
@MainActor
struct NowPlayingLyricsTests {
    @Test("Timed versions are parsed once per accepted read and cleared on errors or target changes")
    func cachedTimelines() async {
        let model = NowPlayingLyricsModel(), value = track()
        let valid = LyricsEntry(trackID: value.id, kind: .synchronized, text: "[00:01]First\n[00:02]Second")
        let malformed = LyricsEntry(trackID: value.id, kind: .synchronized, text: "[00:01]Valid\nUntimed text")
        let plain = LyricsEntry(trackID: value.id, text: "[00:01]Literal plain text")
        await model.load(trackID: value.id, revision: 1) { _ in .init(track: value, entries: [valid, malformed, plain]) }
        #expect(model.timelines.count == 1 && model.timelines[valid.id]?.cues.count == 2)
        #expect(model.snapshot?.entries == [valid, malformed, plain]) // Original text never rewritten.
        await model.load(trackID: value.id, revision: 2) { _ in throw LyricsReadGate.Failure.fixture }
        #expect(model.timelines.isEmpty && model.errorMessage != nil)
        await model.load(trackID: nil, revision: 3) { _ in Issue.record("No read without a track"); return nil }
        #expect(model.timelines.isEmpty && model.errorMessage == nil)
    }
    @Test("Newer track or revision wins over an older reader and its error")
    func latestReadWins() async throws {
        let model = NowPlayingLyricsModel()
        let first = track(), second = track()
        let gate = LyricsReadGate()
        let old = Task { await model.load(trackID: first.id, revision: 1) { _ in try await gate.read() } }
        await gate.waitUntilRequested()
        await model.load(trackID: second.id, revision: 2) { _ in .init(track: second, entries: [.init(trackID: second.id, text: "New lyrics")]) }
        await gate.fail()
        await old.value
        #expect(model.snapshot?.track.id == second.id && model.snapshot?.entries.first?.text == "New lyrics")
        #expect(model.errorMessage == nil && !model.isLoading && model.revision == 2)

        let sameTrackGate = LyricsReadGate()
        let stale = Task { await model.load(trackID: second.id, revision: 2) { _ in try await sameTrackGate.read() } }
        await sameTrackGate.waitUntilRequested()
        await model.load(trackID: second.id, revision: 3) { _ in .init(track: second, entries: []) }
        await sameTrackGate.complete(.init(track: second, entries: [.init(trackID: second.id, kind: .synchronized, text: "[00:01]Outdated")]))
        await stale.value
        #expect(model.revision == 3 && model.snapshot?.entries.isEmpty == true)
        #expect(model.timelines.isEmpty)
    }

    @Test("No track and mismatched reader identities cannot display another song's lyrics")
    func emptyAndMismatch() async {
        let model = NowPlayingLyricsModel()
        let first = track(), other = track()
        await model.load(trackID: nil, revision: 0) { _ in Issue.record("Reader must not run"); return nil }
        #expect(model.snapshot == nil && !model.isLoading && model.errorMessage == nil)
        await model.load(trackID: first.id, revision: 1) { _ in .init(track: other, entries: []) }
        #expect(model.snapshot == nil)
        await model.load(trackID: first.id, revision: 1) { _ in .init(track: first, entries: [.init(trackID: other.id, text: "Wrong track")]) }
        #expect(model.snapshot == nil)
    }

    @Test("Cancelled reads publish neither lyrics nor errors; retry succeeds")
    func cancellationAndRetry() async {
        let model = NowPlayingLyricsModel(), value = track()
        let gate = LyricsReadGate()
        let pending = Task { await model.load(trackID: value.id, revision: 1) { _ in try await gate.read() } }
        await gate.waitUntilRequested()
        pending.cancel()
        await gate.fail()
        await pending.value
        #expect(model.snapshot == nil && model.errorMessage == nil && !model.isLoading)
        await model.load(trackID: value.id, revision: 1) { _ in throw LyricsReadGate.Failure.fixture }
        #expect(model.errorMessage != nil && !model.isLoading && model.snapshot == nil)
        await model.load(trackID: value.id, revision: 1) { _ in .init(track: value, entries: []) }
        #expect(model.snapshot?.track.isInstrumental == true && !model.isLoading && model.errorMessage == nil)
    }

    @Test("Lyrics context is catalogue-only, retains plain/LRC versions and excludes deleted tracks")
    func catalogueContext() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LyricsContext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Fixture album"))
        let disc = try await database.createDisc(albumID: album.id)
        let track = try await database.createTrack(discID: disc.id, draft: .init(title: "Instrumental", displayPosition: "A2",
            durationMilliseconds: 2_200, workName: "Suite", movementNumber: 2, movementName: "Adagio", isInstrumental: true, rating: 4))
        let plain = LyricsEntry(trackID: track.id, language: "en", text: "Fixture plain text")
        let lrc = LyricsEntry(trackID: track.id, language: "en", kind: .synchronized, text: "[00:01.00]Fixture timed line")
        try await database.saveLyrics(plain)
        try await database.saveLyrics(lrc)
        let store = LibraryStore(database: database)
        try await store.reload()
        let revision = store.catalogueRevision
        let value = try #require(await store.nowPlayingLyrics(trackID: track.id))
        #expect(value.track == track && value.track.isInstrumental == true)
        #expect(Set(value.entries.map(\.id)) == [plain.id, lrc.id])
        #expect(value.entries.contains(plain) && value.entries.contains(lrc))
        #expect(try await database.currentRevision() == revision && !store.isSnapshotPublishPending)
        #expect(try await store.nowPlayingLyrics(trackID: TrackID()) == nil)
        try await store.softDeleteAlbum(album.id)
        #expect(try await store.nowPlayingLyrics(trackID: track.id) == nil)
    }

    private func track() -> Track {
        .init(id: TrackID(), discID: DiscID(), number: 1, title: "Fixture track", displayPosition: nil,
              durationMilliseconds: nil, workName: nil, movementNumber: nil, movementName: nil, isInstrumental: true)
    }
}

private actor LyricsReadGate {
    enum Failure: Error { case fixture }
    private var continuation: CheckedContinuation<NowPlayingLyrics?, any Error>?
    private var requested: CheckedContinuation<Void, Never>?
    func read() async throws -> NowPlayingLyrics? {
        try await withCheckedThrowingContinuation { continuation = $0; requested?.resume(); requested = nil }
    }
    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
    func fail() { continuation?.resume(throwing: Failure.fixture); continuation = nil }
    func complete(_ value: NowPlayingLyrics) { continuation?.resume(returning: value); continuation = nil }
}
