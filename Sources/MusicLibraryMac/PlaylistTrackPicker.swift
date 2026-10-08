import SwiftUI
import MusicDomain
import MusicApplication

struct PlaylistTrackPicker: View {
    @ObservedObject var library: LibraryStore
    let playlist: Playlist
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selection: TrackID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var attemptedSelection: TrackID?
    @State private var entryID = UUID()
    private var tracks: [TrackBrowseSummary] {
        library.trackBrowseSummaries.filter { $0.matches(search, albumArtist: library.albumBrowseSummaries[$0.albumID]?.artist) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Tracks to \(playlist.name)").font(.title2.bold())
            Text("Choose a catalogue track. Adding it again creates another playlist entry; no audio is copied.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Search tracks, albums or album artists", text: $search).textFieldStyle(.roundedBorder)
                .disabled(attemptedSelection != nil)
            Text("\(tracks.count) matching track\(tracks.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            List(tracks, selection: $selection) { track in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(track.title).font(.headline)
                        Spacer()
                        if let duration = track.durationLabel { Text(duration).monospacedDigit().foregroundStyle(.secondary) }
                    }
                    Text("\(track.albumTitle) · Disc \(track.discNumber), track \(track.trackNumber)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let artist = library.albumBrowseSummaries[track.albumID]?.artist {
                        Text("Album artist: \(artist)").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 5).tag(track.id)
            }.disabled(attemptedSelection != nil).overlay {
                if tracks.isEmpty {
                    ContentUnavailableView("No Matching Tracks", systemImage: "magnifyingglass", description: Text("Try another search. Only tracks from active catalogue albums are listed."))
                }
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if isSaving { ProgressView().controlSize(.small); Text("Adding track…").font(.caption) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(errorMessage == nil ? "Add Selected Track" : "Retry Add") { add() }.keyboardShortcut(.defaultAction)
                    .disabled(selection == nil || !tracks.contains(where: { $0.id == selection }))
            }
        }.padding(24).frame(minWidth: 560, idealWidth: 650, minHeight: 440, idealHeight: 560)
            .disabled(isSaving).interactiveDismissDisabled(isSaving)
    }
    private func add() {
        guard !isSaving, let selection, tracks.contains(where: { $0.id == selection }) else { return }
        attemptedSelection = selection
        isSaving = true; errorMessage = nil
        Task {
            defer { isSaving = false }
            do { try await library.addTrack(selection, toPlaylist: playlist.id, itemID: entryID); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
