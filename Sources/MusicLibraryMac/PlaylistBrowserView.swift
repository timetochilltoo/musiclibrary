import SwiftUI
import MusicDomain
import MusicApplication

struct PlaylistBrowserView: View {
    @ObservedObject var library: LibraryStore
    @Binding var selection: PlaylistID?
    @Binding var search: String
    let onRename: (Playlist) -> Void
    let onDelete: (Playlist) -> Void
    private var playlists: [Playlist] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.playlists.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id.description < $1.id.description : comparison == .orderedAscending
        }
    }
    var body: some View {
        let tracks = Dictionary(uniqueKeysWithValues: library.trackBrowseSummaries.map { ($0.id, $0) })
        VStack(spacing: 0) {
            HStack {
                Text("\(playlists.count) playlist\(playlists.count == 1 ? "" : "s")").font(.callout)
                Spacer()
                TextField("Search playlists", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            }.padding(16)
            List(playlists) { playlist in
                Button { selection = playlist.id } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "music.note.list").font(.title).foregroundStyle(Color.accentColor)
                            .frame(width: 64, height: 64).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(playlist.name).font(.headline)
                            let count = library.playlistContents[playlist.id]?.count ?? 0
                            Text(count == 0 ? "Empty playlist" : "\(count) track\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                            let summary = PlaylistBrowseSummary(items: library.playlistContents[playlist.id] ?? [], tracks: tracks)
                            if let duration = summary.durationLabel { Text(duration).font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).contextMenu {
                    Button("Rename…") { onRename(playlist) }
                    Button("Move to Recently Deleted", role: .destructive) { onDelete(playlist) }
                }
            }.overlay {
                if library.isReady && playlists.isEmpty {
                    ContentUnavailableView {
                        Label(library.playlists.isEmpty ? "No Playlists" : "No Matching Playlists", systemImage: "music.note.list")
                    } description: {
                        Text(library.playlists.isEmpty ? "Use Add Playlist, then add tracks from an album." : "Try another name or clear your search.")
                    } actions: {
                        if !search.isEmpty { Button("Clear Search") { search = "" } }
                    }
                }
            }
        }
    }
}
