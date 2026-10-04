import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Manual lyrics editor")
@MainActor
struct LyricsEditorTests {
    enum Failure: Error { case fixture }

    @Test("Empty drafts and mismatched read/delete targets never write")
    func invalidTargets() async {
        let model = LyricsEditorModel(trackID: TrackID())
        model.text = " \n "
        await model.save { _ in Issue.record("Blank text must not write") }
        let other = LyricsEntry(trackID: TrackID(), text: "Other track")
        await model.load { _ in [other] }
        #expect(model.entries.isEmpty && model.readError != nil)
        await model.delete(other) { _ in Issue.record("Other track must not delete") }
        await model.load { _ in [] }
        #expect(model.readError == nil && model.entries.isEmpty)
    }

    @Test("Editing preserves identity, provenance and captured track")
    func edit() async {
        let track = TrackID(), other = TrackID()
        let model = LyricsEditorModel(trackID: track)
        let entry = LyricsEntry(trackID: track, language: "en", kind: .synchronized,
            text: "[00:01]Old", source: "fixture", providerID: "source-id", isUserEdited: false)
        await model.load { id in #expect(id == track); return [entry] }
        model.beginEditing(entry)
        #expect(!model.isDirty && !model.canSave)
        model.text = "[00:01]Updated"
        model.language = " zh-Hant "
        await model.save { value in
            #expect(value.id == entry.id && value.trackID == track)
            #expect(value.language == "zh-Hant" && value.kind == .synchronized)
            #expect(value.source == "fixture" && value.providerID == "source-id" && value.isUserEdited)
        }
        #expect(model.entries.count == 1 && !model.isDirty && !model.canSave)
        model.beginEditing(.init(trackID: other, text: "Wrong song"))
        #expect(model.editingID == entry.id && model.text == "[00:01]Updated")
    }

    @Test("Save retries retain draft UUID even when a committed write reports refresh failure")
    func retry() async {
        let model = LyricsEditorModel(trackID: TrackID())
        model.text = "Keep this draft"
        var firstID: UUID?
        await model.save { firstID = $0.id; throw Failure.fixture }
        #expect(model.isDirty && model.writeError != nil && model.text == "Keep this draft")
        await model.save { #expect($0.id == firstID) }
        #expect(model.entries.count == 1 && model.writeError == nil && !model.isDirty)
        await model.save { _ in Issue.record("Unchanged draft must not write again") }
        model.beginEditing(nil)
        model.text = "Another version"
        await model.save { #expect($0.id != firstID) }
        #expect(model.entries.count == 2)
    }

    @Test("Busy writes reject repeat submission and draft switching; failures remain visible")
    func busyAndErrors() async {
        let model = LyricsEditorModel(trackID: TrackID())
        model.text = "Pending"
        let gate = LyricsWriteGate()
        let write = Task { await model.save { _ in try await gate.write() } }
        await gate.waitUntilRequested()
        #expect(model.isBusy && !model.canSave)
        await model.save { _ in Issue.record("Duplicate write") }
        model.beginEditing(nil)
        #expect(model.text == "Pending")
        await gate.fail()
        await write.value
        #expect(!model.isBusy && model.writeError != nil && model.isDirty)
        await model.load { _ in throw Failure.fixture }
        #expect(model.readError != nil && model.text == "Pending")
        await model.load { id in [.init(trackID: id, text: "Saved")] }
        #expect(model.readError == nil && model.entries.count == 1)
        let entry = model.entries[0]
        model.beginEditing(entry)
        await model.delete(entry) { _ in throw Failure.fixture }
        #expect(model.writeError != nil && model.entries == [entry] && model.editingID == entry.id)
        await model.delete(entry) { #expect($0 == entry.id) }
        #expect(model.entries.isEmpty && model.editingID == nil && model.text.isEmpty && model.writeError == nil)
    }

    @Test("Database edits replace one row and reject cross-track or deleted-track writes atomically")
    func persistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LyricsEdit-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Fixture"))
        let disc = try await database.createDisc(albumID: album.id)
        let first = try await database.createTrack(discID: disc.id, draft: .init(title: "First"))
        let second = try await database.createTrack(discID: disc.id, draft: .init(title: "Second"))
        let entry = LyricsEntry(trackID: first.id, text: "Original")
        try await database.saveLyrics(entry)
        let updated = LyricsEntry(id: entry.id, trackID: first.id, text: "Edited")
        try await database.saveLyrics(updated)
        #expect(try await database.lyrics(trackID: first.id) == [updated])
        let revision = try await database.currentRevision()
        await #expect(throws: DatabaseError.invalidOperation("Lyrics cannot be reassigned to another track.")) {
            try await database.saveLyrics(.init(id: entry.id, trackID: second.id, text: "Wrong target"))
        }
        #expect(try await database.currentRevision() == revision)
        #expect(try await database.lyrics(trackID: first.id) == [updated])
        #expect(try await database.lyrics(trackID: second.id).isEmpty)
        try await database.softDeleteAlbum(album.id)
        let deletedRevision = try await database.currentRevision()
        await #expect(throws: DatabaseError.notFound("Track")) { try await database.saveLyrics(updated) }
        #expect(try await database.currentRevision() == deletedRevision)
    }
}

private actor LyricsWriteGate {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var requested: CheckedContinuation<Void, Never>?
    func write() async throws {
        try await withCheckedThrowingContinuation { continuation = $0; requested?.resume(); requested = nil }
    }
    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
    func fail() { continuation?.resume(throwing: LyricsEditorTests.Failure.fixture); continuation = nil }
}
