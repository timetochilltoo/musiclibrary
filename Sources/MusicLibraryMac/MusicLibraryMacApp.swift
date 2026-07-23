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
                .task { await library.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { Task { await library.flushPendingSnapshotPublication() } }
                }
        }
    }
}

private struct LibraryShellView: View {
    private enum Section: Hashable, CaseIterable, Identifiable {
        case albums, contributors, locations, boxSets, importInbox, playlists, settings
        var id: Self { self }
        var title: String {
            switch self {
            case .albums: "Albums"
            case .contributors: "Contributors"
            case .locations: "Locations"
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
            case .locations: "archivebox"
            case .boxSets: "shippingbox"
            case .importInbox: "tray"
            case .playlists: "music.note.list"
            case .settings: "gearshape"
            }
        }
    }

    @ObservedObject var library: LibraryStore
    @StateObject private var playback = PlaybackController()
    @State private var section: Section? = .albums
    @State private var selectedAlbumID: AlbumID?
    @State private var selectedContributorID: ContributorID?
    @State private var selectedBoxSetID: BoxSetID?
    @State private var selectedImportBatchID: ImportBatchID?
    @State private var selectedPlaylistID: PlaylistID?
    @State private var searchText = ""
    @State private var showsAlbumEditor = false
    @State private var showsLocationEditor = false
    @State private var showsBoxSetEditor = false
    @State private var showsStorageRootPicker = false
    @State private var showsScanRootPicker = false
    @State private var showsPlaylistEditor = false
    @State private var albumToEdit: Album?
    @State private var playlistToRename: Playlist?

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("Music Library")
        } content: {
            content
                .navigationTitle(section?.title ?? "Music Library")
                .toolbar { toolbar }
        } detail: {
            detail
        }
        .overlay {
            if !library.isReady && library.errorMessage == nil {
                ProgressView("Opening catalogue…")
            }
        }
        .sheet(isPresented: $showsAlbumEditor) { AlbumEditor(library: library) }
        .sheet(isPresented: $showsLocationEditor) { LocationEditor(library: library) }
        .sheet(isPresented: $showsBoxSetEditor) { BoxSetEditor(library: library) }
        .sheet(isPresented: $showsScanRootPicker) { ScanRootPicker(library: library) }
        .sheet(isPresented: $showsPlaylistEditor) { PlaylistEditor(library: library) }
        .sheet(item: $albumToEdit) { album in EditAlbumEditor(library: library, album: album) }
        .sheet(item: $playlistToRename) { playlist in PlaylistRenameEditor(library: library, playlist: playlist) }
        .fileImporter(isPresented: $showsStorageRootPicker, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { Task { try? await library.addStorageRoot(url: url) } }
        }
        .alert("Music Library", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.dismissError() } }
        )) {
            Button("OK", role: .cancel) { library.dismissError() }
        } message: {
            Text(library.errorMessage ?? "")
        }
        .safeAreaInset(edge: .bottom) {
            if playback.isPlaying || playback.currentTitle != "Nothing playing" {
                HStack { Image(systemName: playback.isPlaying ? "speaker.wave.2.fill" : "pause.circle"); Text(playback.currentTitle).lineLimit(1); Spacer(); Button("Previous", systemImage: "backward.fill") { playback.previous() }.labelStyle(.iconOnly); Button(playback.isPlaying ? "Pause" : "Play") { playback.toggle() }; Button("Next", systemImage: "forward.fill") { playback.next() }.labelStyle(.iconOnly); Menu("Queue") { Button("Shuffle") { playback.shuffle() }; Picker("Repeat", selection: Binding(get: { playback.queue.repeatMode }, set: { playback.setRepeatMode($0) })) { ForEach(RepeatMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } } }; Slider(value: Binding(get: { playback.volume }, set: { playback.setVolume(Float($0)) }), in: 0...1).frame(width: 90); Button("Stop") { playback.stop() } }
                    .padding(10).background(.bar)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .albums:
            List(library.albums, selection: $selectedAlbumID) { album in
                AlbumRow(album: album).tag(album.id).contextMenu { Button("Move to Recently Deleted", role: .destructive) { Task { do { try await library.softDeleteAlbum(album.id); if selectedAlbumID == album.id { selectedAlbumID = nil } } catch { library.presentError(error) } } } }
            }
            .searchable(text: $searchText, prompt: "Albums, editions, or catalogue numbers")
            .onChange(of: searchText) { _, value in Task { await library.search(value) } }
            .overlay {
                if library.isReady && library.albums.isEmpty {
                    ContentUnavailableView("No albums yet", systemImage: "opticaldisc", description: Text("Add a physical CD, a digital album, or both."))
                }
            }
        case .locations:
            LocationList(library: library)
        case .contributors:
            List(library.contributors, selection: $selectedContributorID) { contributor in
                VStack(alignment: .leading) {
                    Text(contributor.name)
                    if let sortName = contributor.sortName, sortName != contributor.name { Text(sortName).font(.caption).foregroundStyle(.secondary) }
                }.tag(contributor.id)
            }
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
        case .importInbox:
            List(library.importBatches, selection: $selectedImportBatchID) { batch in
                VStack(alignment: .leading) {
                    Text(batch.sourceDescription ?? "Music folder").lineLimit(1)
                    Text("\(batch.candidateCount) audio files · \(batch.errorCount) errors · \(batch.status.rawValue)").font(.caption).foregroundStyle(.secondary)
                }.tag(batch.id)
            }
            .overlay { if library.isReady && library.importBatches.isEmpty { ContentUnavailableView("No import batches", systemImage: "tray", description: Text("Choose an available music folder to scan into the review inbox.")) } }
        case .playlists:
            List(library.playlists, selection: $selectedPlaylistID) { playlist in
                Text(playlist.name)
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
            .overlay {
                if library.isReady && library.boxSets.isEmpty {
                    ContentUnavailableView("No box sets", systemImage: "shippingbox", description: Text("Create a box set to group its member albums at one location."))
                }
            }
        case .settings:
            StorageRootList(library: library) { albumID in
                selectedAlbumID = albumID
                section = .albums
            }
        default:
            ContentUnavailableView(section?.title ?? "Music Library", systemImage: section?.symbol ?? "music.note")
        }
    }

    @ViewBuilder private var detail: some View {
        if section == .contributors, let selectedContributorID, let contributor = library.contributors.first(where: { $0.id == selectedContributorID }) {
            ContributorDetail(library: library, contributor: contributor, onShowAlbum: { albumID in selectedAlbumID = albumID; section = .albums })
        } else if section == .boxSets, let selectedBoxSetID, let box = library.boxSets.first(where: { $0.id == selectedBoxSetID }) {
            BoxSetDetail(library: library, boxSet: box)
        } else if section == .importInbox, let selectedImportBatchID, let batch = library.importBatches.first(where: { $0.id == selectedImportBatchID }) {
            ImportBatchDetail(library: library, batch: batch)
        } else if section == .playlists, let selectedPlaylistID, let playlist = library.playlists.first(where: { $0.id == selectedPlaylistID }) {
            PlaylistDetail(library: library, playback: playback, playlist: playlist)
        } else if let selectedAlbumID, let album = library.albums.first(where: { $0.id == selectedAlbumID }) {
            AlbumDetail(library: library, playback: playback, album: album, locations: library.locations, onEdit: { albumToEdit = album })
        } else {
            ContentUnavailableView("Select an album", systemImage: "opticaldisc", description: Text("Album details will appear here."))
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(section == .locations ? "Add Location" : section == .boxSets ? "Add Box Set" : section == .settings ? "Add Music Folder" : section == .importInbox ? "Scan Music Folder" : section == .playlists ? "Add Playlist" : "Add Album", systemImage: "plus") {
                switch section {
                case .locations: showsLocationEditor = true
                case .boxSets: showsBoxSetEditor = true
                case .settings: showsStorageRootPicker = true
                case .importInbox: showsScanRootPicker = true
                case .playlists: showsPlaylistEditor = true
                default: showsAlbumEditor = true
                }
            }
        }
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
        .task(id: contributor.id) { albums = (try? await library.albums(creditedTo: contributor.id)) ?? [] }
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
        if let payload = candidate.payload { VStack(alignment: .leading) { Text(payload.relativePath); CandidateMetadataSummary(candidate: candidate, fallback: payload.contentTypeIdentifier) } }
        else { Text(candidate.errorMessage ?? "Unreadable item").foregroundStyle(.secondary) }
    }
}

