import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MusicApplication
import MusicDomain
import MusicUIComponents

@main
struct MusicLibraryMacApp: App {
    @StateObject private var library = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Music Library") {
            LibraryShellView(library: library)
                .frame(minWidth: 980, minHeight: 640)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { Task { await library.flushPendingSnapshotPublication() } }
                }
        }
    }
}

private struct LibraryShellView: View {
    private enum AlbumSourceFilter: String, CaseIterable, Identifiable {
        case all, nas, local
        var id: Self { self }
        var title: String { switch self { case .all: "All Music"; case .nas: "NAS / iPad Music"; case .local: "This Mac Only" } }
    }
    private enum NavigationSection: Hashable, CaseIterable, Identifiable {
        case albums, contributors, locations, boxSets, importInbox, playlists, settings
        var id: Self { self }
        var title: String {
            switch self {
            case .albums: "Albums"
            case .contributors: "Contributors"
            case .locations: "Locations"
            case .boxSets: "Box Sets"
            case .importInbox: "Imports"
            case .playlists: "Playlists"
            case .settings: "Settings"
            }
        }
        var symbol: String {
            switch self {
            case .albums: "square.stack"
            case .contributors: "person.2"
            case .locations: "archivebox"
            case .boxSets: "shippingbox"
            case .importInbox: "tray"
            case .playlists: "music.note.list"
            case .settings: "gearshape"
            }
        }
    }
    private enum AlbumPresentation: String, CaseIterable, Identifiable {
        case grid, list
        var id: Self { self }
        var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
        var title: String { self == .grid ? "Grid" : "List" }
    }
    private enum AlbumSort: String, CaseIterable, Identifiable {
        case title, newest, recentlyAdded, rating
        var id: Self { self }
        var title: String {
            switch self {
            case .title: "Title"
            case .newest: "Release Year"
            case .recentlyAdded: "Recently Added"
            case .rating: "Rating"
            }
        }
    }

    @ObservedObject var library: LibraryStore
    @StateObject private var playback = PlaybackController()
    @State private var section: NavigationSection? = .albums
    @State private var selectedAlbumID: AlbumID?
    @State private var selectedContributorID: ContributorID?
    @State private var selectedBoxSetID: BoxSetID?
    @State private var selectedImportBatchID: ImportBatchID?
    @State private var importBatchToAnalyzeAfterScan: ImportBatchID?
    @State private var selectedPlaylistID: PlaylistID?
    @State private var searchText = ""
    @State private var albumSourceFilter: AlbumSourceFilter = .all
    @State private var albumPresentation: AlbumPresentation = .grid
    @State private var albumSort: AlbumSort = .title
    @State private var showsFavouriteAlbumsOnly = false
    @State private var contributorSearchText = ""
    @State private var showsAlbumEditor = false
    @State private var showsLocationEditor = false
    @State private var showsBoxSetEditor = false
    @State private var showsStorageRootPicker = false
    @State private var showsScanRootPicker = false
    @State private var showsPlaylistEditor = false
    @State private var albumToEdit: Album?
    @State private var playlistToRename: Playlist?
    @State private var metadataSelection: MetadataInspectionSelection?

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("Browse") {
                    sidebarRow(.albums)
                    sidebarRow(.contributors)
                    sidebarRow(.playlists)
                }
                Section("Collection") {
                    sidebarRow(.locations)
                    sidebarRow(.boxSets)
                }
                Section("Review") {
                    sidebarRow(.importInbox)
                }
                Section {
                    sidebarRow(.settings)
                }
            }
            .navigationTitle("Music Library")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } content: {
            content
                .navigationTitle(section?.title ?? "Music Library")
                .toolbar { toolbar }
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .overlay {
            if !library.isReady && library.errorMessage == nil {
                ProgressView("Opening catalogue…")
            }
        }
        .task {
            await library.start()
            let restoredItems = await library.playbackURLs(trackIDs: playback.queue.trackIDs)
            playback.restore(items: restoredItems)
        }
        .onChange(of: library.importBatches) { previous, current in
            // A retry creates a new audit batch. Select it immediately so the
            // Library Changes detail pane follows the rescan rather than
            // remaining attached to the historical batch it replaced.
            guard section == .importInbox else { return }
            let previousIDs = Set(previous.map(\.id))
            if let newlyCreated = current.first(where: { !previousIDs.contains($0.id) }) {
                selectedImportBatchID = newlyCreated.id
            } else if let selectedImportBatchID,
                      !current.contains(where: { $0.id == selectedImportBatchID }) {
                self.selectedImportBatchID = latestImportBatchesByRoot.first?.id
            }
        }
        .sheet(isPresented: $showsAlbumEditor) { AlbumEditor(library: library) }
        .sheet(isPresented: $showsLocationEditor) { LocationEditor(library: library) }
        .sheet(isPresented: $showsBoxSetEditor) { BoxSetEditor(library: library) }
        .sheet(isPresented: $showsScanRootPicker) { ScanRootPicker(library: library) }
        .sheet(isPresented: $showsPlaylistEditor) { PlaylistEditor(library: library) }
        .sheet(item: $albumToEdit) { album in EditAlbumEditor(library: library, album: album) }
        .sheet(item: $playlistToRename) { playlist in PlaylistRenameEditor(library: library, playlist: playlist) }
        .sheet(item: $metadataSelection) { selection in TrackMetadataInspector(library: library, selection: selection) }
        .fileImporter(isPresented: $showsStorageRootPicker, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { Task { do { try await library.addStorageRoot(url: url) } catch { library.presentError(error) } } }
        }
        .alert("Music Library", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.dismissError() } }
        )) {
            Button("OK", role: .cancel) { library.dismissError() }
        } message: {
            Text(library.errorMessage ?? "")
        }
        .alert("Playback", isPresented: Binding(
            get: { playback.errorMessage != nil },
            set: { if !$0 { playback.dismissError() } }
        )) {
            Button("OK", role: .cancel) { playback.dismissError() }
        } message: {
            Text(playback.errorMessage ?? "")
        }
        .safeAreaInset(edge: .bottom) {
            if playback.isPlaying || playback.currentTitle != "Nothing playing" {
                MiniPlayerBar(playback: playback) {
                    if let trackID = playback.currentTrackID {
                        metadataSelection = .init(trackID: trackID, title: playback.currentTitle)
                    }
                }
            }
        }
    }

    @ViewBuilder private func sidebarRow(_ item: NavigationSection) -> some View {
        Label(item.title, systemImage: item.symbol)
            .tag(item)
            .help(sidebarHelp(item))
    }

    private func sidebarHelp(_ item: NavigationSection) -> String {
        switch item {
        case .albums: "Browse and play the catalogue"
        case .contributors: "Browse artists, composers, and performers"
        case .playlists: "Create and play ordered track collections"
        case .locations: "Manage physical CD storage locations"
        case .boxSets: "Organize albums that belong to a box set"
        case .importInbox: "Review rescans, new files, and import proposals"
        case .settings: "Music folders, publishing, backups, and library health"
        }
    }

    private var repeatSystemImage: String {
        playback.queue.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var repeatAccessibilityLabel: String {
        switch playback.queue.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    private func cycleRepeatMode() {
        let nextMode: RepeatMode
        switch playback.queue.repeatMode {
        case .off: nextMode = .all
        case .all: nextMode = .one
        case .one: nextMode = .off
        }
        playback.setRepeatMode(nextMode)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .albums:
            AlbumBrowser(
                albums: displayedAlbums,
                selectedAlbumID: $selectedAlbumID,
                usesGrid: albumPresentation == .grid,
                artworkPaths: library.albumFrontArtworkPaths,
                localAlbumIDs: library.localAlbumIDs,
                publishedAlbumIDs: library.publishedAlbumIDs,
                onDelete: deleteAlbum
            )
            .searchable(text: $searchText, prompt: "Albums, editions, or catalogue numbers")
            .onChange(of: searchText) { _, value in Task { await library.search(value) } }
            .overlay {
                if library.isReady && displayedAlbums.isEmpty {
                    ContentUnavailableView("No matching albums", systemImage: "opticaldisc", description: Text("Change the music source filter or add an album."))
                }
            }
        case .locations:
            LocationList(library: library)
        case .contributors:
            List(filteredContributors, selection: $selectedContributorID) { contributor in
                VStack(alignment: .leading) {
                    Text(contributor.name)
                    if let sortName = contributor.sortName, sortName != contributor.name { Text(sortName).font(.caption).foregroundStyle(.secondary) }
                }.tag(contributor.id)
            }
            .searchable(text: $contributorSearchText, prompt: "Contributor name or sort name")
            .overlay { if library.isReady && library.contributors.isEmpty { ContentUnavailableView("No contributors", systemImage: "person.2", description: Text("Add contributors from an album or track credit.")) } }
        case .boxSets:
            List(library.boxSets, selection: $selectedBoxSetID) { box in
                VStack(alignment: .leading) {
                    Text(box.title).font(.headline)
                    if let edition = box.editionLabel, !edition.isEmpty { Text(edition).foregroundStyle(.secondary) }
                }.tag(box.id).contextMenu {
                    Button("Move Empty Box Set to Recently Deleted", role: .destructive) { Task { do { try await library.softDeleteEmptyBoxSet(box.id); if selectedBoxSetID == box.id { selectedBoxSetID = nil } } catch { library.presentError(error) } } }
                }
            }
            .overlay { if library.isReady && library.boxSets.isEmpty { ContentUnavailableView("No box sets", systemImage: "shippingbox", description: Text("Create a box set to group its member albums at one location.")) } }
        case .importInbox:
            List(latestImportBatchesByRoot, selection: $selectedImportBatchID) { batch in
                HStack(spacing: 10) {
                    Image(systemName: importBatchSymbol(batch))
                        .font(.title3)
                        .foregroundStyle(importBatchColor(batch))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(batch.sourceDescription ?? "Music folder").font(.headline).lineLimit(1)
                        Text("\(batch.candidateCount) audio files · \(batch.errorCount) errors · \(batch.status.rawValue.capitalized)")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 5)
                .tag(batch.id)
            }
            .overlay { if library.isReady && latestImportBatchesByRoot.isEmpty { ContentUnavailableView("No library changes", systemImage: "tray", description: Text("Rescan a registered music folder when you want to review new or changed albums.")) } }
        case .playlists:
            List(library.playlists, selection: $selectedPlaylistID) { playlist in
                HStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 30, height: 30)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                    Text(playlist.name).font(.headline).lineLimit(1)
                }
                    .padding(.vertical, 5)
                    .tag(playlist.id)
                    .contextMenu {
                        Button("Rename") { playlistToRename = playlist }
                        Button("Delete", role: .destructive) {
                            Task {
                                do {
                                    try await library.deletePlaylist(playlist.id)
                                    if selectedPlaylistID == playlist.id { selectedPlaylistID = nil }
                                } catch {
                                    library.presentError(error)
                                }
                            }
                        }
                    }
            }
            .overlay { if library.isReady && library.playlists.isEmpty { ContentUnavailableView("No playlists", systemImage: "music.note.list", description: Text("Create a playlist, then add tracks from an album.")) } }
        case .settings:
            List {
                Label("Overview", systemImage: "rectangle.grid.2x2")
                Label("Publishing and Backup", systemImage: "externaldrive.badge.timemachine")
                Label("Music Folders", systemImage: "externaldrive.connected.to.line.below")
                Label("Library Health", systemImage: "checkmark.shield")
                Label("Recovery and Activity", systemImage: "clock.arrow.circlepath")
            }
            .foregroundStyle(.secondary)
        default:
            ContentUnavailableView(section?.title ?? "Music Library", systemImage: section?.symbol ?? "music.note")
        }
    }

    private var filteredContributors: [Contributor] {
        let term = contributorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return library.contributors }
        return library.contributors.filter { $0.name.localizedCaseInsensitiveContains(term) || ($0.sortName?.localizedCaseInsensitiveContains(term) ?? false) }
    }

    private var scopedAlbums: [Album] {
        switch albumSourceFilter {
        case .all: library.albums
        case .nas: library.albums.filter { library.publishedAlbumIDs.contains($0.id) }
        case .local: library.albums.filter { library.localAlbumIDs.contains($0.id) }
        }
    }

    private var displayedAlbums: [Album] {
        let filtered = showsFavouriteAlbumsOnly ? scopedAlbums.filter(\.isFavourite) : scopedAlbums
        return filtered.sorted { lhs, rhs in
            switch albumSort {
            case .title:
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            case .newest:
                if lhs.releaseYear != rhs.releaseYear { return (lhs.releaseYear ?? Int.min) > (rhs.releaseYear ?? Int.min) }
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            case .recentlyAdded:
                return lhs.createdAt > rhs.createdAt
            case .rating:
                if lhs.rating != rhs.rating { return (lhs.rating ?? 0) > (rhs.rating ?? 0) }
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
        }
    }

    private func deleteAlbum(_ album: Album) {
        Task {
            do {
                try await library.softDeleteAlbum(album.id)
                if selectedAlbumID == album.id { selectedAlbumID = nil }
            } catch {
                library.presentError(error)
            }
        }
    }

    private var latestImportBatchesByRoot: [ImportBatch] {
        var seen = Set<StorageRootID>()
        return library.importBatches.filter { batch in
            guard let rootID = batch.storageRootID else { return true }
            return seen.insert(rootID).inserted
        }
    }

    private func importBatchSymbol(_ batch: ImportBatch) -> String {
        if batch.status == .scanning { return "arrow.triangle.2.circlepath" }
        if batch.status == .failed || batch.errorCount > 0 { return "exclamationmark.triangle.fill" }
        if batch.status == .cancelled { return "xmark.circle.fill" }
        return "checkmark.circle.fill"
    }

    private func importBatchColor(_ batch: ImportBatch) -> Color {
        if batch.status == .scanning { return .blue }
        if batch.status == .failed || batch.errorCount > 0 { return .orange }
        if batch.status == .cancelled { return .secondary }
        return .green
    }

    @ViewBuilder private var detail: some View {
        if section == .settings {
            StorageRootList(
                library: library,
                playback: playback,
                onShowAlbum: { albumID in
                    selectedAlbumID = albumID
                    section = .albums
                },
                onShowImportBatch: { batchID in
                    selectedImportBatchID = batchID
                    section = .importInbox
                }
            )
            .navigationTitle("Settings")
        } else if section == .contributors, let selectedContributorID, let contributor = library.contributors.first(where: { $0.id == selectedContributorID }) {
            ContributorDetail(library: library, contributor: contributor, onShowAlbum: { albumID in selectedAlbumID = albumID; section = .albums })
        } else if section == .boxSets, let selectedBoxSetID, let box = library.boxSets.first(where: { $0.id == selectedBoxSetID }) {
            BoxSetDetail(library: library, boxSet: box)
        } else if section == .importInbox, let selectedImportBatchID, let batch = library.importBatches.first(where: { $0.id == selectedImportBatchID }) {
            ImportBatchDetail(
                library: library,
                batch: batch,
                onRescanStarted: { self.selectedImportBatchID = $0 },
                onCombinedRescanRequested: { self.importBatchToAnalyzeAfterScan = $0 },
                analyzeMetadataAfterScan: importBatchToAnalyzeAfterScan == batch.id,
                onCombinedAnalysisFinished: {
                    if self.importBatchToAnalyzeAfterScan == batch.id {
                        self.importBatchToAnalyzeAfterScan = nil
                    }
                }
            )
        } else if section == .playlists, let selectedPlaylistID, let playlist = library.playlists.first(where: { $0.id == selectedPlaylistID }) {
            PlaylistDetail(library: library, playback: playback, playlist: playlist)
        } else if let selectedAlbumID, let album = library.albums.first(where: { $0.id == selectedAlbumID }) {
            AlbumDetail(library: library, playback: playback, album: album, locations: library.locations, onEdit: { albumToEdit = album })
        } else if section == .importInbox {
            ContentUnavailableView("Select a music folder", systemImage: "tray", description: Text("Choose a registered folder to review its latest scan and proposed changes."))
        } else if section == .playlists {
            ContentUnavailableView("Select a playlist", systemImage: "music.note.list", description: Text("Choose a playlist to play or organize its tracks."))
        } else if section == .contributors {
            ContentUnavailableView("Select a contributor", systemImage: "person.crop.circle", description: Text("Contributor credits and albums will appear here."))
        } else if section == .boxSets {
            ContentUnavailableView("Select a box set", systemImage: "shippingbox", description: Text("Box-set members and placement will appear here."))
        } else {
            ContentUnavailableView("Select an album", systemImage: "opticaldisc", description: Text("Album details will appear here."))
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if section == .albums {
            ToolbarItemGroup(placement: .automatic) {
                Picker("View", selection: $albumPresentation) {
                    ForEach(AlbumPresentation.allCases) { presentation in
                        Label(presentation.title, systemImage: presentation.symbol).tag(presentation)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Menu {
                    Picker("Source", selection: $albumSourceFilter) {
                        ForEach(AlbumSourceFilter.allCases) { filter in Text(filter.title).tag(filter) }
                    }
                    Divider()
                    Picker("Sort", selection: $albumSort) {
                        ForEach(AlbumSort.allCases) { sort in Text(sort.title).tag(sort) }
                    }
                    Divider()
                    Toggle("Favourites Only", isOn: $showsFavouriteAlbumsOnly)
                } label: {
                    Label("Filter and Sort", systemImage: activeAlbumFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .help("Filter and sort albums")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if section == .albums {
                Button("Add Physical Album", systemImage: "plus") {
                    showsAlbumEditor = true
                }
                .help("Add a physical album to the catalogue")
            } else {
                Button(section == .locations ? "Add Location" : section == .boxSets ? "Add Box Set" : section == .settings ? "Add Music Folder" : section == .importInbox ? "Rescan Music Folder" : section == .playlists ? "Add Playlist" : "Add Album", systemImage: "plus") {
                    switch section {
                    case .locations: showsLocationEditor = true
                    case .boxSets: showsBoxSetEditor = true
                    case .settings: showsStorageRootPicker = true
                    case .importInbox: showsScanRootPicker = true
                    case .playlists: showsPlaylistEditor = true
                    default: break
                    }
                }
            }
        }
    }

    private var activeAlbumFilter: Bool {
        albumSourceFilter != .all || showsFavouriteAlbumsOnly || albumSort != .title
    }
}

private struct AlbumBrowser: View {
    let albums: [Album]
    @Binding var selectedAlbumID: AlbumID?
    let usesGrid: Bool
    let artworkPaths: [AlbumID: String]
    let localAlbumIDs: Set<AlbumID>
    let publishedAlbumIDs: Set<AlbumID>
    let onDelete: (Album) -> Void

    var body: some View {
        if usesGrid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 18)], spacing: 22) {
                    ForEach(albums) { album in
                        AlbumCard(
                            album: album,
                            artworkPath: artworkPaths[album.id],
                            isLocal: localAlbumIDs.contains(album.id),
                            isPublished: publishedAlbumIDs.contains(album.id),
                            isSelected: selectedAlbumID == album.id
                        ) {
                            selectedAlbumID = album.id
                        }
                        .contextMenu { deleteButton(for: album) }
                    }
                }
                .padding(20)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        } else {
            List(albums, selection: $selectedAlbumID) { album in
                AlbumListRow(
                    album: album,
                    artworkPath: artworkPaths[album.id],
                    isLocal: localAlbumIDs.contains(album.id),
                    isPublished: publishedAlbumIDs.contains(album.id)
                )
                .tag(album.id)
                .contextMenu { deleteButton(for: album) }
            }
        }
    }

    @ViewBuilder private func deleteButton(for album: Album) -> some View {
        Button("Move to Recently Deleted", role: .destructive) { onDelete(album) }
    }
}

private struct AlbumCard: View {
    let album: Album
    let artworkPath: String?
    let isLocal: Bool
    let isPublished: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    AlbumArtworkImage(path: artworkPath)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                    if album.isFavourite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.pink, in: Circle())
                            .padding(8)
                            .accessibilityLabel("Favourite")
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.headline)
                        .lineLimit(2)
                    if let edition = album.editionLabel, !edition.isEmpty {
                        Text(edition).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if let releaseYear = album.releaseYear { Text(String(releaseYear)) }
                        Spacer(minLength: 4)
                        AlbumSourceBadges(hasCD: album.hasCD, isLocal: isLocal, isPublished: isPublished)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(album.displayTitle)
        .accessibilityHint("Open album details")
    }
}

