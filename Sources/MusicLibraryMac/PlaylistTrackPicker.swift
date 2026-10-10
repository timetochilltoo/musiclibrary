import SwiftUI
import MusicDomain
import MusicApplication

struct PlaylistTrackPicker: View {
    @ObservedObject var library: LibraryStore
    let playlist: Playlist
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selection = Set<TrackID>()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var attemptedAdditions: [PlaylistTrackAddition]?
    private var tracks: [TrackBrowseSummary] {
        library.trackBrowseSummaries.filter { $0.matches(search, albumArtist: library.albumBrowseSummaries[$0.albumID]?.artist) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Tracks to \(playlist.name)").font(.title2.bold())
            Text("Choose tracks in catalogue order. Selections stay selected while you search. Adding a track again creates another entry; no audio is copied.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Search tracks, albums or album artists", text: $search).textFieldStyle(.roundedBorder)
                .disabled(attemptedAdditions != nil)
            HStack {
                Text("\(tracks.count) matching track\(tracks.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Select Matching") { selection.formUnion(tracks.map(\.id)) }.disabled(tracks.isEmpty)
                Button("Clear Selection") { selection.removeAll() }.disabled(selection.isEmpty)
            }.disabled(attemptedAdditions != nil)
            List(tracks) { track in
                HStack(alignment: .top, spacing: 12) {
                    Toggle("Select \(track.title)", isOn: Binding(get: { selection.contains(track.id) }, set: { selected in
                        if selected { selection.insert(track.id) } else { selection.remove(track.id) }
                    })).toggleStyle(.checkbox).labelsHidden().accessibilityLabel("Select \(track.title)")
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
                        Text(track.audioStatus.label).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 5)
            }.disabled(attemptedAdditions != nil).overlay {
                if tracks.isEmpty {
                    ContentUnavailableView("No Matching Tracks", systemImage: "magnifyingglass", description: Text("Try another search. Only tracks from active catalogue albums are listed."))
                }
            }
            let visibleIDs = Set(tracks.map(\.id))
            let hiddenCount = selection.subtracting(visibleIDs).count
            Text("\(selection.count) selected" + (hiddenCount == 0 ? "" : " · \(hiddenCount) hidden by search or catalogue changes"))
                .font(.callout.weight(.medium))
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if isSaving { ProgressView().controlSize(.small); Text("Adding tracks…").font(.caption) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(attemptedAdditions == nil ? "Add \(selection.count) Track\(selection.count == 1 ? "" : "s")" : "Retry Add") { add() }.keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
            }
        }.padding(24).frame(minWidth: 560, idealWidth: 650, minHeight: 440, idealHeight: 560)
            .disabled(isSaving).interactiveDismissDisabled(isSaving)
    }
    private func add() {
        guard !isSaving, !selection.isEmpty else { return }
        let additions: [PlaylistTrackAddition]
        if let attemptedAdditions { additions = attemptedAdditions }
        else {
            let selectedTracks = library.trackBrowseSummaries.filter { selection.contains($0.id) }
            guard selectedTracks.count == selection.count else {
                errorMessage = "A selected track is no longer in the active catalogue. Clear Selection and choose tracks again."
                return
            }
            additions = selectedTracks.map { PlaylistTrackAddition(trackID: $0.id) }
            attemptedAdditions = additions
        }
        isSaving = true; errorMessage = nil
        Task {
            defer { isSaving = false }
            do { try await library.addTracks(additions, toPlaylist: playlist.id); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
