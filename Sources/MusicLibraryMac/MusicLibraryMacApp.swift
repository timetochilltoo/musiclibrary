import SwiftUI
import MusicDomain
import MusicUIComponents

@main
struct MusicLibraryMacApp: App {
    var body: some Scene {
        WindowGroup("Music Library") {
            LibraryShellView()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

private struct LibraryShellView: View {
    private enum Section: Hashable, CaseIterable, Identifiable {
        case albums, contributors, boxSets, importInbox, playlists, settings
        var id: Self { self }
        var title: String {
            switch self {
            case .albums: "Albums"
            case .contributors: "Artists & Contributors"
            case .boxSets: "Box Sets"
            case .importInbox: "Import Inbox"
            case .playlists: "Playlists"
            case .settings: "Settings"
            }
        }
        var symbol: String {
            switch self {
            case .albums: "square.stack"
            case .contributors: "person.2"
            case .boxSets: "shippingbox"
            case .importInbox: "tray"
            case .playlists: "music.note.list"
            case .settings: "gearshape"
            }
        }
    }

    @State private var selection: Section? = .albums

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationTitle("Music Library")
        } content: {
            List {
                if selection == .albums {
                    AlbumRow(
                        album: Album(
                            id: AlbumID(),
                            from: NewAlbum(title: "Your library is ready", editionLabel: "Add an album to begin")
                        )
                    )
                } else {
                    ContentUnavailableView(selection?.title ?? "Music Library", systemImage: selection?.symbol ?? "music.note")
                }
            }
            .navigationTitle(selection?.title ?? "Music Library")
        } detail: {
            ContentUnavailableView(
                "Select an album",
                systemImage: "opticaldisc",
                description: Text("The next slice will connect this SwiftUI shell to the local catalogue database.")
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Album", systemImage: "plus") { }
                    .help("Add an album")
            }
        }
    }
}