private struct AlbumListRow: View {
    let album: Album
    let artworkPath: String?
    let isLocal: Bool
    let isPublished: Bool

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtworkImage(path: artworkPath)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(album.title).font(.headline).lineLimit(1)
                    if album.isFavourite { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                }
                if let edition = album.editionLabel, !edition.isEmpty {
                    Text(edition).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let releaseYear = album.releaseYear { Text(String(releaseYear)) }
                    AlbumSourceBadges(hasCD: album.hasCD, isLocal: isLocal, isPublished: isPublished)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct AlbumArtworkImage: View {
    let path: String?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.5), Color.purple.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
        }
        .clipped()
        .task(id: path) {
            image = nil
            guard let path else { return }
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: URL(fileURLWithPath: path)) }.value
            if let data { image = NSImage(data: data) }
        }
    }
}

private struct AlbumSourceBadges: View {
    let hasCD: Bool
    let isLocal: Bool
    let isPublished: Bool

    var body: some View {
        HStack(spacing: 4) {
            if hasCD { badge("CD", symbol: "opticaldisc") }
            if isLocal { badge("Mac", symbol: "laptopcomputer") }
            if isPublished { badge("NAS", symbol: "externaldrive.connected.to.line.below") }
        }
    }

    private func badge(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .labelStyle(.iconOnly)
            .padding(4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            .help(title)
            .accessibilityLabel(title)
    }
}

private struct MiniPlayerBar: View {
    @ObservedObject var playback: PlaybackController
    let showMetadata: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if playback.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: playback.isPlaying ? "waveform" : "music.note")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(playerTitle).font(.headline).lineLimit(1)
                Text(playback.isLoading ? loadingDetail : (playback.audioFormatDescription ?? "Ready to play"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: 320, alignment: .leading)

            Button("Previous", systemImage: "backward.fill") { playback.previous() }.playerIconStyle()
            Button(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill") { playback.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(playback.isLoading)
            Button("Next", systemImage: "forward.fill") { playback.next() }.playerIconStyle()

            VStack(spacing: 2) {
                if playback.isLoading, let progress = playback.loadingProgress {
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(.linear)
                    HStack {
                        Text("\(Int((progress * 100).rounded()))%")
                        Spacer()
                        if let remaining = playback.loadingEstimatedTimeRemaining {
                            Text("About \(remainingTime(remaining)) remaining")
                        } else if playback.isFinalizingLoad {
                            Text("Finalizing playback")
                        } else {
                            Text("Estimating time remaining")
                        }
                    }
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Slider(value: Binding(
                        get: { playback.duration > 0 ? playback.currentTime / playback.duration : 0 },
                        set: { playback.seek(to: $0) }
                    ), in: 0...1)
                    .disabled(playback.duration <= 0 || playback.isLoading)
                    HStack {
                        Text(time(playback.currentTime))
                        Spacer()
                        Text(time(playback.duration))
                    }
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 140, maxWidth: .infinity)

            if playback.currentTrackID != nil {
                Button("Show extracted metadata", systemImage: "info.circle", action: showMetadata).playerIconStyle()
            }
            Button(playback.queue.isShuffled ? "Turn Shuffle Off" : "Shuffle Queue", systemImage: "shuffle") { playback.toggleShuffle() }
                .playerToggleStyle(active: playback.queue.isShuffled)
            Button(repeatLabel, systemImage: playback.queue.repeatMode == .one ? "repeat.1" : "repeat") { cycleRepeatMode() }
                .playerToggleStyle(active: playback.queue.repeatMode != .off)
            Image(systemName: playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { playback.volume }, set: { playback.setVolume(Float($0)) }), in: 0...1)
                .frame(width: 80)
            Button("Stop", systemImage: "stop.fill") { playback.stop() }.playerIconStyle()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var repeatLabel: String {
        switch playback.queue.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    private var playerTitle: String {
        if playback.isLoading {
            return "Now Loading \u{201c}\(playback.loadingTitle ?? playback.currentTitle)\u{201d}\u{2026}"
        }
        return playback.currentTitle
    }

    private var loadingDetail: String {
        if playback.isFinalizingLoad { return "DSF conversion complete — preparing playback" }
        if playback.loadingProgress != nil { return "Converting DSF to high-resolution PCM" }
        return "Opening audio from its music folder"
    }

    private func cycleRepeatMode() {
        switch playback.queue.repeatMode {
        case .off: playback.setRepeatMode(.all)
        case .all: playback.setRepeatMode(.one)
        case .one: playback.setRepeatMode(.off)
        }
    }

    private func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let whole = Int(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    private func remainingTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "a moment" }
        let rounded = Int(seconds.rounded())
        if rounded < 60 { return "\(max(1, rounded)) sec" }
        let minutes = rounded / 60
        let remainder = rounded % 60
        return remainder == 0 ? "\(minutes) min" : "\(minutes)m \(remainder)s"
    }
}

private extension View {
    func playerIconStyle() -> some View {
        labelStyle(.iconOnly).buttonStyle(.plain).font(.title3).padding(5)
    }

    func playerToggleStyle(active: Bool) -> some View {
        labelStyle(.iconOnly)
            .buttonStyle(.borderedProminent)
            .tint(active ? .accentColor : Color.gray.opacity(0.18))
    }
}

private struct ContributorDetail: View {
    @ObservedObject var library: LibraryStore
    let contributor: Contributor
    let onShowAlbum: (AlbumID) -> Void
    @State private var albums: [Album] = []

    var body: some View {
        List {
            Section("Contributor") {
                Text(contributor.name)
                if let sortName = contributor.sortName, sortName != contributor.name { LabeledContent("Sort name", value: sortName) }
            }
            Section("Credited albums") {
                if albums.isEmpty { Text("No active album credits").foregroundStyle(.secondary) }
                ForEach(albums) { album in
                    Button { onShowAlbum(album.id) } label: {
                        VStack(alignment: .leading) {
                            Text(album.displayTitle)
                            Text("Includes album or track credits").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(contributor.name)
        .task(id: contributor.id) { await loadAlbums() }
    }

    private func loadAlbums() async {
        do {
            albums = try await library.albums(creditedTo: contributor.id)
        } catch {
            library.presentError(error)
        }
    }
}

private struct CandidateMetadataSummary: View {
    let candidate: ImportCandidate
    let fallback: String
    var body: some View {
        let summary = candidate.metadata?.rawTags.map { "\($0.key): \($0.value)" }.sorted().joined(separator: " · ") ?? fallback
        Text(summary).font(.caption).foregroundStyle(.secondary)
    }
}

private struct CandidateRow: View {
    let candidate: ImportCandidate
    var body: some View {
        if let payload = candidate.payload {
            VStack(alignment: .leading, spacing: 5) {
                Label(payload.relativePath, systemImage: "waveform")
                    .lineLimit(2)
                DisclosureGroup("Technical details") {
                    CandidateMetadataSummary(candidate: candidate, fallback: payload.contentTypeIdentifier)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else {
            Label(candidate.errorMessage ?? "Unreadable item", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScanMetric: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline.monospacedDigit()).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func proposalSummary(_ proposal: ImportReleaseProposal) -> String {
    let artist = proposal.artist ?? "Unknown artist"
    let confidence = Int((proposal.confidence * 100).rounded())
    return "\(artist) · \(proposal.discCount) disc(s) · \(proposal.trackCount) files · \(confidence)% confidence"
}

private func relinkConfirmationMessage(_ proposal: AssetRelinkProposal) -> String {
    "Change the catalogue path from \(proposal.currentPath) to \(proposal.proposedPath). No audio file will be moved or renamed."
}

private struct StorageRootList: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var playback: PlaybackController
    let onShowAlbum: (AlbumID) -> Void
    let onShowImportBatch: (ImportBatchID) -> Void
    @State private var rootToRename: StorageRoot?
    @State private var relinkProposalToApply: AssetRelinkProposal?
    @State private var restoreManifestURL: URL?
    @State private var albumToPurge: Album?
    @State private var playlistToPurge: Playlist?
    @State private var showsSnapshotDestinationPicker = false
    @State private var showsMasterRestorePicker = false
    @State private var dsfCacheMaximumGiB = DSFPlaybackCachePreferences.maximumGiB()
    @State private var dsfCacheStatus: DSFPlaybackCacheStatus?
    @State private var isManagingDSFCache = false
    @State private var showsClearDSFCacheConfirmation = false
    @State private var cleanupPreview: CatalogueCleanupPreview?
    @State private var cleanupOptions = CatalogueCleanupOptions()
    @State private var showsCleanupReview = false
    @State private var completeArchiveToRestore: URL?
    @State private var showsCatalogueReset = false
    @State private var isRunningCatalogueMaintenance = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    SettingsStatusCard(
                        symbol: "square.stack.3d.up",
                        title: "Catalogue",
                        value: "Revision \(library.catalogueRevision)",
                        detail: library.isSnapshotPublishPending ? "Unpublished changes" : "Up to date",
                        tint: library.isSnapshotPublishPending ? .orange : .green
                    )
                    SettingsStatusCard(
                        symbol: "externaldrive",
                        title: "Music Folders",
                        value: String(library.storageRoots.count),
                        detail: "\(library.storageRoots.filter { $0.status == .available }.count) available",
                        tint: library.storageRoots.contains { $0.status != .available } ? .orange : .blue
                    )
                    SettingsStatusCard(
                        symbol: library.libraryHealthIssues.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                        title: "Library Health",
                        value: library.libraryHealthIssues.isEmpty ? "Healthy" : "\(library.libraryHealthIssues.count) items",
                        detail: library.libraryHealthIssues.isEmpty ? "No repairs detected" : "Review below",
                        tint: library.libraryHealthIssues.isEmpty ? .green : .orange
                    )
                }
                .padding(.vertical, 8)
            }

            Section {
                Text(library.snapshotPublishStatus).foregroundStyle(.secondary)
                if let path = library.snapshotDestinationPath { Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Text("Catalogue revision \(library.catalogueRevision) · last published \(library.lastPublishedRevision.map(String.init) ?? "never")\(library.isSnapshotPublishPending ? " · pending" : "")").font(.caption).foregroundStyle(.secondary)
                if let lastPublishedAt = library.lastPublishedAt { Text("Last successful publish \(lastPublishedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                if let failure = library.lastSnapshotPublishFailure { Text(failure).font(.caption).foregroundStyle(.red) }
                Button("Choose Snapshot Destination") { showsSnapshotDestinationPicker = true }
                Button(library.lastSnapshotPublishFailure == nil ? "Publish Now" : "Retry Publish") {
                    Task {
                        do { try await library.publishSnapshotNow() }
                        catch { library.presentError(error) }
                    }
                }.disabled(library.snapshotDestinationPath == nil)
                Divider()
                Text(library.masterBackupStatus).font(.caption).foregroundStyle(.secondary)
                Button("Back Up Master Database") {
                    Task {
                        do { try await library.createMasterBackupNow() }
                        catch { library.presentError(error) }
                    }
                }.disabled(library.snapshotDestinationPath == nil)
                Button("Restore Master Backup…", role: .destructive) { showsMasterRestorePicker = true }
            } header: {
                Label("Publishing and Backup", systemImage: "externaldrive.badge.timemachine")
            }
            Section {
                Text("Export a portable JSON view of the current catalogue. Source media files are never copied.").font(.caption).foregroundStyle(.secondary)
                Button("Export Catalogue JSON…", systemImage: "square.and.arrow.up") { exportCatalogue() }
                Button("Export Catalogue CSV…", systemImage: "tablecells") { exportCatalogueCSV() }
            } header: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            Section {
                if isRunningCatalogueMaintenance {
                    ProgressView("Working on catalogue recovery data…")
                        .controlSize(.small)
                }
                Text(library.catalogueMaintenanceStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Review Safe Cleanup…", systemImage: "sparkles") {
                    loadCleanupPreview()
                }
                Button("Export Complete Catalogue Archive…", systemImage: "archivebox") {
                    exportCompleteCatalogueArchive()
                }
                Button("Restore Complete Catalogue Archive…", systemImage: "arrow.counterclockwise.circle", role: .destructive) {
                    chooseCompleteCatalogueArchive()
                }
                Divider()
                Button("Reset Catalogue…", systemImage: "trash.slash", role: .destructive) {
                    showsCatalogueReset = true
                }
                Text("Safe Cleanup removes only superseded scan history and records that are not linked anywhere. Complete archives contain the database and app-managed artwork, but never source audio files. Reset preserves registered music folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Catalogue Maintenance", systemImage: "wrench.and.screwdriver")
            }
            .disabled(isRunningCatalogueMaintenance)
            Section {
                Text("DSF files are converted to replaceable high-resolution PCM WAV files for playback. Original music files are never changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let dsfCacheStatus {
                    ProgressView(
                        value: min(Double(dsfCacheStatus.usageBytes), Double(dsfCacheStatus.maximumBytes)),
                        total: max(1, Double(dsfCacheStatus.maximumBytes))
                    )
                    HStack {
                        Text("\(formattedBytes(dsfCacheStatus.usageBytes)) of \(dsfCacheMaximumGiB) GB used")
                        Spacer()
                        Text("\(dsfCacheStatus.fileCount) cached conversion\(dsfCacheStatus.fileCount == 1 ? "" : "s")")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView("Checking cache…")
                        .controlSize(.small)
                }
                Stepper(
                    "Maximum cache size: \(dsfCacheMaximumGiB) GB",
                    value: $dsfCacheMaximumGiB,
                    in: DSFPlaybackCachePreferences.allowedMaximumGiB
                )
                .onChange(of: dsfCacheMaximumGiB) { _, newValue in
                    updateDSFCacheLimit(newValue)
                }
                Button("Clear DSF Cache…", systemImage: "trash", role: .destructive) {
                    showsClearDSFCacheConfirmation = true
                }
                Text("When the limit is exceeded, the least recently used conversions are removed automatically. A deleted conversion is recreated the next time its DSF track is played.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("DSF Playback Cache", systemImage: "waveform.badge.magnifyingglass")
            }
            .disabled(isManagingDSFCache || playback.isLoading)
            Section {
                Button("Recheck Library Health", systemImage: "arrow.clockwise") {
                    Task {
                        do { try await library.recheckLibraryHealth() }
                        catch { library.presentError(error) }
                    }
                }
                Button("Verify Asset Fingerprints", systemImage: "checkmark.shield") {
                    Task {
                        do { try await library.verifyFingerprints() }
                        catch { library.presentError(error) }
                    }
                }
                if library.storageRoots.isEmpty {
                    ContentUnavailableView("No music folders", systemImage: "externaldrive", description: Text("Add a local or NAS folder. The app saves access permission, not NAS credentials."))
                }
                ForEach(library.storageRoots) { root in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: symbol(for: root.status)).foregroundStyle(color(for: root.status))
                            VStack(alignment: .leading) {
                                Text(root.displayName).font(.headline)
                                Text(root.lastKnownPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(label(for: root.status)).font(.caption).foregroundStyle(color(for: root.status))
                        }
                        HStack {
                            Picker("Use", selection: Binding(get: { root.scope }, set: { scope in
                                Task { do { try await library.updateStorageRootScope(root.id, to: scope) } catch { library.presentError(error) } }
                            })) {
                                ForEach(StorageRootScope.allCases, id: \.self) { scope in Text(scope.displayName).tag(scope) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            Button("Rescan", systemImage: "arrow.clockwise") {
                                Task { do { _ = try await library.startImportScan(rootID: root.id) } catch { library.presentError(error) } }
                            }
                            .disabled(root.status != .available)
                            if let lastScan = latestBatch(for: root.id) {
                                Text("Last scan \(lastScan.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Rename") { rootToRename = root }
                        Button("Check Access") {
                            Task {
                                do { try await library.refreshStorageRootAccess() }
                                catch { library.presentError(error) }
                            }
                        }
                        Divider()
                        Button("Remove", role: .destructive) {
                            Task {
                                do { try await library.deleteStorageRoot(root.id) }
                                catch { library.presentError(error) }
                            }
                        }
                    }
                }
            } header: {
                Label("Music Folders", systemImage: "externaldrive.connected.to.line.below")
            }
            if !library.deletedAlbums.isEmpty {
                Section("Recently Deleted") {
                    ForEach(library.deletedAlbums) { album in
                        HStack {
                            VStack(alignment: .leading) { Text(album.displayTitle); Text("Restore returns this album and its existing catalogue relationships.").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Restore") { Task { do { try await library.restoreAlbum(album.id) } catch { library.presentError(error) } } }
                            Button("Permanently Remove…", role: .destructive) { albumToPurge = album }
                        }
                    }
                }
            }
            if !library.deletedPlaylists.isEmpty {
                Section("Recently Deleted Playlists") {
                    ForEach(library.deletedPlaylists) { playlist in
                        HStack {
                            VStack(alignment: .leading) { Text(playlist.name); Text("Restore returns this playlist with its saved ordered items.").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Restore") { Task { do { try await library.restorePlaylist(playlist.id) } catch { library.presentError(error) } } }
                            Button("Permanently Remove…", role: .destructive) { playlistToPurge = playlist }
                        }
                    }
                }
            }
            if !library.deletedBoxSets.isEmpty {
                Section("Recently Deleted Empty Box Sets") {
                    ForEach(library.deletedBoxSets) { box in
                        HStack {
                            VStack(alignment: .leading) { Text(box.title); Text("Restore returns this empty box set at its saved location.").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Restore") { Task { do { try await library.restoreBoxSet(box.id) } catch { library.presentError(error) } } }
                        }
                    }
                }
            }
            Section {
                if library.libraryHealthIssues.isEmpty {
                    Label("No catalogue repair items are currently detected.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(library.libraryHealthIssues) { issue in
                        VStack(alignment: .leading) {
                            Label(issue.albumTitle, systemImage: healthSymbol(for: issue.kind))
                            Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                            Button("Show Album") { onShowAlbum(issue.albumID) }
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Label("Library Health", systemImage: "checkmark.shield")
            }
            if !importBatchesNeedingAttention.isEmpty {
                Section("Import Inbox Attention") {
                    ForEach(importBatchesNeedingAttention) { batch in
                        VStack(alignment: .leading) {
                            Label(batch.sourceDescription ?? "Music folder", systemImage: "tray.and.arrow.down.fill")
                            Text(importAttentionDetail(batch)).font(.caption).foregroundStyle(.secondary)
                            Button("Review Import") { onShowImportBatch(batch.id) }
                                .font(.caption)
                        }
                    }
                }
            }
            if !library.duplicateAssets.isEmpty {
                Section("Possible duplicate assets") {
                    ForEach(library.duplicateAssets, id: \.contentHash) { duplicate in
                        VStack(alignment: .leading) {
                            Text("\(duplicate.paths.count) files share one content hash")
                            ForEach(duplicate.paths, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }
            }
            if !library.relinkProposals.isEmpty {
                Section("Relink proposals") {
                    ForEach(library.relinkProposals) { proposal in
                        VStack(alignment: .leading) {
                            Text(proposal.currentPath).font(.caption)
                            Text("Proposed: \(proposal.proposedPath)").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Apply Catalogue Path") { relinkProposalToApply = proposal }
                                Button("Discard", role: .destructive) {
                                    Task {
                                        do { try await library.discardRelinkProposal(proposal.id) }
                                        catch { library.presentError(error) }
                                    }
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            if !library.recentCatalogueActivity.isEmpty {
                Section("Recent Catalogue Activity") {
                    Text("Each row records a committed catalogue revision. Edited fields show the previous and new value; older operations may show only the revision marker.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(library.recentCatalogueActivity) { activity in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                if activity.isRevisionMarker {
                                    Text("Revision \(activity.revision)")
                                } else {
                                    Text("\(activity.entityType.capitalized) · \(activity.fieldName.replacingOccurrences(of: "_", with: " "))")
                                    Text("\(activity.oldValue ?? "—") → \(activity.newValue ?? "—")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text("Revision \(activity.revision)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(activity.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $showsSnapshotDestinationPicker, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { do { try library.setSnapshotDestination(url) } catch { library.presentError(error) } }
        }
        .fileImporter(isPresented: $showsMasterRestorePicker, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result { restoreManifestURL = url }
        }
        .confirmationDialog("Permanently remove catalogue record?", isPresented: Binding(get: { albumToPurge != nil }, set: { if !$0 { albumToPurge = nil } }), titleVisibility: .visible) {
            if let album = albumToPurge {
                Button("Remove Album, Tracks, and Asset References", role: .destructive) {
                    Task {
                        do { try await library.permanentlyDeleteAlbum(album.id); albumToPurge = nil }
                        catch { library.presentError(error) }
                    }
                }
            }
        } message: {
            Text("This permanently removes the deleted catalogue album, its tracks, and its stored NAS file references. It never deletes or changes the source audio files.")
        }
        .confirmationDialog("Permanently remove playlist?", isPresented: Binding(get: { playlistToPurge != nil }, set: { if !$0 { playlistToPurge = nil } }), titleVisibility: .visible) {
            if let playlist = playlistToPurge {
                Button("Remove Playlist and Its Items", role: .destructive) {
                    Task {
                        do { try await library.permanentlyDeletePlaylist(playlist.id); playlistToPurge = nil }
                        catch { library.presentError(error) }
                    }
                }
            }
        } message: {
            Text("This permanently removes the deleted playlist and its ordered entries. It never removes catalogue tracks or source audio files.")
        }
        .confirmationDialog("Restore master database?", isPresented: Binding(get: { restoreManifestURL != nil }, set: { if !$0 { restoreManifestURL = nil } }), titleVisibility: .visible) {
            if let manifestURL = restoreManifestURL {
                Button("Restore Verified Backup", role: .destructive) {
                    Task {
                        do { try await library.restoreMasterBackup(from: manifestURL); restoreManifestURL = nil }
                        catch { library.presentError(error) }
                    }
                }
            }
        } message: {
            Text("The selected backup will be verified first. The current master database will be kept in the local Recovery folder before replacement.")
        }
        .confirmationDialog("Restore complete catalogue archive?", isPresented: Binding(get: { completeArchiveToRestore != nil }, set: { if !$0 { completeArchiveToRestore = nil } }), titleVisibility: .visible) {
            if let archiveURL = completeArchiveToRestore {
                Button("Verify and Restore Archive", role: .destructive) {
                    isRunningCatalogueMaintenance = true
                    Task {
                        do {
                            try await library.restoreCompleteCatalogueArchive(from: archiveURL)
                            completeArchiveToRestore = nil
                        } catch {
                            library.presentError(error)
                        }
                        isRunningCatalogueMaintenance = false
                    }
                }
            }
        } message: {
            Text("The archive database and every managed artwork file are checksum-verified before replacement. The current catalogue is archived locally first. Source audio files are never changed.")
        }
        .confirmationDialog("Apply catalogue path?", isPresented: Binding(get: { relinkProposalToApply != nil }, set: { if !$0 { relinkProposalToApply = nil } }), titleVisibility: .visible) {
            if let proposal = relinkProposalToApply {
                Button("Apply Catalogue Path") {
                    Task {
                        do {
                            try await library.applyRelinkProposal(proposal.id)
                            relinkProposalToApply = nil
                        } catch {
                            library.presentError(error)
                        }
                    }
                }
            }
        } message: {
            Text(relinkProposalToApply.map(relinkConfirmationMessage) ?? "")
        }
        .confirmationDialog("Clear DSF playback cache?", isPresented: $showsClearDSFCacheConfirmation, titleVisibility: .visible) {
            Button("Clear Cached Conversions", role: .destructive) {
                clearDSFCache()
            }
        } message: {
            Text("This removes replaceable PCM conversions only. Original DSF files are never changed. A conversion currently playing is kept until it is no longer in use.")
        }
        .sheet(item: $rootToRename) { root in StorageRootRenameEditor(library: library, root: root) }
        .sheet(isPresented: $showsCleanupReview) {
            if let cleanupPreview {
                CatalogueCleanupEditor(
                    preview: cleanupPreview,
                    options: $cleanupOptions,
                    isRunning: isRunningCatalogueMaintenance,
                    onCancel: { showsCleanupReview = false },
                    onCleanup: { performCleanup() }
                )
            }
        }
        .sheet(isPresented: $showsCatalogueReset) {
            CatalogueResetEditor(
                isRunning: isRunningCatalogueMaintenance,
                onCancel: { showsCatalogueReset = false },
                onReset: { confirmation in resetCatalogue(confirmation: confirmation) }
            )
        }
        .task {
            await refreshDSFCacheStatus()
        }
    }

    private func updateDSFCacheLimit(_ value: Int) {
        isManagingDSFCache = true
        Task {
            do {
                dsfCacheStatus = try await playback.setDSFPlaybackCacheMaximumGiB(value)
            } catch {
                dsfCacheMaximumGiB = DSFPlaybackCachePreferences.maximumGiB()
                library.presentError(error)
            }
            isManagingDSFCache = false
        }
    }

    private func clearDSFCache() {
        isManagingDSFCache = true
        Task {
            do {
                dsfCacheStatus = try await playback.clearDSFPlaybackCache()
            } catch {
                library.presentError(error)
            }
            isManagingDSFCache = false
        }
    }

    private func refreshDSFCacheStatus() async {
        do {
            dsfCacheMaximumGiB = DSFPlaybackCachePreferences.maximumGiB()
            dsfCacheStatus = try await playback.dsfPlaybackCacheStatus()
        } catch {
            library.presentError(error)
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }

    private func healthSymbol(for kind: LibraryHealthKind) -> String {
        switch kind {
        case .offline: "externaldrive.badge.exclamationmark"
        case .missingArtwork: "photo.badge.exclamationmark"
        default: "exclamationmark.triangle"
        }
    }

    private var importBatchesNeedingAttention: [ImportBatch] {
        library.importBatches.filter { $0.status == .failed || $0.status == .cancelled || $0.errorCount > 0 }
    }

    private func latestBatch(for rootID: StorageRootID) -> ImportBatch? {
        library.importBatches.first(where: { $0.storageRootID == rootID })
    }

    private func importAttentionDetail(_ batch: ImportBatch) -> String {
        if batch.status == .failed { return batch.errorSummary ?? "The scan failed. Review it and retry when ready." }
        if batch.status == .cancelled { return "The scan was cancelled after \(batch.processedCount) item(s). Review it or retry the scan." }
        return "\(batch.errorCount) scan error(s) were recorded among \(batch.processedCount) processed item(s)."
    }

    private func label(for status: StorageRootStatus) -> String { switch status { case .available: "Available"; case .offline: "Offline"; case .permissionRequired: "Permission required" } }
    private func symbol(for status: StorageRootStatus) -> String { switch status { case .available: "checkmark.circle.fill"; case .offline: "wifi.slash"; case .permissionRequired: "lock.circle" } }
    private func color(for status: StorageRootStatus) -> Color { switch status { case .available: .green; case .offline: .orange; case .permissionRequired: .red } }
    private func exportCatalogue() {
        let panel = NSSavePanel()
        panel.title = "Export Catalogue JSON"
        panel.nameFieldStringValue = "MusicLibraryCatalogue.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { do { try await library.exportCatalogue(to: url) } catch { library.presentError(error) } }
    }
    private func exportCatalogueCSV() {
        let panel = NSSavePanel()
        panel.title = "Export Catalogue CSV"
        panel.nameFieldStringValue = "MusicLibraryCatalogue.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { do { try await library.exportCatalogueCSV(to: url) } catch { library.presentError(error) } }
    }

    private func loadCleanupPreview() {
        isRunningCatalogueMaintenance = true
        Task {
            do {
                cleanupPreview = try await library.catalogueCleanupPreview()
                cleanupOptions = .init()
                showsCleanupReview = true
            } catch {
                library.presentError(error)
            }
            isRunningCatalogueMaintenance = false
        }
    }

    private func performCleanup() {
        isRunningCatalogueMaintenance = true
        Task {
            do {
                _ = try await library.performCatalogueCleanup(cleanupOptions)
                showsCleanupReview = false
                cleanupPreview = nil
            } catch {
                library.presentError(error)
            }
            isRunningCatalogueMaintenance = false
        }
    }

    private func exportCompleteCatalogueArchive() {
        let panel = NSOpenPanel()
        panel.title = "Choose Complete Catalogue Archive Destination"
        panel.prompt = "Export Here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isRunningCatalogueMaintenance = true
        Task {
            do { _ = try await library.exportCompleteCatalogueArchive(to: url) }
            catch { library.presentError(error) }
            isRunningCatalogueMaintenance = false
        }
    }

    private func chooseCompleteCatalogueArchive() {
        let panel = NSOpenPanel()
        panel.title = "Choose Complete Catalogue Archive"
        panel.prompt = "Choose Archive"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        completeArchiveToRestore = url
    }

    private func resetCatalogue(confirmation: String) {
        isRunningCatalogueMaintenance = true
        Task {
            do {
                _ = try await library.resetCatalogue(confirmation: confirmation)
                showsCatalogueReset = false
            } catch {
                library.presentError(error)
            }
            isRunningCatalogueMaintenance = false
        }
    }
}

private struct CatalogueCleanupEditor: View {
    let preview: CatalogueCleanupPreview
    @Binding var options: CatalogueCleanupOptions
    let isRunning: Bool
    let onCancel: () -> Void
    let onCleanup: () -> Void

    private var selectedCount: Int {
        (options.removeSupersededImportBatches ? preview.supersededImportBatchCount : 0)
            + (options.removeOrphanContributors ? preview.orphanContributorCount : 0)
            + (options.removeUnusedLocations ? preview.unusedLocationCount : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Safe Catalogue Cleanup", systemImage: "sparkles")
                .font(.title2.bold())
            Text("Review exactly what will be removed. A complete local recovery archive is created first. Albums, tracks, playlists, registered music folders, artwork in use, and source audio are not removed.")
                .foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $options.removeSupersededImportBatches) {
                        cleanupRow("Old completed scan history", count: preview.supersededImportBatchCount, detail: "Keeps the newest completed result for each registered folder.")
                    }
                    Divider()
                    Toggle(isOn: $options.removeOrphanContributors) {
                        cleanupRow("Unlinked contributors", count: preview.orphanContributorCount, detail: "Only names with no album or track credit.")
                    }
                    Divider()
                    Toggle(isOn: $options.removeUnusedLocations) {
                        cleanupRow("Unused physical locations", count: preview.unusedLocationCount, detail: "Only locations that contain no album, box set, or used child location.")
                    }
                }
                .padding(6)
            }
            Spacer()
            HStack {
                Text("\(selectedCount) record\(selectedCount == 1 ? "" : "s") selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create Recovery Archive and Clean Up", action: onCleanup)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCount == 0 || isRunning)
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 430)
    }

    private func cleanupRow(_ title: String, count: Int, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title); Spacer(); Text(String(count)).monospacedDigit().foregroundStyle(.secondary) }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CatalogueResetEditor: View {
    @State private var confirmation = ""
    let isRunning: Bool
    let onCancel: () -> Void
    let onReset: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Reset Catalogue", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.red)
            Text("This clears albums, tracks, playlists, contributors, locations, box sets, import history, and managed artwork from the live catalogue. Registered local and NAS music folders are preserved. Source audio files are never deleted or changed.")
            Text("A complete recovery archive is created automatically before reset.")
                .foregroundStyle(.secondary)
            Text("Type RESET to continue:").font(.headline)
            TextField("RESET", text: $confirmation)
                .textFieldStyle(.roundedBorder)
            Spacer()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Archive and Reset Catalogue", role: .destructive) { onReset(confirmation) }
                    .disabled(confirmation != "RESET" || isRunning)
            }
        }
        .padding(24)
        .frame(minWidth: 580, minHeight: 330)
    }
}

private struct SettingsStatusCard: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct StorageRootRenameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let root: StorageRoot
    @State private var name: String

    init(library: LibraryStore, root: StorageRoot) { self.library = library; self.root = root; _name = State(initialValue: root.displayName) }

    var body: some View {
        Form { TextField("Folder name", text: $name) }
            .padding().frame(width: 360)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.nilIfBlank == nil) } }
    }

    private func save() { Task { do { try await library.renameStorageRoot(root.id, to: name); dismiss() } catch { library.presentError(error) } } }
}

private struct ScanRootPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    @State private var showsChildFolderPicker = false

    var body: some View {
        NavigationStack {
            List(library.storageRoots) { root in
                Button { scan(root) } label: {
                    HStack { VStack(alignment: .leading) { Text(root.displayName); Text(root.lastKnownPath).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Text(root.status.rawValue).font(.caption).foregroundStyle(root.status == .available ? .green : .secondary) }
                }
                .disabled(root.status != .available)
            }
            .navigationTitle("Choose Music Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Scan Album Folder…", systemImage: "folder") { showsChildFolderPicker = true } }
            }
        }
        .frame(width: 520, height: 360)
        .fileImporter(isPresented: $showsChildFolderPicker, allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else { return }
            Task {
                do {
                    _ = try await library.startImportScan(containing: url)
                    dismiss()
                } catch {
                    library.presentError(error)
                }
            }
        }
    }

    private func scan(_ root: StorageRoot) { Task { do { _ = try await library.startImportScan(rootID: root.id); dismiss() } catch { library.presentError(error) } } }
}

private struct PlaylistEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    @State private var name = ""
    var body: some View { Form { TextField("Playlist name", text: $name) }.padding().frame(width: 360).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Create") { Task { do { try await library.addPlaylist(name: name); dismiss() } catch { library.presentError(error) } } }.disabled(name.nilIfBlank == nil) } } }
}

private struct PlaylistRenameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let playlist: Playlist
    @State private var name: String
    @State private var errorMessage: String?

    init(library: LibraryStore, playlist: Playlist) {
        self.library = library
        self.playlist = playlist
        _name = State(initialValue: playlist.name)
    }

    var body: some View {
        Form { TextField("Playlist name", text: $name) }
            .padding().frame(width: 360)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.nilIfBlank == nil) }
            }
            .alert("Unable to rename playlist", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }

    private func save() {
        Task {
            do {
                try await library.renamePlaylist(playlist.id, to: name)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PlaylistDetail: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var playback: PlaybackController
    let playlist: Playlist
    @State private var items: [PlaylistItem] = []
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack(spacing: 18) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 42))
                        .foregroundStyle(.tint)
                        .frame(width: 92, height: 92)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(playlist.name).font(.largeTitle.bold())
                        Text("\(items.count) track\(items.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                        Button("Play Playlist", systemImage: "play.fill") { play() }
                            .buttonStyle(.borderedProminent)
                            .disabled(items.isEmpty)
                    }
                    Spacer()
                }
                .padding(24)
                Divider()

                ForEach(items) { item in
                    HStack(spacing: 12) {
                        Text(String(item.position))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                        Button("Play \(item.title)", systemImage: "play.fill") { play(item) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Play this track and continue through the playlist")
                        Text(item.title).font(.body.weight(.medium)).lineLimit(2)
                        Spacer()
                        Button("Move Earlier", systemImage: "arrow.up") { move(item, to: item.position - 1) }
                            .labelStyle(.iconOnly).disabled(item.position == 1).help("Move earlier")
                        Button("Move Later", systemImage: "arrow.down") { move(item, to: item.position + 1) }
                            .labelStyle(.iconOnly).disabled(item.position == items.count).help("Move later")
                        Button("Remove from Playlist", systemImage: "trash", role: .destructive) { remove(item) }
                            .labelStyle(.iconOnly).help("Remove from playlist")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 11)
                    Divider().padding(.leading, 66)
                }
            }
        }
        .navigationTitle(playlist.name)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Empty playlist", systemImage: "music.note.list", description: Text("Add tracks from an album, then play them here."))
            }
        }
        .task(id: playlist.id) { await load() }
    }

    private func load() async {
        do { items = try await library.playlistItems(playlist.id) }
        catch { library.presentError(error) }
    }

    private func move(_ item: PlaylistItem, to position: Int) {
        Task {
            do { try await library.movePlaylistItem(item.id, to: position); await load() }
            catch { library.presentError(error) }
        }
    }

    private func remove(_ item: PlaylistItem) {
        Task {
            do { try await library.removePlaylistItem(item.id); await load() }
            catch { library.presentError(error) }
        }
    }

    private func play() {
        Task {
            do {
                try playback.play(items: try await library.playbackURLs(playlistID: playlist.id), startingAt: 0)
            } catch {
                library.presentError(error)
            }
        }
    }

    private func play(_ item: PlaylistItem) {
        Task {
            do {
                let playableItems = try await library.playbackURLs(playlistID: playlist.id)
                guard let index = playableItems.firstIndex(where: { $0.trackID == item.trackID }) else {
                    throw NSError(domain: "MusicLibrary", code: 3, userInfo: [NSLocalizedDescriptionKey: "This playlist item has no currently playable audio file."])
                }
                try playback.play(items: playableItems, startingAt: index)
            } catch {
                library.presentError(error)
            }
        }
    }
}

private struct ImportBatchDetail: View {
    @ObservedObject var library: LibraryStore
    let batch: ImportBatch
    let onRescanStarted: (ImportBatchID) -> Void
    let onCombinedRescanRequested: (ImportBatchID) -> Void
    let analyzeMetadataAfterScan: Bool
    let onCombinedAnalysisFinished: () -> Void
    @State private var candidates: [ImportCandidate] = []
    @State private var unregisteredCandidates: [ImportCandidate] = []
    @State private var proposals: [ImportReleaseProposal] = []
    @State private var proposalPreviews: [UUID: ImportProposalPreview] = [:]
    @State private var proposalToAttach: ImportReleaseProposal?
    @State private var proposalToLookUp: ImportReleaseProposal?
    @State private var selectionToReview: ExternalMetadataSelection?
    @State private var selections: [UUID: ExternalMetadataSelection] = [:]
    @State private var missingAssets: [MissingAssetReview] = []
    @State private var missingAssetToConfirm: MissingAssetReview?
    @State private var missingAssetToRemove: MissingAssetReview?
    @State private var missingAssetToRelink: MissingAssetReview?

    private var audioCandidates: [ImportCandidate] { candidates.filter { $0.payload != nil } }
    private var failedCandidates: [ImportCandidate] { candidates.filter { $0.status == .failed } }

    var body: some View {
        List {
            Section("Scan") {
                HStack(spacing: 22) {
                    ScanMetric(symbol: scanStatusSymbol, title: "Status", value: batch.status.rawValue.capitalized, tint: scanStatusColor)
                    ScanMetric(symbol: "doc.on.doc", title: "Processed", value: String(batch.processedCount), tint: .secondary)
                    ScanMetric(symbol: "waveform", title: "Audio", value: String(batch.candidateCount), tint: .blue)
                    ScanMetric(symbol: batch.errorCount == 0 ? "checkmark.circle" : "exclamationmark.triangle", title: "Errors", value: String(batch.errorCount), tint: batch.errorCount == 0 ? .green : .orange)
                }
                .padding(.vertical, 8)
                if let error = batch.errorSummary { Text(error).foregroundStyle(.secondary) }
                if let progress = library.importScanProgress[batch.id] {
                    LabeledContent("Items checked", value: String(progress.examinedItemCount))
                    LabeledContent("Audio found so far", value: String(progress.audioCandidateCount))
                    if let path = progress.currentRelativePath {
                        Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    ProgressView()
                }
                if batch.status == .scanning { Button("Cancel Scan", role: .destructive) { Task { await library.cancelImportScan(batch.id) } } }
                if batch.status != .scanning {
                    HStack {
                        Button("Rescan", systemImage: "arrow.clockwise") {
                            Task {
                                do {
                                    let newBatchID = try await library.retryImportScan(batch.id)
                                    onRescanStarted(newBatchID)
                                }
                                catch { library.presentError(error) }
                            }
                        }
                        Button("Rescan and Review New Files", systemImage: "text.magnifyingglass") {
                        Task {
                            do {
                                let newBatchID = try await library.retryImportScan(batch.id)
                                // Set the intent before selecting the new batch. The
                                // new detail view can then wait for scan completion
                                // and perform the explicit metadata pass exactly once.
                                onCombinedRescanRequested(newBatchID)
                                onRescanStarted(newBatchID)
                            } catch {
                                library.presentError(error)
                            }
                        }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Text("Review New Files performs the same safe rescan, then reads metadata only for paths not already represented in the catalogue.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if batch.status != .scanning && !unregisteredCandidates.isEmpty { Button("Read Metadata for New Files", systemImage: "text.magnifyingglass") {
                    Task {
                        do {
                            try await library.analyzeImportBatch(batch.id)
                            await load()
                        } catch {
                            library.presentError(error)
                        }
                    }
                } }
                if batch.status != .scanning && candidates.isEmpty == false && unregisteredCandidates.isEmpty {
                    Text("All scanned audio files already have catalogue asset paths; no metadata review is needed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if batch.status == .completed {
                    Text(scanOutcome).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !failedCandidates.isEmpty {
                Section("File-level scan errors") {
                    Text("These files could not be fully scanned. The rest of the scan remains available for review.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(failedCandidates) { candidate in
                        Text(candidate.errorMessage ?? "Unknown scan error").font(.caption)
                    }
                }
            }
            if !missingAssets.isEmpty {
                Section("Missing files found by this rescan") {
                    Text("These catalogue asset references were not found while this available folder was scanned. Nothing has been removed automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(missingAssets) { asset in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(asset.albumTitle).font(.headline)
                            Text(asset.trackTitle).font(.caption)
                            Text(asset.relativePath).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            HStack {
                                Button("Choose Replacement File…") { missingAssetToRelink = asset }
                                Button("Mark Catalogue Asset Missing…", role: .destructive) { missingAssetToConfirm = asset }
                                Button("Remove Asset Reference…", role: .destructive) { missingAssetToRemove = asset }
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            Section("Release Proposals") {
                if proposals.isEmpty { Text("Read embedded metadata to create local proposals. No catalogue records or source files will be changed.").foregroundStyle(.secondary) }
                ForEach(proposals) { proposal in
                    HStack(alignment: .top, spacing: 14) {
                        proposalArtwork(for: proposal)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(proposal.title).font(.headline).lineLimit(2)
                            Text(proposal.artist ?? "Unknown artist").font(.subheadline)
                            HStack(spacing: 8) {
                                Label(proposal.provenance, systemImage: "tag")
                                Text(proposalSummary(proposal))
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            if proposal.createdAlbumID != nil {
                                Label("Catalogue edition created", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 8) {
                            Button("Search MusicBrainz…", systemImage: "magnifyingglass") { proposalToLookUp = proposal }
                            if let selection = selections[proposal.id] {
                                Button("Review MusicBrainz Fields…", systemImage: "rectangle.and.pencil.and.ellipsis") { selectionToReview = selection }
                            }
                            if proposal.createdAlbumID == nil && (proposal.status == .proposed || proposal.status == .approved) {
                                HStack(spacing: 8) {
                                    Button("Create New Edition", systemImage: "plus.rectangle.on.folder") {
                                        Task {
                                            do {
                                                _ = try await library.confirmImportReleaseProposal(proposal.id)
                                                await load()
                                            } catch {
                                                library.presentError(error)
                                            }
                                        }
                                    }
                                    Button("Dismiss", role: .destructive) {
                                        Task {
                                            do {
                                                try await library.setImportReleaseProposal(proposal.id, status: .dismissed)
                                                await load()
                                            } catch {
                                                library.presentError(error)
                                            }
                                        }
                                    }
                                }
                                Button("Attach to Existing Edition…", systemImage: "link.badge.plus") { proposalToAttach = proposal }
                            }
                        }
                        .frame(minWidth: 210, alignment: .trailing)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        Text(proposal.status.rawValue.capitalized)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    .padding(.vertical, 4)
                }
            }
            if !unregisteredCandidates.isEmpty {
                Section("New audio files") {
                    Text("These files are under this scan's music folder but are not yet represented by a catalogue asset path. Review their metadata before creating any catalogue records.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(unregisteredCandidates) { CandidateRow(candidate: $0) }
                }
            }
            Section("Scan diagnostics") {
                DisclosureGroup("All scanned audio files (\(audioCandidates.count))") {
                    ForEach(audioCandidates) { CandidateRow(candidate: $0) }
                }
            }
        }
        .navigationTitle("Import Batch")
        .task(id: batchRefreshToken) {
            await load()
            await analyzeNewFilesIfRequested()
        }
        .confirmationDialog("Mark this catalogue asset missing?", isPresented: Binding(get: { missingAssetToConfirm != nil }, set: { if !$0 { missingAssetToConfirm = nil } }), titleVisibility: .visible) {
            if let asset = missingAssetToConfirm {
                Button("Mark Asset Missing", role: .destructive) {
                    Task {
                        do {
                            try await library.confirmAssetMissing(asset.id, in: batch.id)
                            missingAssetToConfirm = nil
                            await load()
                        } catch { library.presentError(error) }
                    }
                }
            }
        } message: {
            Text("This keeps the catalogue track but records that its file is currently missing. It never deletes, moves, or changes source audio files.")
        }
        .confirmationDialog("Remove this missing asset reference?", isPresented: Binding(get: { missingAssetToRemove != nil }, set: { if !$0 { missingAssetToRemove = nil } }), titleVisibility: .visible) {
            if let asset = missingAssetToRemove {
                Button("Remove Asset Reference", role: .destructive) {
                    Task {
                        do {
                            try await library.removeMissingAssetReference(asset.id, in: batch.id)
                            missingAssetToRemove = nil
                            await load()
                        } catch { library.presentError(error) }
                    }
                }
            }
        } message: {
            Text("This permanently removes only the stored file reference for \(missingAssetToRemove?.trackTitle ?? "this track"). The catalogue track, album, playlists, and source audio files are not deleted or changed.")
        }
        .fileImporter(isPresented: Binding(get: { missingAssetToRelink != nil }, set: { if !$0 { missingAssetToRelink = nil } }), allowedContentTypes: [.audio, .data]) { result in
            guard let asset = missingAssetToRelink else { return }
            switch result {
            case .success(let url):
                Task {
                    do {
                        try await library.proposeRelink(assetID: asset.id, replacementURL: url)
                        missingAssetToRelink = nil
                        await load()
                    } catch {
                        library.presentError(error)
                    }
                }
            case .failure(let error):
                library.presentError(error)
            }
        }
        .sheet(item: $proposalToLookUp) { proposal in
            ExternalMetadataLookupView(library: library, proposal: proposal, onSelected: { await load() })
        }
        .sheet(item: $proposalToAttach) { proposal in
            ExistingAlbumAttachmentView(library: library, proposal: proposal, onAttached: { await load() })
        }
        .sheet(item: $selectionToReview) { selection in ExternalMetadataComparisonView(library: library, selection: selection, proposal: proposals.first(where: { $0.id == selection.importProposalID }), onApplied: { await load() }) }
    }

    private var scanStatusSymbol: String {
        switch batch.status {
        case .scanning: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private var scanStatusColor: Color {
        switch batch.status {
        case .scanning: .blue
        case .completed: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }

    private func load() async {
        do {
            let loadedCandidates = try await library.importCandidates(batchID: batch.id)
            let loadedUnregisteredCandidates = try await library.unregisteredImportCandidates(batchID: batch.id)
            let loadedProposals = try await library.importReleaseProposals(batchID: batch.id)
            let loadedMissingAssets = try await library.missingAssetReviews(batchID: batch.id)
            var loadedSelections: [UUID: ExternalMetadataSelection] = [:]
            var loadedPreviews: [UUID: ImportProposalPreview] = [:]
            for proposal in loadedProposals {
                if let selection = try await library.externalMetadataSelection(for: proposal.id) {
                    loadedSelections[proposal.id] = selection
                }
                if let preview = try? await library.importProposalPreview(proposal) {
                    loadedPreviews[proposal.id] = preview
                }
            }
            candidates = loadedCandidates
            unregisteredCandidates = loadedUnregisteredCandidates
            proposals = loadedProposals
            proposalPreviews = loadedPreviews
            selections = loadedSelections
            missingAssets = loadedMissingAssets
        } catch {
            library.presentError(error)
        }
    }

    private var batchRefreshToken: String {
        "\(batch.id.description)|\(batch.status.rawValue)|\(batch.processedCount)|\(batch.candidateCount)|\(batch.errorCount)|\(batch.completedAt?.timeIntervalSince1970 ?? 0)"
    }

    private func analyzeNewFilesIfRequested() async {
        guard analyzeMetadataAfterScan else { return }
        guard batch.status != .scanning else { return }
        guard batch.status == .completed else {
            // Do not attempt metadata extraction after a failed or cancelled
            // scan. Clear the one-shot intent so the user can retry explicitly.
            onCombinedAnalysisFinished()
            return
        }

        do {
            try await library.analyzeImportBatch(batch.id)
            await load()
        } catch {
            library.presentError(error)
        }
        onCombinedAnalysisFinished()
    }

    @ViewBuilder
    private func proposalArtwork(for proposal: ImportReleaseProposal) -> some View {
        if let url = proposalPreviews[proposal.id]?.artworkURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 96, height: 96)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var scanOutcome: String {
        if audioCandidates.isEmpty {
            return "This completed scan found no supported audio files. Hidden files and package contents are skipped."
        }
        if unregisteredCandidates.isEmpty && missingAssets.isEmpty {
            return "No catalogue changes were found by this rescan: every scanned audio path is already registered and no registered path is missing."
        }
        var parts: [String] = []
        if !unregisteredCandidates.isEmpty { parts.append("\(unregisteredCandidates.count) new audio file\(unregisteredCandidates.count == 1 ? "" : "s")") }
        if !missingAssets.isEmpty { parts.append("\(missingAssets.count) missing catalogue reference\(missingAssets.count == 1 ? "" : "s")") }
        return "This completed scan found " + parts.joined(separator: " and ") + ". Review the items below; nothing is changed automatically."
    }
}

private struct ExistingAlbumAttachmentView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let proposal: ImportReleaseProposal
    let onAttached: () async -> Void

    @State private var searchText = ""
    @State private var selectedAlbumID: AlbumID?
    @State private var preview: ImportAttachmentPreview?
    @State private var isLoadingPreview = false
    @State private var isAttaching = false

    private var filteredAlbums: [Album] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.albums
            .filter { album in
                guard !term.isEmpty else { return true }
                return [album.title, album.editionLabel, album.catalogueNumber, album.countryCode, album.releaseYear.map(String.init)]
                    .compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(term) }
            }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Attach Files to an Existing Edition")
                    .font(.title2.bold())
                Text("Choose the catalogue edition these scanned files belong to. Catalogue titles, credits, artwork, and edition metadata will not be replaced.")
                    .foregroundStyle(.secondary)
                Label("\(proposal.trackCount) imported file\(proposal.trackCount == 1 ? "" : "s") · \(proposal.discCount) disc\(proposal.discCount == 1 ? "" : "s")", systemImage: "waveform.badge.plus")
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find an album or edition", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                    .padding(12)

                    List(filteredAlbums, selection: $selectedAlbumID) { album in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(album.displayTitle).font(.headline).lineLimit(2)
                            HStack(spacing: 6) {
                                if let year = album.releaseYear { Text(String(year)) }
                                if let country = album.countryCode { Text(country) }
                                if let catalogueNumber = album.catalogueNumber { Text(catalogueNumber) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                if library.localAlbumIDs.contains(album.id) {
                                    Label("Mac", systemImage: "macbook")
                                }
                                if library.publishedAlbumIDs.contains(album.id) {
                                    Label("NAS", systemImage: "externaldrive.connected.to.line.below")
                                }
                                if album.hasCD { Label("CD", systemImage: "opticaldisc") }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .tag(album.id)
                    }
                    .overlay {
                        if filteredAlbums.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                }
                .frame(minWidth: 300, idealWidth: 350)

                Group {
                    if isLoadingPreview {
                        ProgressView("Checking discs, tracks, and file paths…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let preview {
                        attachmentPreview(preview)
                    } else {
                        ContentUnavailableView(
                            "Select an Existing Edition",
                            systemImage: "rectangle.stack.badge.person.crop",
                            description: Text("The app will compare every imported file with the selected catalogue edition before enabling attachment.")
                        )
                    }
                }
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                Label("Source audio files are never copied, moved, renamed, or modified.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    attach()
                } label: {
                    if isAttaching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Attach Digital Files", systemImage: "link.badge.plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(preview?.isCompatible != true || isLoadingPreview || isAttaching)
            }
            .padding(16)
        }
        .frame(minWidth: 940, idealWidth: 1120, minHeight: 640, idealHeight: 760)
        .presentationSizing(.fitted)
        .task(id: selectedAlbumID) { await loadPreview() }
    }

    @ViewBuilder
    private func attachmentPreview(_ preview: ImportAttachmentPreview) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(preview.albumTitle).font(.title2.bold())
                    Label(
                        preview.isCompatible ? "Ready to attach" : "Cannot attach safely",
                        systemImage: preview.isCompatible ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(preview.isCompatible ? .green : .orange)
                    Text(preview.compatibilityMessage).foregroundStyle(.secondary)
                    Text(preview.mode == .populateEmptyAlbum
                         ? "This catalogue edition is empty. The imported disc and track structure will be created while its existing album metadata remains unchanged."
                         : "The imported files will be paired with the existing tracks below. Existing track titles and ordering remain unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text("File-to-track preview").font(.headline)
                ForEach(preview.pairs) { pair in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Imported", systemImage: "doc.badge.plus")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            Text(pair.importedTitle).fontWeight(.medium)
                            Text(pair.relativePath).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Label("Catalogue · Disc \(pair.discNumber)", systemImage: "music.note.list")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            if let title = pair.catalogueTitle {
                                Text(title).fontWeight(.medium)
                                Text("Track \(pair.catalogueTrackNumber.map(String.init) ?? "—") · title preserved")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text(pair.importedTitle).fontWeight(.medium)
                                Text("New catalogue track will be created")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(22)
        }
    }

    private func loadPreview() async {
        guard let albumID = selectedAlbumID else {
            preview = nil
            return
        }
        isLoadingPreview = true
        preview = nil
        do {
            let loaded = try await library.importAttachmentPreview(proposalID: proposal.id, albumID: albumID)
            guard selectedAlbumID == albumID else { return }
            preview = loaded
        } catch {
            guard selectedAlbumID == albumID else { return }
            library.presentError(error)
        }
        if selectedAlbumID == albumID { isLoadingPreview = false }
    }

    private func attach() {
        guard let albumID = selectedAlbumID, preview?.isCompatible == true else { return }
        isAttaching = true
        Task {
            do {
                _ = try await library.attachImportReleaseProposal(proposal.id, to: albumID)
                await onAttached()
                dismiss()
            } catch {
                library.presentError(error)
                isAttaching = false
                await loadPreview()
            }
        }
    }
}

private struct ExternalMetadataLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let proposal: ImportReleaseProposal
    let onSelected: () async -> Void
    @State private var title: String
    @State private var artist: String
    @State private var results: [ExternalReleasePreview] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var selectedResultID: String?
    @State private var selectedReleaseDetail: ExternalReleasePreview?
    @State private var isLoadingReleaseDetail = false
    @State private var importedPreview = ImportProposalPreview(trackTitles: [], artworkURL: nil)
    @State private var isDownloadingArtwork = false
    @State private var artworkMessage: String?

    init(library: LibraryStore, proposal: ImportReleaseProposal, onSelected: @escaping () async -> Void) {
        self.library = library
        self.proposal = proposal
        self.onSelected = onSelected
        _title = State(initialValue: proposal.title)
        _artist = State(initialValue: proposal.artist ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Search").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow { Text("Album title").frame(width: 96, alignment: .trailing); TextField("Album title", text: $title) }
                        GridRow { Text("Artist (optional)").frame(width: 96, alignment: .trailing); TextField("Artist", text: $artist) }
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
                HStack(spacing: 12) {
                    Button("Search MusicBrainz") { search() }.disabled(isSearching || title.nilIfBlank == nil)
                    Text("Only the text above is sent. Audio files are never uploaded or modified.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.bottom, 14)
                Divider()
                if isSearching {
                    Spacer(); ProgressView("Searching MusicBrainz…"); Spacer()
                } else if hasSearched && results.isEmpty {
                    Spacer(); ContentUnavailableView("No matching releases", systemImage: "magnifyingglass", description: Text("Try a different album title or artist.")); Spacer()
                } else if !results.isEmpty {
                    HStack(spacing: 0) {
                        List(selection: $selectedResultID) {
                            Section("Album candidates") {
                                ForEach(results) { result in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.title).font(.headline).lineLimit(2)
                                        Text([result.artist, result.releaseDate, result.countryCode, result.catalogueNumber].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        Text("\(result.mediaCount) disc\(result.mediaCount == 1 ? "" : "s")")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .tag(result.id)
                                }
                            }
                        }
                        .frame(minWidth: 270, maxWidth: 320)
                        Divider()
                        MusicBrainzCandidateComparison(proposal: proposal, result: displayedResult, importedPreview: importedPreview, onDownloadArtwork: downloadArtwork, isDownloadingArtwork: isDownloadingArtwork, isLoadingTracks: isLoadingReleaseDetail)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Spacer(); ContentUnavailableView("Search MusicBrainz", systemImage: "magnifyingglass", description: Text("Search for release candidates, then compare one with this imported album.")); Spacer()
                }
            }
            .navigationTitle("MusicBrainz Lookup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Selected Release") { if let selectedResult { save(selectedResult) } }
                        .disabled(selectedResult == nil)
                }
            }
            .alert("Search failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
            .alert("Cover artwork", isPresented: Binding(get: { artworkMessage != nil }, set: { if !$0 { artworkMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(artworkMessage ?? "") }
        }
        // Flexible limits let macOS provide a larger, user-resizable sheet on larger displays.
        .frame(minWidth: 980, idealWidth: 1_200, maxWidth: 1_500, minHeight: 660, idealHeight: 800, maxHeight: 1_000)
        .background(MusicBrainzSheetResizability())
        .task { await loadImportedPreview() }
        .task(id: selectedResultID) { await loadSelectedReleaseDetail() }
    }

    private var selectedResult: ExternalReleasePreview? { results.first { $0.id == selectedResultID } }
    private var displayedResult: ExternalReleasePreview? {
        guard let selectedResult else { return nil }
        return selectedReleaseDetail?.id == selectedResult.id ? selectedReleaseDetail : selectedResult
    }

    private func search() {
        isSearching = true
        hasSearched = true
        results = []
        Task {
            do {
                results = try await library.searchMusicBrainz(title: title, artist: artist.nilIfBlank)
                selectedReleaseDetail = nil
                selectedResultID = results.first?.id
            }
            catch { errorMessage = error.localizedDescription }
            isSearching = false
        }
    }

    private func loadSelectedReleaseDetail() async {
        guard let selectedResultID else { selectedReleaseDetail = nil; return }
        isLoadingReleaseDetail = true
        defer { isLoadingReleaseDetail = false }
        do { selectedReleaseDetail = try await library.musicBrainzReleaseDetails(id: selectedResultID) }
        catch { selectedReleaseDetail = nil }
    }

    private func loadImportedPreview() async {
        importedPreview = (try? await library.importProposalPreview(proposal)) ?? .init(trackTitles: [], artworkURL: nil)
    }
    private func save(_ result: ExternalReleasePreview) {
        Task {
            do {
                // Persist the full detail response, not the lightweight search row, so the later
                // field-application step can safely offer MusicBrainz track titles.
                let release = displayedResult?.id == result.id && !(displayedResult?.trackTitles.isEmpty ?? true)
                    ? displayedResult!
                    : try await library.musicBrainzReleaseDetails(id: result.id)
                try await library.saveMusicBrainzSelection(release, for: proposal.id)
                await onSelected()
                dismiss()
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func downloadArtwork(_ result: ExternalReleasePreview) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = "\(safeFileName(result.title)).jpg"
        panel.message = "Save the selected MusicBrainz cover as a JPEG. This does not change the catalogue or import proposal."
        guard panel.runModal() == .OK, let destination = panel.url, let artworkURL = result.coverArtworkURL else { return }
        isDownloadingArtwork = true
        Task {
            defer { isDownloadingArtwork = false }
            do {
                let request = MusicNetworkRequestPolicy.request(url: artworkURL)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let image = NSImage(data: data), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
                    throw NSError(domain: "MusicLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "MusicBrainz did not provide a usable front-cover image for this release."])
                }
                try jpeg.write(to: destination, options: .atomic)
                artworkMessage = "Saved JPEG cover artwork to \(destination.lastPathComponent)."
            } catch {
                artworkMessage = "Could not download cover artwork: \(error.localizedDescription)"
            }
        }
    }

    private func safeFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        return value.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "MusicBrainz Cover"
    }
}

private struct MusicBrainzCandidateComparison: View {
    let proposal: ImportReleaseProposal
    let result: ExternalReleasePreview?
    let importedPreview: ImportProposalPreview

    let onDownloadArtwork: (ExternalReleasePreview) -> Void
    let isDownloadingArtwork: Bool
    let isLoadingTracks: Bool

    var body: some View {
        Group {
            if let result {
                ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Imported cover").font(.caption.bold()).foregroundStyle(.secondary)
                            importedArtwork()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("MusicBrainz cover").font(.caption.bold()).foregroundStyle(.secondary)
                            coverArtwork(for: result)
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Compare metadata").font(.title3.bold())
                            Text(result.title).font(.headline)
                            Text([result.artist, result.releaseDate, result.countryCode, result.catalogueNumber].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            Button(isDownloadingArtwork ? "Downloading Cover…" : "Download Cover Artwork…", systemImage: "arrow.down.circle") { onDownloadArtwork(result) }
                                .disabled(isDownloadingArtwork || result.coverArtworkURL == nil)
                            Text("Saves only a JPEG copy you choose. It does not apply MusicBrainz metadata.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text("Review the imported values beside the selected MusicBrainz release. Choosing it still changes nothing until you press Use Selected Release, then select the fields to apply.")
                        .font(.caption).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                        GridRow {
                            Text("Field").font(.caption.bold()).foregroundStyle(.secondary)
                            Text("Imported album").font(.caption.bold()).foregroundStyle(.secondary)
                            Text("Selected MusicBrainz release").font(.caption.bold()).foregroundStyle(.secondary)
                        }
                        Divider().gridCellColumns(3)
                        row("Album title", proposal.title, result.title)
                        row("Artist", proposal.artist, result.artist)
                        row("Release date", nil, result.releaseDate)
                        row("Country / region", proposal.countryCode, result.countryCode)
                        row("Catalogue number", proposal.catalogueNumber, result.catalogueNumber)
                        row("Disc count", String(proposal.discCount), String(result.mediaCount))
                        row("Imported tracks", String(proposal.trackCount), nil)
                    }
                    Divider()
                    if isLoadingTracks {
                        HStack { ProgressView(); Text("Loading selected release tracks…").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        TrackListComparison(importedTracks: importedPreview.trackTitles, musicBrainzTracks: result.trackTitles)
                    }
                    Label("Preview only — no catalogue record, import proposal, or audio file has changed.", systemImage: "eye")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(24)
                }
            } else {
                ContentUnavailableView("Select an album candidate", systemImage: "rectangle.and.text.magnifyingglass", description: Text("The selected candidate's MusicBrainz metadata will appear beside the imported values."))
            }
        }
    }

    @ViewBuilder private func coverArtwork(for result: ExternalReleasePreview) -> some View {
        if let url = result.coverArtworkThumbnailURL {
            AsyncImage(url: url, transaction: .init(animation: .default)) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure:
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No MusicBrainz cover").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                default: ProgressView()
                }
            }
            // AsyncImage's loading phase is stateful; identity must change with the selected release.
            .id(result.id)
            .frame(width: 130, height: 130)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private func importedArtwork() -> some View {
        if let url = importedPreview.artworkURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill()
                .frame(width: 130, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                Text("No folder artwork found").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .frame(width: 130, height: 130)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private func row(_ label: String, _ imported: String?, _ musicBrainz: String?) -> some View {
        GridRow {
            Text(label).font(.subheadline.weight(.medium))
            Text(imported?.nilIfBlank ?? "—").textSelection(.enabled)
            Text(musicBrainz?.nilIfBlank ?? "—").textSelection(.enabled)
        }
    }
}

private struct TrackListComparison: View {
    let importedTracks: [String]
    let musicBrainzTracks: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Track comparison").font(.headline)
            HStack(alignment: .top, spacing: 24) {
                trackColumn(title: "Imported tracks (\(importedTracks.count))", tracks: importedTracks, empty: "No extracted imported tracks.")
                Divider()
                trackColumn(title: "MusicBrainz tracks (\(musicBrainzTracks.count))", tracks: musicBrainzTracks, empty: "MusicBrainz did not return a track list.")
            }
        }
    }

    private func trackColumn(title: String, tracks: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            if tracks.isEmpty { Text(empty).font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).") .foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                    Text(track)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExternalMetadataComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let selection: ExternalMetadataSelection
    let proposal: ImportReleaseProposal?
    let onApplied: () async -> Void
    @State private var useTitle = true
    @State private var useArtist = true
    @State private var useDiscCount = true
    @State private var useCountryCode = true
    @State private var useCatalogueNumber = true
    @State private var useReleaseDate = false
    @State private var useTrackTitles: Bool
    @State private var useFrontArtwork = false
    @State private var errorMessage: String?

    init(library: LibraryStore, selection: ExternalMetadataSelection, proposal: ImportReleaseProposal?, onApplied: @escaping () async -> Void) {
        self.library = library
        self.selection = selection
        self.proposal = proposal
        self.onApplied = onApplied
        _useTrackTitles = State(initialValue: proposal?.trackCount == selection.trackTitles.count && !selection.trackTitles.isEmpty)
    }

    var body: some View {
        Form {
            Section("MusicBrainz field comparison") {
                comparison("Album title", current: proposal?.title, proposed: selection.title, enabled: $useTitle)
                comparison("Artist", current: proposal?.artist, proposed: selection.artist, enabled: $useArtist)
                comparison("Disc count", current: proposal.map { String($0.discCount) }, proposed: String(selection.discCount), enabled: $useDiscCount)
                comparison("Country/region", current: proposal?.countryCode, proposed: selection.countryCode, enabled: $useCountryCode)
                comparison("Catalogue number", current: proposal?.catalogueNumber, proposed: selection.catalogueNumber, enabled: $useCatalogueNumber)
                comparison("Release date", current: "From imported audio tags", proposed: selection.releaseDate, enabled: $useReleaseDate)
                Toggle(isOn: $useTrackTitles) {
                    VStack(alignment: .leading) {
                        Text("Track titles")
                        Text("Imported: \(proposal?.trackCount ?? 0) tracks → MusicBrainz: \(selection.trackTitles.count) tracks").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!trackTitlesMatch)
                if !trackTitlesMatch {
                    Text("Track titles can only be applied when both releases contain the same number of tracks.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $useFrontArtwork) {
                    VStack(alignment: .leading) {
                        Text("Front cover artwork")
                        Text("Downloads the selected MusicBrainz cover into managed library storage and makes it the album cover when catalogue records are created.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Only checked fields update this import proposal. Track titles are matched by disc and track number. This never changes audio tags.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding().frame(width: 520)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Apply Selected Fields") { apply() } } }
        .alert("Unable to apply fields", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }
    private func comparison(_ name: String, current: String?, proposed: String?, enabled: Binding<Bool>) -> some View {
        Toggle(isOn: enabled) { VStack(alignment: .leading) { Text(name); Text("Current: \(current ?? "—") → MusicBrainz: \(proposed ?? "—")").font(.caption).foregroundStyle(.secondary) } }
    }
    private var trackTitlesMatch: Bool { proposal?.trackCount == selection.trackTitles.count && !selection.trackTitles.isEmpty }
    private func apply() { Task { do { try await library.applyExternalMetadataSelection(selection, fields: .init(title: useTitle, artist: useArtist, discCount: useDiscCount, countryCode: useCountryCode, catalogueNumber: useCatalogueNumber, releaseDate: useReleaseDate, trackTitles: useTrackTitles && trackTitlesMatch, frontArtwork: useFrontArtwork)); await onApplied(); dismiss() } catch { errorMessage = error.localizedDescription } } }
}

/// SwiftUI sheets do not inherit the main window's resizable style. This bridge makes
/// the MusicBrainz lookup sheet explicitly resizable, with sensible catalogue-review limits.
private struct MusicBrainzSheetResizability: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.minSize = .init(width: 980, height: 660)
            window.maxSize = .init(width: 1_500, height: 1_000)
        }
    }
}

private struct ArtworkPreview: View {
    let artwork: Artwork

    var body: some View {
        Group {
            if let path = artwork.localPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Selected front artwork")
            } else {
                ContentUnavailableView("Artwork file unavailable", systemImage: "photo.badge.exclamationmark", description: Text("The selected catalogue artwork could not be read."))
            }
        }
    }
}

private struct TagWritePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let album: Album
    let discs: [Disc]
    let tracksByDisc: [DiscID: [Track]]
    let albumCredits: [ContributorCredit]
    let trackCredits: [TrackID: [ContributorCredit]]
    @State private var previews: [FLACTagWriteCoordinator.Preview] = []
    @State private var isLoading = true
    @State private var isWriting = false
    @State private var result: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Safety") {
                    Text("Nothing changes until you press Back Up and Write. Every selected FLAC is copied first to Music Library’s TagWriteBackups folder, written through a temporary replacement, then read again for verification. Audio frames are copied without transcoding.")
                }
                Section("Supported-format matrix") {
                    LabeledContent("FLAC / Vorbis comments", value: "Supported")
                    LabeledContent("WAV + CUE, DSF, AIFF, ALAC, MP3", value: "Catalogue-only")
                }
                if isLoading {
                    ProgressView("Preparing preview…")
                } else {
                    Section("Planned changes") {
                        ForEach(previews) { preview in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preview.planned.trackTitle).font(.headline)
                                Text(URL(fileURLWithPath: preview.planned.sourcePath).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                if let reason = preview.unsupportedReason { Text(reason).font(.caption).foregroundStyle(.orange) }
                                else if preview.changedKeys.isEmpty { Text("Already matches the catalogue; no write needed.").font(.caption).foregroundStyle(.secondary) }
                                else { Text("Will update: \(preview.changedKeys.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if let result { Section("Result") { Text(result) } }
            }
            .navigationTitle("Preview Tag Write-Back")
            .task { await load() }
            .alert("Tag write-back could not finish", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Back Up and Write \(previews.filter(\.isWritable).count) FLAC File(s)") { write() }
                        .disabled(isLoading || isWriting || previews.filter(\.isWritable).isEmpty)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    private func load() async {
        do { previews = try await library.tagWritePreviews(album: album, discs: discs, tracksByDisc: tracksByDisc, albumCredits: albumCredits, trackCredits: trackCredits) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
    private func write() {
        isWriting = true
        Task {
            do {
                let journal = try await library.executeTagWrite(previews: previews)
                let completed = journal.entries.filter { $0.status == "completed" }.count
                let failed = journal.entries.filter { $0.status == "failed" }.count
                result = "Completed \(completed) file(s)\(failed == 0 ? "" : "; \(failed) failed"). The batch journal and untouched backups were retained for recovery."
            } catch { errorMessage = error.localizedDescription }
            isWriting = false
        }
    }
}

private struct LyricsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let track: Track
    @State private var entries: [LyricsEntry] = []
    @State private var text = ""
    @State private var language = ""
    @State private var kind: LyricsKind = .plain
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if track.isInstrumental == true {
                        Label("This track is marked instrumental. Lyrics are optional.", systemImage: "music.note")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Saved lyrics") {
                        if entries.isEmpty {
                            Text("No lyrics stored. This is not treated as an error.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(entries) { entry in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("\(entry.kind.rawValue.capitalized) · \(entry.language ?? "No language") · \(entry.source)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Button("Delete", systemImage: "trash", role: .destructive) {
                                                Task { try? await library.deleteLyrics(entry.id); await load() }
                                            }
                                            .labelStyle(.iconOnly)
                                        }
                                        ScrollView {
                                            Text(entry.text)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .textSelection(.enabled)
                                        }
                                        .frame(minHeight: 72, maxHeight: 180)
                                        .padding(8)
                                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                    if entry.id != entries.last?.id { Divider() }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox("Manual import or edit") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Language (optional)").font(.caption).foregroundStyle(.secondary)
                            TextField("e.g. en or zh-Hant", text: $language)
                            Text("Kind").font(.caption).foregroundStyle(.secondary)
                            Picker("Kind", selection: $kind) {
                                Text("Plain").tag(LyricsKind.plain)
                                Text("Synchronized (LRC)").tag(LyricsKind.synchronized)
                            }
                            .pickerStyle(.menu)
                            Text("Lyrics text").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $text)
                                .font(.body)
                                .frame(minWidth: 620, minHeight: 320)
                                .padding(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                            Text("Lyrics providers are intentionally not enabled yet. This editor stores only text you manually paste or type.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Lyrics — \(track.title)")
            .task { await load() }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
            .alert("Unable to save lyrics", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 700, idealHeight: 760)
    }
    private func load() async { entries = (try? await library.lyrics(trackID: track.id)) ?? [] }
    private func save() { Task { do { try await library.saveLyrics(.init(trackID: track.id, language: language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : language, kind: kind, text: text)); text = ""; await load() } catch { errorMessage = error.localizedDescription } } }
}

private struct MetadataInspectionSelection: Identifiable {
    let trackID: TrackID
    let title: String
    var id: UUID { trackID.rawValue }
}

private struct TrackMetadataInspector: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let selection: MetadataInspectionSelection
    @State private var metadata: EmbeddedMetadataPayload?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Catalogue track") {
                    LabeledContent("Title", value: selection.title)
                }
                if let metadata {
                    Section("Extracted fields") {
                        metadataRow("Title", metadata.title)
                        metadataRow("Album", metadata.albumTitle)
                        metadataRow("Artist", metadata.artist)
                        metadataRow("Album artist", metadata.albumArtist)
                        metadataRow("Release year", metadata.releaseYear.map(String.init))
                        metadataRow("Genre", metadata.genre)
                        metadataRow("Disc number", metadata.discNumber.map(String.init))
                        metadataRow("Track number", metadata.trackNumber.map(String.init))
                        metadataRow("Duration", metadata.durationMilliseconds.map { "\($0) ms" })
                        metadataRow("Provenance", metadata.provenance)
                    }
                    Section("Technical audio information") {
                        metadataRow("Codec", metadata.codec)
                        metadataRow("Sample rate", metadata.sampleRateHz.map { "\($0) Hz" })
                        metadataRow("Bit depth", metadata.bitDepth.map { "\($0)-bit" })
                        metadataRow("Channels", metadata.channelCount.map(String.init))
                    }
                    Section("All embedded tags") {
                        ForEach(metadata.rawTags.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: metadata.rawTags[key] ?? "")
                        }
                    }
                } else {
                    ContentUnavailableView("Metadata not stored", systemImage: "tag.slash", description: Text("This album was imported before metadata preservation was enabled. Import a fresh test album to inspect its original embedded tags."))
                }
            }
            .navigationTitle("Extracted Metadata")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task(id: selection.trackID.rawValue) {
                do { metadata = try await library.embeddedMetadata(trackID: selection.trackID) }
                catch { errorMessage = error.localizedDescription }
            }
            .alert("Unable to read metadata", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
        .frame(width: 620, height: 650)
    }

    @ViewBuilder private func metadataRow(_ name: String, _ value: String?) -> some View {
        if let value, !value.isEmpty { LabeledContent(name, value: value) }
    }
}

private struct AlbumDetail: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var playback: PlaybackController
    let album: Album
    let locations: [PhysicalLocation]
    let onEdit: () -> Void
    @State private var placement: AlbumBoxPlacement?
    @State private var discs: [Disc] = []
    @State private var tracksByDisc: [DiscID: [Track]] = [:]
    @State private var trackCredits: [TrackID: [ContributorCredit]] = [:]
    @State private var credits: [ContributorCredit] = []
    @State private var aliases: [AlbumAlias] = []
    @State private var artwork: [Artwork] = []
    @State private var showsAddDisc = false
    @State private var discForTrack: Disc?
    @State private var showsAddAlias = false
    @State private var showsAddContributor = false
    @State private var trackForContributor: Track?
    @State private var trackToEdit: Track?
    @State private var metadataSelection: MetadataInspectionSelection?
    @State private var trackForLyrics: Track?
    @State private var trackPendingDeletion: Track?
    @State private var contributorToEdit: Contributor?
    @State private var albumCreditToEdit: ContributorCredit?
    @State private var trackCreditToEdit: TrackCreditSelection?
    @State private var showsArtworkPicker = false
    @State private var artworkToMigrate: Artwork?
    @State private var discPendingDeletion: Disc?
    @State private var showsTagWritePreview = false
    @State private var showsArtworkManagement = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AlbumIdentityHeader(
                    album: album,
                    artworkPath: artwork.first(where: { $0.role == .front && $0.isSelected })?.localPath,
                    isLocal: library.localAlbumIDs.contains(album.id),
                    isPublished: library.publishedAlbumIDs.contains(album.id),
                    locationName: album.hasCD ? locationName : nil,
                    credits: credits,
                    aliases: aliases,
                    canPlay: !playableTracks.isEmpty,
                    onChangeArtwork: { showsArtworkPicker = true },
                    onPlay: { playAlbum(shuffled: false) },
                    onShuffle: { playAlbum(shuffled: true) },
                    onAddContributor: { showsAddContributor = true },
                    onEditContributor: { contributorToEdit = $0.contributor },
                    onEditCreditedName: { albumCreditToEdit = $0 },
                    onRemoveContributor: { removeAlbumContributor($0) }
                )

                LibraryPanel {
                    VStack(alignment: .leading, spacing: 13) {
                        LibrarySectionHeader(
                            "Tracks",
                            subtitle: trackSummary,
                            actionTitle: "Add Disc",
                            actionSymbol: "plus",
                            action: { showsAddDisc = true }
                        )
                        if discs.isEmpty {
                            Text("Create a disc to start building the catalogue track list. Digital files are never changed by these catalogue edits.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(discs) { disc in
                                discHeaderRow(disc)
                                ForEach(tracksByDisc[disc.id] ?? []) { track in
                                    albumTrackRow(track)
                                }
                                Button("Add track", systemImage: "plus") { discForTrack = disc }
                                    .buttonStyle(.borderless)
                                    .font(.callout)
                                if disc.id != discs.last?.id { Divider().padding(.vertical, 4) }
                            }
                        }
                    }
                }

                LibraryPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        LibrarySectionHeader(
                            "Other titles",
                            subtitle: "Alternate, translated, and romanized names for search",
                            actionTitle: "Add title",
                            actionSymbol: "plus",
                            action: { showsAddAlias = true }
                        )
                        if aliases.isEmpty {
                            Text("No other titles recorded.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(aliases) { alias in
                                albumAliasRow(alias)
                            }
                        }
                    }
                }

                if album.hasCD || album.notes != nil || album.physicalNote != nil {
                    LibraryPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            LibrarySectionHeader("Collection", subtitle: "Physical placement and catalogue notes")
                            if album.hasCD {
                                LabeledContent("Location", value: locationName)
                                if let note = album.physicalNote, !note.isEmpty {
                                    LabeledContent("Physical note", value: note)
                                }
                            }
                            if let notes = album.notes, !notes.isEmpty {
                                LabeledContent("Notes", value: notes)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 1_060, alignment: .leading)
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(album.title)
        .toolbar {
            Button("Edit Album", systemImage: "pencil", action: onEdit)
            Button("Add Disc", systemImage: "plus") { showsAddDisc = true }
            Menu("Artwork", systemImage: "photo") {
                Button("Change Cover…", systemImage: "photo.badge.plus") { showsArtworkPicker = true }
                Button("Artwork Details…", systemImage: "info.circle") { showsArtworkManagement = true }
            }
            Menu("Album Actions", systemImage: "ellipsis.circle") {
                if !discs.isEmpty {
                    Divider()
                    Button("Preview FLAC Tag Changes…", systemImage: "tag") { showsTagWritePreview = true }
                    Text("FLAC only; preview and backup are required before writing.")
                }
            }
        }
        .task(id: album.id) {
            do {
                placement = try await library.boxPlacement(for: album.id)
            } catch {
                library.presentError(error)
            }
            await loadContent()
        }
        .sheet(isPresented: $showsAddDisc) { AddDiscEditor(library: library, albumID: album.id, onAdded: { await loadContent() }) }
        .sheet(item: $discForTrack) { disc in AddTrackEditor(library: library, disc: disc, onAdded: { await loadContent() }) }
        .sheet(isPresented: $showsAddAlias) { AddAliasEditor(library: library, albumID: album.id, onAdded: { await loadContent() }) }
        .sheet(isPresented: $showsAddContributor) { AddContributorEditor(library: library, albumID: album.id, onAdded: { await loadContent() }) }
        .sheet(item: $trackForContributor) { track in AddTrackContributorEditor(library: library, track: track, onAdded: { await loadContent() }) }
        .sheet(item: $trackToEdit) { track in EditTrackEditor(library: library, track: track, onSaved: { await loadContent() }) }
        .sheet(item: $metadataSelection) { selection in TrackMetadataInspector(library: library, selection: selection) }
        .sheet(item: $trackForLyrics) { track in LyricsEditor(library: library, track: track) }
        .sheet(isPresented: $showsArtworkManagement) {
            ArtworkManagementSheet(
                artwork: artwork,
                library: library,
                onChooseArtwork: {
                    showsArtworkManagement = false
                    showsArtworkPicker = true
                },
                onMigrate: { artworkToMigrate = $0 }
            )
        }
        .sheet(isPresented: $showsTagWritePreview) { TagWritePreviewSheet(library: library, album: album, discs: discs, tracksByDisc: tracksByDisc, albumCredits: credits, trackCredits: trackCredits) }
        .sheet(item: $contributorToEdit) { contributor in EditContributorEditor(library: library, contributor: contributor, onSaved: { await loadContent() }) }
        .sheet(item: $albumCreditToEdit) { credit in EditAlbumCreditedNameEditor(library: library, albumID: album.id, credit: credit, onSaved: { await loadContent() }) }
        .sheet(item: $trackCreditToEdit) { selection in EditTrackCreditedNameEditor(library: library, track: selection.track, credit: selection.credit, onSaved: { await loadContent() }) }
        .confirmationDialog("Remove this disc?", isPresented: Binding(get: { discPendingDeletion != nil }, set: { if !$0 { discPendingDeletion = nil } }), titleVisibility: .visible, presenting: discPendingDeletion) { disc in
            Button("Remove Disc and Its Tracks", role: .destructive) { Task { do { try await library.deleteDisc(disc.id); await loadContent(); discPendingDeletion = nil } catch { library.presentError(error) } } }
        } message: { disc in
            Text("This removes Disc \(disc.number), its catalogue tracks, and their catalogue-only asset references. Matching playlist entries are removed. Source audio files are not changed.")
        }
        .confirmationDialog("Remove this track?", isPresented: Binding(get: { trackPendingDeletion != nil }, set: { if !$0 { trackPendingDeletion = nil } }), titleVisibility: .visible, presenting: trackPendingDeletion) { track in
            Button("Remove Track", role: .destructive) { Task { do { try await library.deleteTrack(track.id); await loadContent(); trackPendingDeletion = nil } catch { library.presentError(error) } } }
        } message: { track in
            Text("This removes \(track.title) and its catalogue-only asset references. Matching playlist entries are removed. Source audio files are not changed.")
        }
        .confirmationDialog("Copy artwork into managed storage?", isPresented: Binding(get: { artworkToMigrate != nil }, set: { if !$0 { artworkToMigrate = nil } }), titleVisibility: .visible, presenting: artworkToMigrate) { image in
            Button("Copy Artwork") {
                Task {
                    do {
                        try await library.migrateArtworkToManagedStorage(image)
                        artworkToMigrate = nil
                        await loadContent()
                    } catch {
                        library.presentError(error)
                    }
                }
            }
        } message: { image in
            Text("A managed copy of \(image.localPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "this artwork") will be stored with the catalogue. The original file will not be modified or deleted.")
        }
        .fileImporter(isPresented: $showsArtworkPicker, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                Task {
                    do { try await library.addAlbumArtwork(albumID: album.id, from: url, role: .front); await loadContent() }
                    catch { library.presentError(error) }
                }
            }
        }
    }

    private var locationName: String {
        if let placement { return "In box set: \(placement.boxSetTitle)" }
        if album.isPhysicalLocationUnknown { return "Unknown" }
        guard let id = album.physicalLocationID else { return "Not recorded" }
        if let location = locations.first(where: { $0.id == id }) {
            return locationPath(location, in: locations)
        }
        return "Unknown location"
    }

    private var playableTracks: [Track] {
        discs.flatMap { tracksByDisc[$0.id] ?? [] }
    }

    private var trackSummary: String {
        guard !discs.isEmpty else { return "No catalogue tracks yet" }
        let trackWord = playableTracks.count == 1 ? "track" : "tracks"
        let discWord = discs.count == 1 ? "disc" : "discs"
        return "\(playableTracks.count) \(trackWord) across \(discs.count) \(discWord)"
    }

    private func playAlbum(shuffled: Bool) {
        Task {
            do {
                var items: [(url: URL, trackID: TrackID, title: String, cueStartMilliseconds: Int?, cueEndMilliseconds: Int?)] = []
                for disc in discs {
                    items.append(contentsOf: try await library.playbackURLs(discID: disc.id))
                }
                guard !items.isEmpty else { return }
                try playback.play(items: items, startingAt: 0)
                if shuffled { playback.toggleShuffle() }
            } catch {
                library.presentError(error)
            }
        }
    }

    private func moveDisc(_ disc: Disc, to position: Int) {
        Task {
            do {
                try await library.reorderDisc(disc.id, in: album.id, to: position)
                await loadContent()
            } catch {
                library.presentError(error)
            }
        }
    }

    private func removeAlbumContributor(_ credit: ContributorCredit) {
        Task {
            do {
                try await library.deleteAlbumContributor(credit, from: album.id)
                await loadContent()
            } catch {
                library.presentError(error)
            }
        }
    }

    private func removeTrackCredit(_ credit: ContributorCredit, from track: Track) {
        Task {
            do {
                try await library.deleteTrackContributor(credit, from: track.id)
                await loadContent()
            } catch {
                library.presentError(error)
            }
        }
    }

    private func removeAlias(_ alias: AlbumAlias) {
        Task {
            do {
                try await library.deleteAlbumAlias(alias.id)
                await loadContent()
            } catch {
                library.presentError(error)
            }
        }
    }

    @ViewBuilder
    private var artworkManagementContent: some View {
        if artwork.isEmpty {
            Text("No front artwork selected")
                .foregroundStyle(.secondary)
        }
        ForEach(artwork) { image in
            ArtworkManagementRow(
                image: image,
                isManaged: library.isManagedArtwork(image),
                onMakePortable: { artworkToMigrate = image }
            )
        }
        Button("Choose Artwork…", systemImage: "photo.badge.plus") { showsArtworkPicker = true }
    }

    private func loadContent() async {
        do {
            let loadedDiscs = try await library.discs(albumID: album.id)
            var mapped: [DiscID: [Track]] = [:]
            var loadedTrackCredits: [TrackID: [ContributorCredit]] = [:]
            for disc in loadedDiscs {
                let tracks = try await library.tracks(discID: disc.id)
                mapped[disc.id] = tracks
                for track in tracks {
                    loadedTrackCredits[track.id] = try await library.trackContributors(trackID: track.id)
                }
            }
            let loadedCredits = try await library.albumContributors(albumID: album.id)
            let loadedAliases = try await library.albumAliases(albumID: album.id)
            let loadedArtwork = try await library.albumArtwork(albumID: album.id)
            discs = loadedDiscs
            tracksByDisc = mapped
            trackCredits = loadedTrackCredits
            credits = loadedCredits
            aliases = loadedAliases
            artwork = loadedArtwork
        } catch {
            library.presentError(error)
        }
    }

    private func play(_ track: Track) {
        Task {
            do {
                let items = try await library.playbackURLs(discID: track.discID)
                guard let index = items.firstIndex(where: { $0.trackID == track.id }) else { return }
                try playback.play(items: items, startingAt: index)
            } catch {
                library.presentError(error)
            }
        }
    }

    @ViewBuilder
    private func playlistMenuContent(for track: Track) -> some View {
        if library.playlists.isEmpty {
            Text("Create a playlist from the Playlists sidebar first.")
        } else {
            ForEach(library.playlists) { playlist in
                Button(playlist.name) {
                    Task {
                        do {
                            try await library.addTrack(track.id, toPlaylist: playlist.id)
                        } catch {
                            library.presentError(error)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func albumTrackRow(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", track.number))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.body)
                        .lineLimit(2)
                    if let duration = track.durationMilliseconds, duration > 0 {
                        Text(trackDuration(duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let rating = track.rating {
                    Text("\(rating)★")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Play", systemImage: "play.fill") { play(track) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Menu {
                    Button("Edit Track", systemImage: "pencil") { trackToEdit = track }
                    Button("Show Embedded Metadata", systemImage: "info.circle") { metadataSelection = .init(trackID: track.id, title: track.title) }
                    Button("Lyrics", systemImage: "quote.bubble") { trackForLyrics = track }
                    Menu("Add to Playlist", systemImage: "text.badge.plus") {
                        playlistMenuContent(for: track)
                    }
                    Button("Add Credit", systemImage: "person.badge.plus") { trackForContributor = track }
                    Divider()
                    Button("Remove Track", systemImage: "trash", role: .destructive) { trackPendingDeletion = track }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Actions for \(track.title)")
            }
            if let credits = trackCredits[track.id], !credits.isEmpty {
                ForEach(credits) { credit in
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(credit.creditedName ?? credit.contributor.name) — \(credit.role.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Menu {
                            Button("Edit credited name", systemImage: "pencil") { trackCreditToEdit = .init(track: track, credit: credit) }
                            Button("Remove credit", systemImage: "trash", role: .destructive) { removeTrackCredit(credit, from: track) }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Credit actions")
                    }
                    .padding(.leading, 36)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func discHeaderRow(_ disc: Disc) -> some View {
        HStack {
            Image(systemName: "opticaldisc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(disc.title ?? "Disc \(disc.number)")
                    .font(.headline)
                Text("\(tracksByDisc[disc.id, default: []].count) track\(tracksByDisc[disc.id, default: []].count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Move Earlier", systemImage: "arrow.up") { moveDisc(disc, to: disc.number - 1) }
                    .disabled(disc.number <= 1)
                Button("Move Later", systemImage: "arrow.down") { moveDisc(disc, to: disc.number + 1) }
                    .disabled(disc.number >= discs.count)
                Divider()
                Button("Remove Disc", systemImage: "trash", role: .destructive) { discPendingDeletion = disc }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Actions for disc \(disc.number)")
        }
        .padding(.top, 3)
    }

    private func albumAliasRow(_ alias: AlbumAlias) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "textformat")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(alias.name)
                    .textSelection(.enabled)
                Text([alias.kind.rawValue.capitalized, alias.locale].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Remove Other Title", systemImage: "trash", role: .destructive) { removeAlias(alias) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Actions for \(alias.name)")
        }
    }

    private func trackDuration(_ milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1_000)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct ArtworkManagementRow: View {
    let image: Artwork
    let isManaged: Bool
    let onMakePortable: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(artworkLabel)
                    .font(.caption)
                Text(image.source.isEmpty ? "No provenance recorded" : image.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if image.localPath != nil {
                if isManaged {
                    Label("Managed", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Make Portable", systemImage: "archivebox", action: onMakePortable)
                        .font(.caption)
                }
            }
        }
    }

    private var artworkLabel: String {
        let selection = image.isSelected ? "Selected " : ""
        let filename = image.localPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No local file"
        return selection + image.role.rawValue + ": " + filename
    }
}

private struct ArtworkManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let artwork: [Artwork]
    @ObservedObject var library: LibraryStore
    let onChooseArtwork: () -> Void
    let onMigrate: (Artwork) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let selected = artwork.first(where: { $0.role == .front && $0.isSelected }) {
                        GroupBox("Current cover") {
                            HStack(alignment: .top, spacing: 16) {
                                ArtworkPreview(artwork: selected)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("This is the artwork shown beside the album title.")
                                        .font(.callout)
                                    Text("The catalogue keeps a managed copy when artwork is imported. A legacy path can be made portable here without changing or deleting the original file.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !library.isManagedArtwork(selected), selected.localPath != nil {
                                        Button("Make Portable", systemImage: "archivebox") {
                                            onMigrate(selected)
                                            dismiss()
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        ContentUnavailableView("No cover selected", systemImage: "photo", description: Text("Choose a front image to display with this album."))
                    }

                    GroupBox("Artwork records") {
                        if artwork.isEmpty {
                            Text("No artwork records are stored for this album.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(artwork) { image in
                                    ArtworkManagementRow(
                                        image: image,
                                        isManaged: library.isManagedArtwork(image),
                                        onMakePortable: {
                                            onMigrate(image)
                                            dismiss()
                                        }
                                    )
                                    if image.id != artwork.last?.id { Divider() }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Artwork")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Choose Cover…", systemImage: "photo.badge.plus") {
                        onChooseArtwork()
                    }
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 520, idealHeight: 620)
    }
}

private struct TrackCreditSelection: Identifiable {
    let track: Track
    let credit: ContributorCredit
    var id: String { "\(track.id.description)-\(credit.id)" }
}

private struct AddDiscEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let albumID: AlbumID
    let onAdded: () async -> Void
    @State private var title = ""
    var body: some View {
        Form { TextField("Disc title (optional)", text: $title) }
            .padding().frame(width: 360)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { add() } } }
    }
    private func add() { Task { do { try await library.addDisc(albumID: albumID, title: title.nilIfBlank); await onAdded(); dismiss() } catch { library.presentError(error) } } }
}

private struct AddTrackEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let disc: Disc
    let onAdded: () async -> Void
    @State private var title = ""
    @State private var rating = 0
    var body: some View {
        Form { TextField("Track title", text: $title); Picker("Rating", selection: $rating) { Text("Not rated").tag(0); ForEach(1...5, id: \.self) { Text("\($0) star\($0 == 1 ? "" : "s")").tag($0) } } }
            .padding().frame(width: 360)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { add() }.disabled(title.nilIfBlank == nil) } }
    }
    private func add() { Task { do { try await library.addTrack(discID: disc.id, draft: .init(title: title, rating: rating == 0 ? nil : rating)); await onAdded(); dismiss() } catch { library.presentError(error) } } }
}

private struct EditTrackEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let track: Track
    let onSaved: () async -> Void
    @State private var title: String
    @State private var displayPosition: String
    @State private var durationSeconds: String
    @State private var workName: String
    @State private var movementNumber: String
    @State private var movementName: String
    @State private var instrumental: Bool
    @State private var rating: Int
    @State private var errorMessage: String?

    init(library: LibraryStore, track: Track, onSaved: @escaping () async -> Void) {
        self.library = library
        self.track = track
        self.onSaved = onSaved
        _title = State(initialValue: track.title)
        _displayPosition = State(initialValue: track.displayPosition ?? "")
        _durationSeconds = State(initialValue: track.durationMilliseconds.map { String($0 / 1_000) } ?? "")
        _workName = State(initialValue: track.workName ?? "")
        _movementNumber = State(initialValue: track.movementNumber.map(String.init) ?? "")
        _movementName = State(initialValue: track.movementName ?? "")
        _instrumental = State(initialValue: track.isInstrumental ?? false)
        _rating = State(initialValue: track.rating ?? 0)
    }

    var body: some View {
        Form {
            Section("Track") { TextField("Track title", text: $title); TextField("Display position (optional)", text: $displayPosition); TextField("Duration in seconds (optional)", text: $durationSeconds) }
            Section("Classical / detailed metadata") { TextField("Work name (optional)", text: $workName); TextField("Movement number (optional)", text: $movementNumber); TextField("Movement name (optional)", text: $movementName); Toggle("Instrumental", isOn: $instrumental) }
            Picker("Rating", selection: $rating) { Text("Not rated").tag(0); ForEach(1...5, id: \.self) { Text("\($0) star\($0 == 1 ? "" : "s")").tag($0) } }
            Text("These are catalogue corrections only; source audio tags are not changed.").font(.caption).foregroundStyle(.secondary)
        }
            .padding().frame(width: 440)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.nilIfBlank == nil) }
            }
            .alert("Unable to update track", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func save() {
        Task {
            do {
                try await library.updateTrack(track.id, draft: .init(title: title, displayPosition: displayPosition.nilIfBlank, durationMilliseconds: Int(durationSeconds).map { $0 * 1_000 }, workName: workName.nilIfBlank, movementNumber: Int(movementNumber), movementName: movementName.nilIfBlank, isInstrumental: instrumental, rating: rating == 0 ? nil : rating))
                await onSaved()
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct AddAliasEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let albumID: AlbumID
    let onAdded: () async -> Void
    @State private var name = ""
    @State private var kind: AlbumAliasKind = .alternate
    @State private var locale = ""
    var body: some View {
        Form {
            Section("Other title") {
                TextField("Title", text: $name)
                Picker("Type", selection: $kind) { ForEach(AlbumAliasKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                TextField("Language or locale (optional)", text: $locale)
            }
            Text("Other titles are catalogue names used for search and display. They do not replace the primary album title.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
            .padding().frame(width: 380)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add Other Title") { add() }.disabled(name.nilIfBlank == nil) } }
    }
    private func add() { Task { do { try await library.addAlbumAlias(albumID: albumID, name: name, kind: kind, locale: locale.nilIfBlank); await onAdded(); dismiss() } catch { library.presentError(error) } } }
}

private struct AddContributorEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let albumID: AlbumID
    let onAdded: () async -> Void
    @State private var name = ""
    @State private var creditedName = ""
    @State private var role: ContributorRole = .albumArtist
    var body: some View {
        Form { TextField("Contributor name", text: $name); Picker("Role", selection: $role) { ForEach(ContributorRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; TextField("Credited name (optional)", text: $creditedName) }
            .padding().frame(width: 400)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { add() }.disabled(name.nilIfBlank == nil) } }
    }
    private func add() { Task { do { try await library.addAlbumContributor(albumID: albumID, name: name, role: role, creditedName: creditedName.nilIfBlank); await onAdded(); dismiss() } catch { library.presentError(error) } } }
}

private struct EditContributorEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let contributor: Contributor
    let onSaved: () async -> Void
    @State private var name: String
    @State private var sortName: String
    @State private var errorMessage: String?

    init(library: LibraryStore, contributor: Contributor, onSaved: @escaping () async -> Void) {
        self.library = library
        self.contributor = contributor
        self.onSaved = onSaved
        _name = State(initialValue: contributor.name)
        _sortName = State(initialValue: contributor.sortName ?? "")
    }

    var body: some View {
        Form {
            TextField("Contributor name", text: $name)
            TextField("Sort name (optional)", text: $sortName)
            Text("This corrects the catalogue name anywhere this contributor is credited. It does not change audio-file tags.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding().frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.nilIfBlank == nil) }
        }
        .alert("Unable to update contributor", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func save() {
        Task {
            do {
                try await library.updateContributor(contributor.id, draft: .init(name: name, sortName: sortName.nilIfBlank))
                await onSaved()
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct AddTrackContributorEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let track: Track
    let onAdded: () async -> Void
    @State private var name = ""
    @State private var creditedName = ""
    @State private var role: ContributorRole = .performer
    var body: some View {
        Form { TextField("Contributor name", text: $name); Picker("Role", selection: $role) { ForEach(ContributorRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; TextField("Credited name (optional)", text: $creditedName) }
            .padding().frame(width: 400)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { add() }.disabled(name.nilIfBlank == nil) } }
    }
    private func add() { Task { do { try await library.addTrackContributor(trackID: track.id, name: name, role: role, creditedName: creditedName.nilIfBlank); await onAdded(); dismiss() } catch { library.presentError(error) } } }
}

private struct EditAlbumCreditedNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let albumID: AlbumID
    let credit: ContributorCredit
    let onSaved: () async -> Void
    @State private var creditedName: String
    @State private var role: ContributorRole
    @State private var errorMessage: String?

    init(library: LibraryStore, albumID: AlbumID, credit: ContributorCredit, onSaved: @escaping () async -> Void) {
        self.library = library
        self.albumID = albumID
        self.credit = credit
        self.onSaved = onSaved
        _creditedName = State(initialValue: credit.creditedName ?? credit.contributor.name)
        _role = State(initialValue: credit.role)
    }

    var body: some View {
        Form {
            TextField("Credited name", text: $creditedName)
            Picker("Role", selection: $role) { ForEach(ContributorRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Text("This changes only this album credit. The shared contributor record and audio-file tags are not changed. A changed role is placed last within its new role.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding().frame(width: 440)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
        .alert("Unable to update credit", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func save() { Task { do { try await library.updateAlbumContributorCredit(credit, in: albumID, creditedName: creditedName.nilIfBlank, newRole: role); await onSaved(); dismiss() } catch { errorMessage = error.localizedDescription } } }
}

private struct EditTrackCreditedNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let track: Track
    let credit: ContributorCredit
    let onSaved: () async -> Void
    @State private var creditedName: String
    @State private var role: ContributorRole
    @State private var errorMessage: String?

    init(library: LibraryStore, track: Track, credit: ContributorCredit, onSaved: @escaping () async -> Void) {
        self.library = library
        self.track = track
        self.credit = credit
        self.onSaved = onSaved
        _creditedName = State(initialValue: credit.creditedName ?? credit.contributor.name)
        _role = State(initialValue: credit.role)
    }

    var body: some View {
        Form {
            TextField("Credited name", text: $creditedName)
            Picker("Role", selection: $role) { ForEach(ContributorRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Text("This changes only this track credit. The shared contributor record and audio-file tags are not changed. A changed role is placed last within its new role.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding().frame(width: 440)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
        .alert("Unable to update credit", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func save() { Task { do { try await library.updateTrackContributorCredit(credit, in: track.id, creditedName: creditedName.nilIfBlank, newRole: role); await onSaved(); dismiss() } catch { errorMessage = error.localizedDescription } } }
}

private func locationPath(_ location: PhysicalLocation, in locations: [PhysicalLocation]) -> String {
    var names: [String] = []
    var current: PhysicalLocation? = location
    var visited = Set<PhysicalLocationID>()
    while let value = current, visited.insert(value.id).inserted {
        names.append(value.name)
        current = value.parentID.flatMap { parentID in locations.first(where: { $0.id == parentID }) }
    }
    return names.reversed().joined(separator: " › ")
}

private func locationDepth(_ location: PhysicalLocation, in locations: [PhysicalLocation]) -> Int {
    var depth = 0
    var current = location
    var visited = Set<PhysicalLocationID>()
    while let parentID = current.parentID, visited.insert(current.id).inserted,
          let parent = locations.first(where: { $0.id == parentID }) {
        depth += 1
        current = parent
    }
    return depth
}

private func isLocationDescendant(_ candidate: PhysicalLocation, of ancestorID: PhysicalLocationID, in locations: [PhysicalLocation]) -> Bool {
    var current = candidate
    var visited = Set<PhysicalLocationID>()
    while let parentID = current.parentID, visited.insert(current.id).inserted {
        if parentID == ancestorID { return true }
        guard let parent = locations.first(where: { $0.id == parentID }) else { return false }
        current = parent
    }
    return false
}

private struct LocationList: View {
    @ObservedObject var library: LibraryStore
    @State private var locationToRename: PhysicalLocation?
    @State private var locationToMove: PhysicalLocation?
    @State private var locationToDelete: PhysicalLocation?

    private var orderedLocations: [PhysicalLocation] {
        library.locations.sorted { left, right in
            locationPath(left, in: library.locations).localizedCaseInsensitiveCompare(locationPath(right, in: library.locations)) == .orderedAscending
        }
    }

    var body: some View {
        List(orderedLocations) { location in
            Text(locationPath(location, in: library.locations))
                .padding(.leading, CGFloat(locationDepth(location, in: library.locations)) * 14)
                .contextMenu {
                    Button("Move…") { locationToMove = location }
                    Button("Rename") { locationToRename = location }
                    Divider()
                    Button("Delete", role: .destructive) { locationToDelete = location }
                }
        }
        .overlay {
            if library.isReady && library.locations.isEmpty {
                ContentUnavailableView("No locations", systemImage: "archivebox", description: Text("Create locations such as Living Room › Cabinet A › Shelf 2."))
            }
        }
        .sheet(item: $locationToRename) { location in
            RenameLocationEditor(library: library, location: location)
        }
        .sheet(item: $locationToMove) { location in
            MoveLocationEditor(library: library, location: location)
        }
        .alert("Delete location?", isPresented: Binding(get: { locationToDelete != nil }, set: { if !$0 { locationToDelete = nil } }), presenting: locationToDelete) { location in
            Button("Delete", role: .destructive) {
                Task {
                    do { try await library.deleteLocation(location.id) }
                    catch { library.presentError(error) }
                    locationToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { locationToDelete = nil }
        } message: { location in
            Text("This removes \(locationPath(location, in: library.locations)). Albums, box sets, and child locations must be moved first.")
        }
    }
}

private enum ManualAlbumPlacement: String, CaseIterable, Identifiable {
    case location
    case boxSet
    case unknown

    var id: Self { self }
    var title: String {
        switch self {
        case .location: "Location"
        case .boxSet: "Box Set"
        case .unknown: "Unknown"
        }
    }
}

private struct ManualAlbumContributor: Identifiable {
    let id = UUID()
    var name = ""
    var role: ContributorRole = .albumArtist
    var creditedName = ""
}

extension ContributorRole {
    var displayName: String {
        switch self {
        case .albumArtist: "Album Artist"
        case .performer: "Performer"
        case .composer: "Composer"
        case .conductor: "Conductor"
        case .orchestra: "Orchestra"
        case .ensemble: "Ensemble"
        case .soloist: "Soloist"
        case .featuredArtist: "Featured Artist"
        case .remixer: "Remixer"
        case .producer: "Producer"
        }
    }
}

private struct AlbumEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    @State private var title = ""
    @State private var editionLabel = ""
    @State private var releaseYear = ""
    @State private var countryCode = ""
    @State private var labelName = ""
    @State private var catalogueNumber = ""
    @State private var barcode = ""
    @State private var remasterYear = ""
    @State private var mediaFormat = "CD"
    @State private var discCount = 1
    @State private var physicalNote = ""
    @State private var notes = ""
    @State private var rating = 0
    @State private var isFavourite = false
    @State private var contributorDrafts = [ManualAlbumContributor()]
    @State private var showsMusicBrainzLookup = false
    @State private var selectedMusicBrainzRelease: ExternalReleasePreview?
    @State private var saveMusicBrainzCover = false
    @State private var isAddingAlbum = false
    @State private var placement: ManualAlbumPlacement = .location
    @State private var selectedLocationID: PhysicalLocationID?
    @State private var selectedBoxSetID: BoxSetID?
    @State private var showsNewLocationFields = false
    @State private var newLocationName = ""
    @State private var newLocationParentID: PhysicalLocationID?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Album") {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Button("Find on MusicBrainz…", systemImage: "magnifyingglass") {
                        showsMusicBrainzLookup = true
                    }
                    Text("Fill returned release details into this form; placement, notes, and extra credits stay unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let release = selectedMusicBrainzRelease {
                    HStack(alignment: .top, spacing: 12) {
                        AsyncImage(url: release.coverArtworkThumbnailURL) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            case .failure:
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            default: ProgressView()
                            }
                        }
                        .frame(width: 72, height: 72)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("MusicBrainz front cover selected")
                                .font(.subheadline.weight(.medium))
                            Text("The full cover will be copied into managed artwork storage when this album is added.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Toggle("Save cover with album", isOn: $saveMusicBrainzCover)
                                .toggleStyle(.checkbox)
                            Button("Clear release and cover") {
                                selectedMusicBrainzRelease = nil
                                saveMusicBrainzCover = false
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }
                TextField("Title", text: $title)
                TextField("Edition label", text: $editionLabel, prompt: Text("Japan version, 2011 remaster…"))
                TextField("Release year", text: $releaseYear)
                TextField("Country/region", text: $countryCode)
                TextField("Record label", text: $labelName)
                TextField("Catalogue number", text: $catalogueNumber)
                TextField("Barcode", text: $barcode)
                TextField("Remaster year", text: $remasterYear)
                TextField("Media format", text: $mediaFormat, prompt: Text("CD, SACD…"))
                Stepper("Discs: \(discCount)", value: $discCount, in: 1...99)
                Picker("Rating", selection: $rating) { Text("Not rated").tag(0); ForEach(1...5, id: \.self) { Text("\($0) star\($0 == 1 ? "" : "s")").tag($0) } }
                Toggle("Favourite", isOn: $isFavourite)
            }

            Section("Contributors") {
                ForEach($contributorDrafts) { $credit in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Contributor name", text: $credit.name)
                            Picker("Role", selection: $credit.role) {
                                ForEach(ContributorRole.allCases, id: \.self) { role in
                                    Text(role.displayName).tag(role)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 155)
                            Button(role: .destructive) {
                                contributorDrafts.removeAll { $0.id == credit.id }
                            } label: {
                                Label("Remove Contributor", systemImage: "minus.circle")
                            }
                            .labelStyle(.iconOnly)
                            .disabled(contributorDrafts.count == 1)
                        }
                        HStack {
                            TextField("Credited name (optional)", text: $credit.creditedName)
                            if !library.contributors.isEmpty {
                                Menu("Use Existing") {
                                    ForEach(library.contributors) { contributor in
                                        Button(contributor.name) { credit.name = contributor.name }
                                    }
                                }
                            }
                        }
                    }
                }
                Button("Add Contributor", systemImage: "person.badge.plus") {
                    contributorDrafts.append(.init())
                }
                if contributorDrafts.contains(where: { $0.name.nilIfBlank == nil }) {
                    Label("Fill or remove every empty contributor row to enable Add Physical Album.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Use roles for composers, performers, conductors, ensembles, producers, and other credits. Existing names are reused instead of creating duplicates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Physical Location") {
                Picker("Stored in", selection: $placement) {
                    ForEach(ManualAlbumPlacement.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)

                switch placement {
                case .location:
                    Picker("Location", selection: $selectedLocationID) {
                        Text("Choose a location").tag(PhysicalLocationID?.none)
                        ForEach(orderedLocations) { location in
                            Text(locationPath(location, in: library.locations)).tag(Optional(location.id))
                        }
                    }
                    DisclosureGroup("Create and select a new location", isExpanded: $showsNewLocationFields) {
                        TextField("Location name", text: $newLocationName)
                        Picker("Inside", selection: $newLocationParentID) {
                            Text("Top level").tag(PhysicalLocationID?.none)
                            ForEach(orderedLocations) { location in
                                Text(locationPath(location, in: library.locations)).tag(Optional(location.id))
                            }
                        }
                        Button("Create and Select", systemImage: "plus") { createAndSelectLocation() }
                            .disabled(newLocationName.nilIfBlank == nil)
                    }
                case .boxSet:
                    Picker("Box set", selection: $selectedBoxSetID) {
                        Text("Choose a box set").tag(BoxSetID?.none)
                        ForEach(library.boxSets) { box in Text(box.title).tag(Optional(box.id)) }
                    }
                    if library.boxSets.isEmpty {
                        Text("Create the box and its shared location in Box Sets first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .unknown:
                    Label("Location not yet known", systemImage: "questionmark.circle")
                    Text("The album will be clearly marked as needing a location. You can assign one later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Physical note (optional)", text: $physicalNote, axis: .vertical)
                    .lineLimit(2...4)
                    .help("For example: second row, signed copy, damaged case, or loaned out")
            }

            Section("Notes") {
                TextField("Catalogue notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                Label("Catalogue information only—no audio files are created or changed.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620)
        .frame(minHeight: 720)
        .navigationTitle("Add Physical Album")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isAddingAlbum ? "Adding…" : "Add Physical Album") { addAlbum() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit || isAddingAlbum)
            }
        }
        .alert("Unable to add album", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showsMusicBrainzLookup) {
            PhysicalAlbumMusicBrainzLookupView(library: library, title: title, artist: contributorDrafts.first?.name) { release in
                applyMusicBrainzRelease(release)
            }
        }
        .onChange(of: placement) { _, newPlacement in
            if newPlacement != .location { selectedLocationID = nil }
            if newPlacement != .boxSet { selectedBoxSetID = nil }
        }
    }

    private var orderedLocations: [PhysicalLocation] {
        library.locations.sorted { locationPath($0, in: library.locations) < locationPath($1, in: library.locations) }
    }

    private var canSubmit: Bool {
        guard title.nilIfBlank != nil,
              !contributorDrafts.isEmpty,
              contributorDrafts.allSatisfy({ $0.name.nilIfBlank != nil }) else { return false }
        switch placement {
        case .location: return selectedLocationID != nil
        case .boxSet: return selectedBoxSetID != nil
        case .unknown: return true
        }
    }

    private func createAndSelectLocation() {
        Task {
            do {
                let location = try await library.addLocation(.init(name: newLocationName, parentID: newLocationParentID))
                selectedLocationID = location.id
                newLocationName = ""
                newLocationParentID = nil
                showsNewLocationFields = false
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func applyMusicBrainzRelease(_ release: ExternalReleasePreview) {
        selectedMusicBrainzRelease = release
        saveMusicBrainzCover = release.coverArtworkURL != nil
        title = release.title
        if let releaseYear = release.releaseYear { self.releaseYear = String(releaseYear) }
        if let countryCode = release.countryCode?.nilIfBlank { self.countryCode = countryCode }
        if let labelName = release.labelName?.nilIfBlank { self.labelName = labelName }
        if let catalogueNumber = release.catalogueNumber?.nilIfBlank { self.catalogueNumber = catalogueNumber }
        if let barcode = release.barcode?.nilIfBlank { self.barcode = barcode }
        if let mediaFormat = release.mediaFormat?.nilIfBlank { self.mediaFormat = mediaFormat }
        if release.mediaCount > 0 { discCount = release.mediaCount }

        guard let artist = release.artist?.nilIfBlank else { return }
        let normalizedArtist = artist.lowercased()
        if let blankIndex = contributorDrafts.firstIndex(where: { $0.name.nilIfBlank == nil }) {
            contributorDrafts[blankIndex].name = artist
            contributorDrafts[blankIndex].role = .albumArtist
        } else if !contributorDrafts.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedArtist }) {
            contributorDrafts.insert(.init(name: artist, role: .albumArtist), at: 0)
        }
    }

    private func addAlbum() {
        isAddingAlbum = true
        Task {
            defer { isAddingAlbum = false }
            do {
                let directLocationID = placement == .location ? selectedLocationID : nil
                let boxSetID = placement == .boxSet ? selectedBoxSetID : nil
                let draft = NewAlbum(
                    title: title,
                    editionLabel: editionLabel.nilIfBlank,
                    releaseYear: Int(releaseYear),
                    countryCode: countryCode.nilIfBlank,
                    labelName: labelName.nilIfBlank,
                    catalogueNumber: catalogueNumber.nilIfBlank,
                    barcode: barcode.nilIfBlank,
                    remasterYear: Int(remasterYear),
                    mediaFormat: mediaFormat.nilIfBlank,
                    discCount: discCount,
                    hasCD: true,
                    physicalLocationID: directLocationID,
                    isPhysicalLocationUnknown: placement == .unknown,
                    physicalNote: physicalNote.nilIfBlank,
                    notes: notes.nilIfBlank,
                    rating: rating == 0 ? nil : rating,
                    isFavourite: isFavourite
                )
                let credits = contributorDrafts.map {
                    NewAlbumContributorCredit(name: $0.name, role: $0.role, creditedName: $0.creditedName.nilIfBlank)
                }
                try await library.addAlbum(
                    draft,
                    toBoxSet: boxSetID,
                    contributors: credits,
                    musicBrainzArtworkURL: saveMusicBrainzCover ? selectedMusicBrainzRelease?.coverArtworkURL : nil
                )
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct LocationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    @State private var name = ""
    @State private var parentID: PhysicalLocationID?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Location name", text: $name)
            Picker("Inside", selection: $parentID) {
                Text("Top level").tag(PhysicalLocationID?.none)
                ForEach(library.locations.sorted { locationPath($0, in: library.locations) < locationPath($1, in: library.locations) }) { location in Text(locationPath(location, in: library.locations)).tag(Optional(location.id)) }
            }
        }
        .padding()
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Add") { addLocation() }.keyboardShortcut(.defaultAction) }
        }
        .alert("Unable to add location", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func addLocation() {
        Task {
            do { _ = try await library.addLocation(.init(name: name, parentID: parentID)); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct RenameLocationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let location: PhysicalLocation
    @State private var name: String
    @State private var errorMessage: String?

    init(library: LibraryStore, location: PhysicalLocation) {
        self.library = library
        self.location = location
        _name = State(initialValue: location.name)
    }

    var body: some View {
        Form { TextField("Location name", text: $name) }
            .padding()
            .frame(width: 360)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { rename() }.keyboardShortcut(.defaultAction) }
            }
            .alert("Unable to rename location", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }

    private func rename() {
        Task {
            do { try await library.renameLocation(location.id, to: name); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct MoveLocationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let location: PhysicalLocation
    @State private var parentID: PhysicalLocationID?
    @State private var errorMessage: String?

    init(library: LibraryStore, location: PhysicalLocation) {
        self.library = library
        self.location = location
        _parentID = State(initialValue: location.parentID)
    }

    private var possibleParents: [PhysicalLocation] {
        library.locations
            .filter { $0.id != location.id && !isLocationDescendant($0, of: location.id, in: library.locations) }
            .sorted { locationPath($0, in: library.locations) < locationPath($1, in: library.locations) }
    }

    var body: some View {
        Form {
            Text("Move \(location.name) and all of its children.")
                .font(.headline)
            Picker("Inside", selection: $parentID) {
                Text("Top level").tag(PhysicalLocationID?.none)
                ForEach(possibleParents) { parent in
                    Text(locationPath(parent, in: library.locations)).tag(Optional(parent.id))
                }
            }
        }
        .padding()
        .frame(width: 460)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Move") { move() }.keyboardShortcut(.defaultAction) }
        }
        .alert("Unable to move location", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func move() {
        Task {
            do { try await library.moveLocation(location.id, under: parentID); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct BoxSetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    @State private var title = ""
    @State private var editionLabel = ""
    @State private var locationID: PhysicalLocationID?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Box set title", text: $title)
            TextField("Edition label", text: $editionLabel)
            Picker("Location", selection: $locationID) {
                Text("Choose a location").tag(PhysicalLocationID?.none)
                ForEach(library.locations.sorted { locationPath($0, in: library.locations) < locationPath($1, in: library.locations) }) { location in Text(locationPath(location, in: library.locations)).tag(Optional(location.id)) }
            }
        }
        .padding()
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Add") { addBoxSet() }.keyboardShortcut(.defaultAction).disabled(locationID == nil) }
        }
        .alert("Unable to add box set", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func addBoxSet() {
        guard let locationID else { return }
        Task {
            do { try await library.addBoxSet(.init(title: title, editionLabel: editionLabel.nilIfBlank, physicalLocationID: locationID)); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct EditAlbumEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let album: Album
    @State private var title: String
    @State private var editionLabel: String
    @State private var releaseYear: String
    @State private var countryCode: String
    @State private var labelName: String
    @State private var catalogueNumber: String
    @State private var barcode: String
    @State private var remasterYear: String
    @State private var mediaFormat: String
    @State private var discCount: Int
    @State private var hasCD: Bool
    @State private var physicalNote: String
    @State private var notes: String
    @State private var rating: Int
    @State private var isFavourite: Bool
    @State private var locationID: PhysicalLocationID?
    @State private var locationUnknown: Bool
    @State private var placement: AlbumBoxPlacement?
    @State private var errorMessage: String?

    init(library: LibraryStore, album: Album) {
        self.library = library
        self.album = album
        _title = State(initialValue: album.title)
        _editionLabel = State(initialValue: album.editionLabel ?? "")
        _releaseYear = State(initialValue: album.releaseYear.map(String.init) ?? "")
        _countryCode = State(initialValue: album.countryCode ?? "")
        _labelName = State(initialValue: album.labelName ?? "")
        _catalogueNumber = State(initialValue: album.catalogueNumber ?? "")
        _barcode = State(initialValue: album.barcode ?? "")
        _remasterYear = State(initialValue: album.remasterYear.map(String.init) ?? "")
        _mediaFormat = State(initialValue: album.mediaFormat ?? "")
        _discCount = State(initialValue: album.discCount)
        _hasCD = State(initialValue: album.hasCD)
        _physicalNote = State(initialValue: album.physicalNote ?? "")
        _notes = State(initialValue: album.notes ?? "")
        _rating = State(initialValue: album.rating ?? 0)
        _isFavourite = State(initialValue: album.isFavourite)
        _locationID = State(initialValue: album.physicalLocationID)
        _locationUnknown = State(initialValue: album.isPhysicalLocationUnknown)
    }

    var body: some View {
        Form {
            Section("Album") {
                TextField("Title", text: $title)
                TextField("Edition label", text: $editionLabel)
                TextField("Release year", text: $releaseYear)
                TextField("Country/region", text: $countryCode)
                TextField("Record label", text: $labelName)
                TextField("Catalogue number", text: $catalogueNumber)
                TextField("Barcode", text: $barcode)
                TextField("Remaster year", text: $remasterYear)
                TextField("Media format", text: $mediaFormat)
                Stepper("Discs: \(discCount)", value: $discCount, in: 1...99)
                Picker("Rating", selection: $rating) { Text("Not rated").tag(0); ForEach(1...5, id: \.self) { Text("\($0) star\($0 == 1 ? "" : "s")").tag($0) } }
                Toggle("Favourite", isOn: $isFavourite)
            }
            Section("Physical CD") {
                if let placement {
                    LabeledContent("Box set", value: placement.boxSetTitle)
                    Text("Remove this album from its box set before changing CD availability or physical location.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Toggle("CD is available", isOn: $hasCD)
                    if hasCD {
                        Picker("Location", selection: $locationID) {
                            Text("Choose a location").tag(PhysicalLocationID?.none)
                            ForEach(library.locations.sorted { locationPath($0, in: library.locations) < locationPath($1, in: library.locations) }) { location in Text(locationPath(location, in: library.locations)).tag(Optional(location.id)) }
                        }
                        Toggle("Physical location is unknown", isOn: $locationUnknown)
                            .onChange(of: locationUnknown) { _, unknown in if unknown { locationID = nil } }
                        TextField("Physical note (optional)", text: $physicalNote, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
            }
            Section("Notes") {
                TextField("Catalogue notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .task {
            do {
                placement = try await library.boxPlacement(for: album.id)
            } catch {
                library.presentError(error)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.keyboardShortcut(.defaultAction) }
        }
        .alert("Unable to update album", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func save() {
        Task {
            do {
                var draft = album.draft
                draft.title = title
                draft.editionLabel = editionLabel.nilIfBlank
                draft.releaseYear = Int(releaseYear)
                draft.countryCode = countryCode.nilIfBlank
                draft.labelName = labelName.nilIfBlank
                draft.catalogueNumber = catalogueNumber.nilIfBlank
                draft.barcode = barcode.nilIfBlank
                draft.remasterYear = Int(remasterYear)
                draft.mediaFormat = mediaFormat.nilIfBlank
                draft.discCount = discCount
                draft.physicalNote = hasCD ? physicalNote.nilIfBlank : nil
                draft.notes = notes.nilIfBlank
                draft.rating = rating == 0 ? nil : rating
                draft.isFavourite = isFavourite
                if placement == nil {
                    draft.hasCD = hasCD
                    draft.physicalLocationID = hasCD && !locationUnknown ? locationID : nil
                    draft.isPhysicalLocationUnknown = hasCD && locationUnknown
                }
                try await library.updateAlbum(album.id, with: draft)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct BoxSetDetail: View {
    @ObservedObject var library: LibraryStore
    let boxSet: BoxSet
    @State private var members: [BoxSetMembership] = []
    @State private var memberToRemove: BoxSetMembership?
    @State private var showsAddMember = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Albums") {
                ForEach(members) { member in
                    HStack {
                        Text("\(member.position). \(member.album.displayTitle)")
                        Spacer()
                        Button("Up", systemImage: "arrow.up") { reorder(member, to: member.position - 1) }.disabled(member.position == 1)
                        Button("Down", systemImage: "arrow.down") { reorder(member, to: member.position + 1) }.disabled(member.position == members.count)
                        Button("Remove", systemImage: "minus.circle", role: .destructive) { memberToRemove = member }
                    }
                }
            }
        }
        .navigationTitle(boxSet.title)
        .toolbar { Button("Add Existing Album", systemImage: "plus") { showsAddMember = true } }
        .task(id: boxSet.id) { await reloadMembers() }
        .sheet(isPresented: $showsAddMember) { AddBoxMemberEditor(library: library, boxSet: boxSet, onAdded: { await reloadMembers() }) }
        .sheet(item: $memberToRemove) { member in RemoveBoxMemberEditor(library: library, boxSet: boxSet, member: member, onRemoved: { await reloadMembers() }) }
        .alert("Unable to update box set", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func reloadMembers() async {
        do { members = try await library.boxMembers(of: boxSet.id) }
        catch { errorMessage = error.localizedDescription }
    }

    private func reorder(_ member: BoxSetMembership, to position: Int) {
        Task {
            do { try await library.reorderAlbum(member.album.id, in: boxSet.id, to: position); await reloadMembers() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct AddBoxMemberEditor: View {
    private struct PendingMove: Identifiable {
        let albumID: AlbumID
        let sourceBoxTitle: String
        var id: AlbumID { albumID }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let boxSet: BoxSet
    let onAdded: () async -> Void
    @State private var selectedAlbumID: AlbumID?
    @State private var pendingMove: PendingMove?
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            Text("Choose an album to add or move into \(boxSet.title).")
                .font(.headline).padding()
            List(library.albums, selection: $selectedAlbumID) { album in Text(album.displayTitle).tag(album.id) }
        }
        .frame(width: 440, height: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Add or Move") { requestAdd() }.disabled(selectedAlbumID == nil) }
        }
        .alert("Unable to add album", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog("Move album to this box set?", isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } })) {
            Button("Move Album", role: .destructive) {
                if let pendingMove { performMove(pendingMove.albumID) }
            }
            Button("Cancel", role: .cancel) { pendingMove = nil }
        } message: {
            Text("This album is currently in \(pendingMove?.sourceBoxTitle ?? "another box set"). It will be removed there and added to \(boxSet.title).")
        }
    }

    private func requestAdd() {
        guard let selectedAlbumID else { return }
        Task {
            do {
                if let existing = try await library.boxPlacement(for: selectedAlbumID), existing.boxSetID != boxSet.id {
                    pendingMove = .init(albumID: selectedAlbumID, sourceBoxTitle: existing.boxSetTitle)
                } else {
                    performMove(selectedAlbumID)
                }
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func performMove(_ albumID: AlbumID) {
        Task {
            do { try await library.moveAlbum(albumID, to: boxSet.id); await onAdded(); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct RemoveBoxMemberEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let boxSet: BoxSet
    let member: BoxSetMembership
    let onRemoved: () async -> Void
    @State private var locationID: PhysicalLocationID?
    @State private var locationUnknown = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Text("Choose where to place \(member.album.displayTitle) after it is removed from this box.")
            Picker("Location", selection: $locationID) {
                Text("Choose a location").tag(PhysicalLocationID?.none)
                ForEach(library.locations.sorted { locationPath($0, in: library.locations) < locationPath($1, in: library.locations) }) { location in Text(locationPath(location, in: library.locations)).tag(Optional(location.id)) }
            }
            Toggle("Physical location is unknown", isOn: $locationUnknown)
                .onChange(of: locationUnknown) { _, unknown in if unknown { locationID = nil } }
        }
        .padding()
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Remove from Box", role: .destructive) { remove() }.disabled(locationID == nil && !locationUnknown) }
        }
        .alert("Unable to remove album", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func remove() {
        Task {
            do { try await library.removeAlbum(member.album.id, from: boxSet.id, assigning: locationID, locationUnknown: locationUnknown); await onRemoved(); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
