import Combine
import Foundation
import MusicDomain

/// A manual draft always belongs to the track captured when the editor opens.
@MainActor
public final class LyricsEditorModel: ObservableObject {
    public let trackID: TrackID
    @Published public private(set) var entries: [LyricsEntry] = []
    @Published public var text = ""
    @Published public var language = ""
    @Published public var kind: LyricsKind = .plain
    @Published public private(set) var isBusy = false
    @Published public private(set) var readError: String?
    @Published public private(set) var writeError: String?
    @Published public private(set) var status: String?
    @Published public private(set) var editingID: UUID?
    private var draftID = UUID()
    private var original: LyricsEntry?

    public init(trackID: TrackID) { self.trackID = trackID }
    public var isDirty: Bool {
        text != (original?.text ?? "") || language != (original?.language ?? "") || kind != (original?.kind ?? .plain)
    }
    public var canSave: Bool { !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isDirty }

    public func beginEditing(_ entry: LyricsEntry?) {
        guard !isBusy, entry == nil || entry?.trackID == trackID else { return }
        original = entry
        editingID = entry?.id
        draftID = entry?.id ?? UUID()
        text = entry?.text ?? ""
        language = entry?.language ?? ""
        kind = entry?.kind ?? .plain
        status = nil
        writeError = nil
    }

    public func load(read: (TrackID) async throws -> [LyricsEntry]) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        readError = nil
        do {
            let values = try await read(trackID)
            guard values.allSatisfy({ $0.trackID == trackID }) else { throw EditorError.wrongTrack }
            entries = values
        } catch { readError = error.localizedDescription }
    }

    public func save(write: (LyricsEntry) async throws -> Void) async {
        guard canSave else { return }
        isBusy = true
        defer { isBusy = false }
        writeError = nil
        status = nil
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = LyricsEntry(id: draftID, trackID: trackID, language: trimmedLanguage.isEmpty ? nil : trimmedLanguage,
            kind: kind, text: text, source: original?.source ?? "manual", providerID: original?.providerID, isUserEdited: true)
        do {
            try await write(value)
            entries.removeAll { $0.id == value.id }
            entries.append(value)
            original = value
            editingID = value.id
            language = value.language ?? ""
            status = "Lyrics saved."
        } catch {
            // Keep this UUID and draft: a service refresh may fail after the write committed.
            writeError = error.localizedDescription
        }
    }

    public func delete(_ entry: LyricsEntry, write: (UUID) async throws -> Void) async {
        guard !isBusy, entry.trackID == trackID, entries.contains(where: { $0.id == entry.id }) else { return }
        isBusy = true
        writeError = nil
        status = nil
        do {
            try await write(entry.id)
            entries.removeAll { $0.id == entry.id }
            isBusy = false
            if editingID == entry.id { beginEditing(nil) }
            status = "Lyrics deleted."
        } catch { writeError = error.localizedDescription }
        isBusy = false
    }

    private enum EditorError: LocalizedError {
        case wrongTrack
        var errorDescription: String? { "The lyrics response belongs to a different track. Try again." }
    }
}