private func proposalSummary(_ proposal: ImportReleaseProposal) -> String {
    let artist = proposal.artist ?? "Unknown artist"
    let confidence = Int((proposal.confidence * 100).rounded())
    return "\(artist) · \(proposal.discCount) disc(s) · \(proposal.trackCount) files · \(confidence)% confidence"
}

private func proposalConfirmationMessage(_ proposal: ImportReleaseProposal) -> String {
    "This will create one album, \(proposal.trackCount) tracks, and root-relative digital asset records. It will not copy, move, or modify any audio files."
}

private func relinkConfirmationMessage(_ proposal: AssetRelinkProposal) -> String {
    "Change the catalogue path from \(proposal.currentPath) to \(proposal.proposedPath). No audio file will be moved or renamed."
}

private struct StorageRootList: View {
    @ObservedObject var library: LibraryStore
    let onShowAlbum: (AlbumID) -> Void
    @State private var rootToRename: StorageRoot?
    @State private var relinkProposalToApply: AssetRelinkProposal?
    @State private var restoreManifestURL: URL?
    @State private var showsSnapshotDestinationPicker = false
    @State private var showsMasterRestorePicker = false

    var body: some View {
        List {
            Section("Snapshot publishing") {
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
            }
            Section("Export") {
                Text("Export a portable JSON view of the current catalogue. Source media files are never copied.").font(.caption).foregroundStyle(.secondary)
                Button("Export Catalogue JSON…", systemImage: "square.and.arrow.up") { exportCatalogue() }
                Button("Export Catalogue CSV…", systemImage: "tablecells") { exportCatalogueCSV() }
            }
            Section("Music Folders") {
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
                ForEach(library.storageRoots) { root in
                    HStack {
                        Image(systemName: symbol(for: root.status)).foregroundStyle(color(for: root.status))
                        VStack(alignment: .leading) {
                            Text(root.displayName).font(.headline)
                            Text(root.lastKnownPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(label(for: root.status)).font(.caption).foregroundStyle(color(for: root.status))
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
            }
            if !library.deletedAlbums.isEmpty {
                Section("Recently Deleted") {
                    ForEach(library.deletedAlbums) { album in
                        HStack {
                            VStack(alignment: .leading) { Text(album.displayTitle); Text("Restore returns this album and its existing catalogue relationships.").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Restore") { Task { do { try await library.restoreAlbum(album.id) } catch { library.presentError(error) } } }
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
            if !library.libraryHealthIssues.isEmpty {
                Section("Library Health") {
                    ForEach(library.libraryHealthIssues) { issue in
                        VStack(alignment: .leading) {
                            Label(issue.albumTitle, systemImage: issue.kind == .offline ? "externaldrive.badge.exclamationmark" : "exclamationmark.triangle")
                            Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                            Button("Show Album") { onShowAlbum(issue.albumID) }
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
            if !library.duplicateAssets.isEmpty { Section("Duplicate fingerprints") { ForEach(library.duplicateAssets) { duplicate in Text("\(duplicate.paths.count) files share fingerprint \(duplicate.contentHash.prefix(12))…") } } }
        }
        .fileImporter(isPresented: $showsSnapshotDestinationPicker, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { try? library.setSnapshotDestination(url) }
        }
        .fileImporter(isPresented: $showsMasterRestorePicker, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result { restoreManifestURL = url }
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
        .overlay {
            if library.isReady && library.storageRoots.isEmpty { ContentUnavailableView("No music folders", systemImage: "externaldrive", description: Text("Add a local or NAS folder. The app saves access permission, not NAS credentials.")) }
        }
        .sheet(item: $rootToRename) { root in StorageRootRenameEditor(library: library, root: root) }
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

    private func save() { Task { try? await library.renameStorageRoot(root.id, to: name); dismiss() } }
}

private struct ScanRootPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore

    var body: some View {
        NavigationStack {
            List(library.storageRoots) { root in
                Button { scan(root) } label: {
                    HStack { VStack(alignment: .leading) { Text(root.displayName); Text(root.lastKnownPath).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Text(root.status.rawValue).font(.caption).foregroundStyle(root.status == .available ? .green : .secondary) }
                }
                .disabled(root.status != .available)
            }
            .navigationTitle("Choose Music Folder")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .frame(width: 520, height: 360)
    }

    private func scan(_ root: StorageRoot) { Task { try? await library.startImportScan(rootID: root.id); dismiss() } }
}

private struct PlaylistEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    @State private var name = ""
    var body: some View { Form { TextField("Playlist name", text: $name) }.padding().frame(width: 360).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Create") { Task { try? await library.addPlaylist(name: name); dismiss() } }.disabled(name.nilIfBlank == nil) } } }
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
        List(items) { item in
            HStack {
                Text("\(item.position). \(item.title)")
                Spacer()
                Button("Move Earlier", systemImage: "arrow.up") { move(item, to: item.position - 1) }
                    .labelStyle(.iconOnly).disabled(item.position == 1)
                Button("Move Later", systemImage: "arrow.down") { move(item, to: item.position + 1) }
                    .labelStyle(.iconOnly).disabled(item.position == items.count)
                Button("Remove", systemImage: "trash", role: .destructive) { remove(item) }
                    .labelStyle(.iconOnly)
            }
        }
        .navigationTitle(playlist.name)
        .toolbar { Button("Play", systemImage: "play.fill") { play() }.disabled(items.isEmpty) }
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
}

private struct ImportBatchDetail: View {
    @ObservedObject var library: LibraryStore
    let batch: ImportBatch
    @State private var candidates: [ImportCandidate] = []
    @State private var proposals: [ImportReleaseProposal] = []
    @State private var proposalToConfirm: ImportReleaseProposal?
    @State private var proposalToLookUp: ImportReleaseProposal?
    @State private var selectionToReview: ExternalMetadataSelection?
    @State private var selections: [UUID: ExternalMetadataSelection] = [:]

    var body: some View {
        List {
            Section("Scan") {
                LabeledContent("Status", value: batch.status.rawValue.capitalized)
                LabeledContent("Files processed", value: String(batch.processedCount))
                LabeledContent("Audio candidates", value: String(batch.candidateCount))
                LabeledContent("Errors", value: String(batch.errorCount))
                if let error = batch.errorSummary { Text(error).foregroundStyle(.secondary) }
                if batch.status == .scanning { Button("Cancel Scan", role: .destructive) { Task { await library.cancelImportScan(batch.id) } } }
                if batch.status != .scanning { Button("Retry Scan", systemImage: "arrow.clockwise") { Task { try? await library.retryImportScan(batch.id) } } }
                if batch.status != .scanning { Button("Read Embedded Metadata", systemImage: "text.magnifyingglass") { Task { try? await library.analyzeImportBatch(batch.id); await load() } } }
            }
            Section("Release Proposals") {
                if proposals.isEmpty { Text("Read embedded metadata to create local proposals. No catalogue records or source files will be changed.").foregroundStyle(.secondary) }
                ForEach(proposals) { proposal in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(proposal.title).font(.headline); Spacer(); Text(proposal.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
                        Text(proposalSummary(proposal)).font(.caption).foregroundStyle(.secondary)
                        Text("Source: \(proposal.provenance). Approval only marks this proposal for later catalogue creation.").font(.caption2).foregroundStyle(.secondary)
                        Button("Search MusicBrainz…", systemImage: "magnifyingglass") { proposalToLookUp = proposal }
                        if let selection = selections[proposal.id] { Button("Review MusicBrainz Fields…", systemImage: "rectangle.and.pencil.and.ellipsis") { selectionToReview = selection } }
                        if proposal.status == .proposed { HStack { Button("Approve for Later") { Task { try? await library.setImportReleaseProposal(proposal.id, status: .approved); await load() } }; Button("Dismiss", role: .destructive) { Task { try? await library.setImportReleaseProposal(proposal.id, status: .dismissed); await load() } } } }
                        if proposal.status == .approved && proposal.createdAlbumID == nil { Button("Create Catalogue Records…", systemImage: "checkmark.seal") { proposalToConfirm = proposal } }
                        if let albumID = proposal.createdAlbumID { Text("Created catalogue album: \(albumID.description)").font(.caption).foregroundStyle(.green) }
                    }
                }
            }
            Section("Candidates") {
                ForEach(candidates) { CandidateRow(candidate: $0) }
            }
        }
        .navigationTitle("Import Batch")
        .task(id: batch.id) { await load() }
        .confirmationDialog("Create catalogue records?", isPresented: Binding(get: { proposalToConfirm != nil }, set: { if !$0 { proposalToConfirm = nil } }), titleVisibility: .visible) {
            if let proposal = proposalToConfirm {
                Button("Create Album, Tracks, and Assets") { Task { _ = try? await library.confirmImportReleaseProposal(proposal.id); await load(); proposalToConfirm = nil } }
            }
        } message: {
            Text(proposalToConfirm.map(proposalConfirmationMessage) ?? "")
        }
        .sheet(item: $proposalToLookUp) { proposal in
            ExternalMetadataLookupView(library: library, proposal: proposal, onSelected: { await load() })
        }
        .sheet(item: $selectionToReview) { selection in ExternalMetadataComparisonView(library: library, selection: selection, proposal: proposals.first(where: { $0.id == selection.importProposalID }), onApplied: { await load() }) }
    }

    private func load() async {
        candidates = (try? await library.importCandidates(batchID: batch.id)) ?? []
        proposals = (try? await library.importReleaseProposals(batchID: batch.id)) ?? []
        var loaded: [UUID: ExternalMetadataSelection] = [:]
        for proposal in proposals { if let selection = try? await library.externalMetadataSelection(for: proposal.id) { loaded[proposal.id] = selection } }
        selections = loaded
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

    init(library: LibraryStore, proposal: ImportReleaseProposal, onSelected: @escaping () async -> Void) {
        self.library = library
        self.proposal = proposal
        self.onSelected = onSelected
        _title = State(initialValue: proposal.title)
        _artist = State(initialValue: proposal.artist ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    TextField("Album title", text: $title)
                    TextField("Artist (optional)", text: $artist)
                    Text("Search sends only the text entered here to MusicBrainz. It does not upload audio, modify files, or change the catalogue.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Search MusicBrainz") { search() }.disabled(isSearching || title.nilIfBlank == nil)
                }
                Section("Preview results") {
                    if isSearching { ProgressView("Searching MusicBrainz…") }
                    else if hasSearched && results.isEmpty { Text("No matching releases found.").foregroundStyle(.secondary) }
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.title).font(.headline)
                            Text([result.artist, result.releaseDate, result.countryCode, result.catalogueNumber].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            if result.mediaCount > 0 { Text("\(result.mediaCount) disc(s)").font(.caption).foregroundStyle(.secondary) }
                            Text("Preview only — no catalogue change has been made.").font(.caption2).foregroundStyle(.secondary)
                            Button("Use for Field Comparison") { save(result) }
                        }
                    }
                }
            }
            .navigationTitle("MusicBrainz Lookup")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .alert("Search failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
        .frame(width: 560, height: 520)
    }

    private func search() {
        isSearching = true
        hasSearched = true
        results = []
        Task {
            do { results = try await library.searchMusicBrainz(title: title, artist: artist.nilIfBlank) }
            catch { errorMessage = error.localizedDescription }
            isSearching = false
        }
    }
    private func save(_ result: ExternalReleasePreview) {
        Task {
            do { try await library.saveMusicBrainzSelection(result, for: proposal.id); await onSelected(); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
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
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("MusicBrainz field comparison") {
                comparison("Album title", current: proposal?.title, proposed: selection.title, enabled: $useTitle)
                comparison("Artist", current: proposal?.artist, proposed: selection.artist, enabled: $useArtist)
                comparison("Disc count", current: proposal.map { String($0.discCount) }, proposed: String(selection.discCount), enabled: $useDiscCount)
                comparison("Country/region", current: proposal?.countryCode, proposed: selection.countryCode, enabled: $useCountryCode)
                comparison("Catalogue number", current: proposal?.catalogueNumber, proposed: selection.catalogueNumber, enabled: $useCatalogueNumber)
                Text("Only checked fields update this import proposal. This does not yet create or edit a catalogue album, and never changes audio tags.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding().frame(width: 520)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Apply Selected Fields") { apply() } } }
        .alert("Unable to apply fields", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }
    private func comparison(_ name: String, current: String?, proposed: String?, enabled: Binding<Bool>) -> some View {
        Toggle(isOn: enabled) { VStack(alignment: .leading) { Text(name); Text("Current: \(current ?? "—") → MusicBrainz: \(proposed ?? "—")").font(.caption).foregroundStyle(.secondary) } }
    }
    private func apply() { Task { do { try await library.applyExternalMetadataSelection(selection, fields: .init(title: useTitle, artist: useArtist, discCount: useDiscCount, countryCode: useCountryCode, catalogueNumber: useCatalogueNumber)); await onApplied(); dismiss() } catch { errorMessage = error.localizedDescription } } }
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
    @State private var trackPendingDeletion: Track?
    @State private var contributorToEdit: Contributor?
    @State private var albumCreditToEdit: ContributorCredit?
    @State private var trackCreditToEdit: TrackCreditSelection?
    @State private var showsArtworkPicker = false
    @State private var discPendingDeletion: Disc?

    var body: some View {
        Form {
            Section("Album") {
                LabeledContent("Title", value: album.title)
                if let edition = album.editionLabel, !edition.isEmpty { LabeledContent("Edition", value: edition) }
                if let year = album.releaseYear { LabeledContent("Release year", value: String(year)) }
                if let country = album.countryCode { LabeledContent("Country", value: country) }
                if let catalogueNumber = album.catalogueNumber { LabeledContent("Catalogue no.", value: catalogueNumber) }
                if let labelName = album.labelName { LabeledContent("Label", value: labelName) }
                LabeledContent("Discs", value: String(album.discCount))
                if let rating = album.rating { LabeledContent("Rating", value: "\(rating) / 5") }
                if album.isFavourite { Label("Favourite", systemImage: "heart.fill").foregroundStyle(.pink) }
            }
            Section("Availability") {
                AvailabilityBadge(title: "CD", isAvailable: album.hasCD)
                AvailabilityBadge(title: "Digital", isAvailable: false)
            }
            if album.hasCD {
                Section("Physical") {
                    LabeledContent("Location", value: locationName)
                }
            }
            if !discs.isEmpty {
                Section("Tracks") {
                    ForEach(discs) { disc in
                        HStack {
                            Text(disc.title ?? "Disc \(disc.number)").font(.headline)
                            Spacer()
                            Button("Move disc earlier", systemImage: "arrow.up") { Task { do { try await library.reorderDisc(disc.id, in: album.id, to: disc.number - 1); await loadContent() } catch { library.presentError(error) } } }
                                .labelStyle(.iconOnly).disabled(disc.number <= 1)
                            Button("Move disc later", systemImage: "arrow.down") { Task { do { try await library.reorderDisc(disc.id, in: album.id, to: disc.number + 1); await loadContent() } catch { library.presentError(error) } } }
                                .labelStyle(.iconOnly).disabled(disc.number >= discs.count)
                            Button("Remove disc", systemImage: "trash", role: .destructive) { discPendingDeletion = disc }
                                .labelStyle(.iconOnly)
                        }
                        ForEach(tracksByDisc[disc.id] ?? []) { track in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text("\(track.number). \(track.title)")
                                    if let rating = track.rating { Text("\(rating)★").font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    Button("Edit", systemImage: "pencil") { trackToEdit = track }.labelStyle(.iconOnly)
                                    Button("Play", systemImage: "play.fill") { play(track) }.labelStyle(.iconOnly)
                                    Menu("Add to Playlist") { ForEach(library.playlists) { playlist in Button(playlist.name) { Task { do { try await library.addTrack(track.id, toPlaylist: playlist.id) } catch { library.presentError(error) } } } } }.labelStyle(.iconOnly)
                                    Button("Credit", systemImage: "person.badge.plus") { trackForContributor = track }
                                        .labelStyle(.iconOnly)
                                    Button("Remove", systemImage: "trash", role: .destructive) { trackPendingDeletion = track }
                                        .labelStyle(.iconOnly)
                                }
                                if let credits = trackCredits[track.id], !credits.isEmpty {
                                    ForEach(credits) { credit in
                                        HStack {
                                            Text("\(credit.creditedName ?? credit.contributor.name) — \(credit.role.rawValue)")
                                                .font(.caption).foregroundStyle(.secondary)
                                            Spacer()
                                            Button("Edit credited name", systemImage: "pencil") { trackCreditToEdit = .init(track: track, credit: credit) }
                                                .labelStyle(.iconOnly)
                                            Button("Remove credit", systemImage: "trash", role: .destructive) { Task { do { try await library.deleteTrackContributor(credit, from: track.id); await loadContent() } catch { library.presentError(error) } } }
                                                .labelStyle(.iconOnly)
                                        }
                                    }
                                }
                            }
                        }
                        Button("Add Track", systemImage: "plus") { discForTrack = disc }
                    }
                }
            } else {
                Section("Tracks") { Button("Add Disc", systemImage: "plus") { showsAddDisc = true } }
            }
            Section("Contributors") {
                ForEach(credits) { credit in
                    HStack {
                        Text("\(credit.creditedName ?? credit.contributor.name) — \(credit.role.rawValue)")
                        Spacer()
                        Button("Edit name", systemImage: "pencil") { contributorToEdit = credit.contributor }.labelStyle(.iconOnly)
                        Button("Edit credited name", systemImage: "text.cursor") { albumCreditToEdit = credit }.labelStyle(.iconOnly)
                        Button("Remove credit", systemImage: "trash", role: .destructive) { Task { do { try await library.deleteAlbumContributor(credit, from: album.id); await loadContent() } catch { library.presentError(error) } } }.labelStyle(.iconOnly)
                    }
                }
                Button("Add Contributor", systemImage: "plus") { showsAddContributor = true }
            }
            Section("Aliases") {
                ForEach(aliases) { alias in
                    HStack { Text("\(alias.name) (\(alias.kind.rawValue))"); Spacer(); Button("Remove", systemImage: "trash", role: .destructive) { Task { do { try await library.deleteAlbumAlias(alias.id); await loadContent() } catch { library.presentError(error) } } }.labelStyle(.iconOnly) }
                }
                Button("Add Alias", systemImage: "plus") { showsAddAlias = true }
            }
            Section("Artwork") {
                if artwork.isEmpty { Text("No artwork selected").foregroundStyle(.secondary) }
                ForEach(artwork) { image in Text("\(image.isSelected ? "Selected " : "")\(image.role.rawValue): \(image.localPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No local file")") }
                Button("Choose Artwork…", systemImage: "photo.badge.plus") { showsArtworkPicker = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(album.displayTitle)
        .toolbar { Button("Edit", action: onEdit); Button("Add Disc", systemImage: "plus") { showsAddDisc = true } }
        .task(id: album.id) {
            placement = try? await library.boxPlacement(for: album.id)
            await loadContent()
        }
        .sheet(isPresented: $showsAddDisc) { AddDiscEditor(library: library, albumID: album.id, onAdded: { await loadContent() }) }
        .sheet(item: $discForTrack) { disc in AddTrackEditor(library: library, disc: disc, onAdded: { await loadContent() }) }
        .sheet(isPresented: $showsAddAlias) { AddAliasEditor(library: library, albumID: album.id, onAdded: { await loadContent() }) }
        .sheet(isPresented: $showsAddContributor) { AddContributorEditor(library: library, albumID: album.id, onAdded: { await loadContent() }) }
        .sheet(item: $trackForContributor) { track in AddTrackContributorEditor(library: library, track: track, onAdded: { await loadContent() }) }
        .sheet(item: $trackToEdit) { track in EditTrackEditor(library: library, track: track, onSaved: { await loadContent() }) }
        .sheet(item: $contributorToEdit) { contributor in EditContributorEditor(library: library, contributor: contributor, onSaved: { await loadContent() }) }
        .sheet(item: $albumCreditToEdit) { credit in EditAlbumCreditedNameEditor(library: library, albumID: album.id, credit: credit, onSaved: { await loadContent() }) }
        .sheet(item: $trackCreditToEdit) { selection in EditTrackCreditedNameEditor(library: library, track: selection.track, credit: selection.credit, onSaved: { await loadContent() }) }
        .confirmationDialog("Remove this disc?", isPresented: Binding(get: { discPendingDeletion != nil }, set: { if !$0 { discPendingDeletion = nil } }), titleVisibility: .visible, presenting: discPendingDeletion) { disc in
            Button("Remove Disc and Its Tracks", role: .destructive) { Task { do { try await library.deleteDisc(disc.id); await loadContent(); discPendingDeletion = nil } catch { library.presentError(error) } } }
        } message: { disc in
            Text("This removes Disc \(disc.number) and its catalogue tracks. Source audio files are not changed. A disc with protected digital assets cannot be removed.")
        }
        .confirmationDialog("Remove this track?", isPresented: Binding(get: { trackPendingDeletion != nil }, set: { if !$0 { trackPendingDeletion = nil } }), titleVisibility: .visible, presenting: trackPendingDeletion) { track in
            Button("Remove Track", role: .destructive) { Task { do { try await library.deleteTrack(track.id); await loadContent(); trackPendingDeletion = nil } catch { library.presentError(error) } } }
        } message: { track in
            Text("This removes \(track.title) from the catalogue. Source audio files are not changed. A track with protected digital assets cannot be removed.")
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
        return locations.first(where: { $0.id == id })?.name ?? "Unknown location"
    }

    private func loadContent() async {
        guard let loadedDiscs = try? await library.discs(albumID: album.id) else { return }
        discs = loadedDiscs
        var mapped: [DiscID: [Track]] = [:]
        var loadedTrackCredits: [TrackID: [ContributorCredit]] = [:]
        for disc in loadedDiscs {
            let tracks = (try? await library.tracks(discID: disc.id)) ?? []
            mapped[disc.id] = tracks
            for track in tracks { loadedTrackCredits[track.id] = (try? await library.trackContributors(trackID: track.id)) ?? [] }
        }
        tracksByDisc = mapped
        trackCredits = loadedTrackCredits
        credits = (try? await library.albumContributors(albumID: album.id)) ?? []
        aliases = (try? await library.albumAliases(albumID: album.id)) ?? []
        artwork = (try? await library.albumArtwork(albumID: album.id)) ?? []
    }

    private func play(_ track: Track) {
        Task {
            if let items = try? await library.playbackURLs(discID: track.discID), let index = items.firstIndex(where: { $0.trackID == track.id }) { try? playback.play(items: items, startingAt: index) }
        }
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
        Form { TextField("Alias", text: $name); Picker("Kind", selection: $kind) { ForEach(AlbumAliasKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; TextField("Locale (optional)", text: $locale) }
            .padding().frame(width: 380)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { add() }.disabled(name.nilIfBlank == nil) } }
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

private struct LocationList: View {
    @ObservedObject var library: LibraryStore
    @State private var locationToRename: PhysicalLocation?

    var body: some View {
        List(library.locations) { location in
            Text(location.name)
                .contextMenu {
                    Button("Rename") { locationToRename = location }
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
    }
}

private struct AlbumEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    @State private var title = ""
    @State private var editionLabel = ""
    @State private var releaseYear = ""
    @State private var countryCode = ""
    @State private var catalogueNumber = ""
    @State private var discCount = 1
    @State private var hasCD = false
    @State private var rating = 0
    @State private var isFavourite = false
    @State private var selectedLocationID: PhysicalLocationID?
    @State private var selectedBoxSetID: BoxSetID?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Album") {
                TextField("Title", text: $title)
                TextField("Edition label", text: $editionLabel, prompt: Text("Japan version, 2011 remaster…"))
                TextField("Release year", text: $releaseYear)
                TextField("Country/region", text: $countryCode)
                TextField("Catalogue number", text: $catalogueNumber)
                Stepper("Discs: \(discCount)", value: $discCount, in: 1...99)
                Picker("Rating", selection: $rating) { Text("Not rated").tag(0); ForEach(1...5, id: \.self) { Text("\($0) star\($0 == 1 ? "" : "s")").tag($0) } }
                Toggle("Favourite", isOn: $isFavourite)
            }
            Section("Physical CD") {
                Toggle("CD is available", isOn: $hasCD)
                if hasCD {
                    Picker("Box set", selection: $selectedBoxSetID) {
                        Text("Not in a box set").tag(BoxSetID?.none)
                        ForEach(library.boxSets) { box in Text(box.title).tag(Optional(box.id)) }
                    }
                    if selectedBoxSetID == nil {
                        Picker("Location", selection: $selectedLocationID) {
                            Text("Location unknown").tag(PhysicalLocationID?.none)
                            ForEach(library.locations) { location in Text(location.name).tag(Optional(location.id)) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .navigationTitle("Add Album")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Add") { addAlbum() }.keyboardShortcut(.defaultAction) }
        }
        .alert("Unable to add album", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onChange(of: selectedBoxSetID) { _, boxID in if boxID != nil { hasCD = true; selectedLocationID = nil } }
    }

    private func addAlbum() {
        Task {
            do {
                let draft = NewAlbum(
                    title: title,
                    editionLabel: editionLabel.nilIfBlank,
                    releaseYear: Int(releaseYear),
                    countryCode: countryCode.nilIfBlank,
                    catalogueNumber: catalogueNumber.nilIfBlank,
                    discCount: discCount,
                    hasCD: hasCD,
                    physicalLocationID: selectedBoxSetID == nil ? selectedLocationID : nil,
                    rating: rating == 0 ? nil : rating,
                    isFavourite: isFavourite
                )
                try await library.addAlbum(draft, toBoxSet: selectedBoxSetID)
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
                ForEach(library.locations) { location in Text(location.name).tag(Optional(location.id)) }
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
            do { try await library.addLocation(.init(name: name, parentID: parentID)); dismiss() }
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
                ForEach(library.locations) { location in Text(location.name).tag(Optional(location.id)) }
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
    @State private var catalogueNumber: String
    @State private var discCount: Int
    @State private var hasCD: Bool
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
        _catalogueNumber = State(initialValue: album.catalogueNumber ?? "")
        _discCount = State(initialValue: album.discCount)
        _hasCD = State(initialValue: album.hasCD)
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
                TextField("Catalogue number", text: $catalogueNumber)
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
                            ForEach(library.locations) { location in Text(location.name).tag(Optional(location.id)) }
                        }
                        Toggle("Physical location is unknown", isOn: $locationUnknown)
                            .onChange(of: locationUnknown) { _, unknown in if unknown { locationID = nil } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .task { placement = try? await library.boxPlacement(for: album.id) }
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
                draft.catalogueNumber = catalogueNumber.nilIfBlank
                draft.discCount = discCount
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
                ForEach(library.locations) { location in Text(location.name).tag(Optional(location.id)) }
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
