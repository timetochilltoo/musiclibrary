import SwiftUI
import MusicReadOnlyClient

public struct PadLibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshotStatus = "No verified snapshot loaded"
    @State private var updateAvailable = false
    @State private var catalogue: ReadOnlyCatalogue?
    @StateObject private var playback = CompanionPlaybackController()
    @State private var searchText = ""
    @State private var mappings: [SMBRootMapping] = []
    @State private var sourceDirectory: URL?
    @State private var favouriteAlbumIDs: Set<String> = []
    @State private var recentlyPlayedAlbumIDs: [String] = []
    @State private var showsFavouritesOnly = false
    @State private var isSelectingSnapshotSource = false
    @State private var isSelectingSMBRoot = false
    @State private var rootID = ""
    @State private var message: String?
    private let client: SnapshotClient
    private let mappingStore: SMBRootMappingStore
    private let sourceStore: SnapshotSourceStore
    private let preferenceStore: CompanionPreferenceStore
    private let snapshotDirectory: URL

    public init(snapshotDirectory: URL, mappingStoreURL: URL, sourceStoreURL: URL? = nil, preferenceStoreURL: URL? = nil) {
        self.snapshotDirectory = snapshotDirectory
        client = SnapshotClient(cacheDirectory: snapshotDirectory)
        mappingStore = SMBRootMappingStore(url: mappingStoreURL)
        sourceStore = SnapshotSourceStore(url: sourceStoreURL ?? mappingStoreURL.deletingLastPathComponent().appending(path: "snapshot-source.bookmark"))
        preferenceStore = CompanionPreferenceStore(url: preferenceStoreURL ?? mappingStoreURL.deletingLastPathComponent().appending(path: "companion-preferences.json"))
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Catalogue") {
                    Text(snapshotStatus)
                    Text("Read-only companion").foregroundStyle(.secondary)
                    if let sourceDirectory {
                        Text(sourceDirectory.path).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Choose the published snapshot folder to refresh.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Choose snapshot source") { isSelectingSnapshotSource = true }
                    Button("Refresh snapshot") { refreshSnapshot() }.disabled(sourceDirectory == nil)
                    if updateAvailable { Text("A newer published snapshot is available.").font(.caption).foregroundStyle(.orange) }
                }
                Section("Albums") {
                    if let catalogue {
                        Text("Revision \(catalogue.catalogueRevision) · \(catalogue.albums.count) albums").font(.caption).foregroundStyle(.secondary)
                        if !recentlyPlayedAlbums.isEmpty {
                            HStack {
                                Text("Recently played").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear") { clearRecentlyPlayed() }.font(.caption)
                            }
                            ForEach(recentlyPlayedAlbums) { album in
                                albumLink(album)
                            }
                            Divider()
                        }
                        if filteredAlbums.isEmpty {
                            Text("No albums match your search.").foregroundStyle(.secondary)
                        }
                        ForEach(filteredAlbums) { album in
                            albumLink(album)
                        }
                    } else {
                        Text("Refresh a verified snapshot to browse albums.").foregroundStyle(.secondary)
                    }
                }
                Section("SMB music roots") {
                    if mappings.isEmpty { Text("No device-local SMB mappings").foregroundStyle(.secondary) }
                    ForEach(mappings, id: \.publishedRootID) { mapping in
                        VStack(alignment: .leading) {
                            Text(mapping.publishedRootID)
                            Text(mapping.localURL.path).font(.caption).foregroundStyle(.secondary)
                        }
                    }.onDelete(perform: removeMappings)
                    TextField("Published root ID", text: $rootID)
                    Button("Choose SMB root") { isSelectingSMBRoot = true }.disabled(rootID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Music Library")
            .searchable(text: $searchText, prompt: "Search title, edition, catalogue number")
            .toolbar { Toggle("Favourites only", isOn: $showsFavouritesOnly) }
            .task { loadState() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { checkForNewerSource() }
            }
            .fileImporter(isPresented: $isSelectingSnapshotSource, allowedContentTypes: [.folder]) { result in
                selectSnapshotSource(result)
            }
            .fileImporter(isPresented: $isSelectingSMBRoot, allowedContentTypes: [.folder]) { result in
                selectSMBRoot(result)
            }
            .alert("Music Library", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
            .alert("Playback", isPresented: Binding(get: { playback.errorMessage != nil }, set: { if !$0 { playback.dismissError() } })) {
                Button("OK", role: .cancel) { playback.dismissError() }
            } message: { Text(playback.errorMessage ?? "") }
        }
    }

    private func loadState() {
        mappings = (try? mappingStore.mappings()) ?? []
        sourceDirectory = try? sourceStore.selectedDirectory()
        do { favouriteAlbumIDs = try preferenceStore.favouriteAlbumIDs() }
        catch { message = "Could not load device-local favourites: \(error.localizedDescription)" }
        do { recentlyPlayedAlbumIDs = try preferenceStore.recentlyPlayedAlbumIDs() }
        catch { message = "Could not load device-local play history: \(error.localizedDescription)" }
        do {
            catalogue = try client.localCatalogue()
            snapshotStatus = catalogue == nil ? "No verified snapshot loaded" : "Verified local snapshot available"
            checkForNewerSource()
        } catch {
            catalogue = nil
            snapshotStatus = "Verified cache could not be opened"
            message = "The local snapshot is not usable: \(error.localizedDescription)"
        }
    }

    private func selectSnapshotSource(_ result: Result<URL, Error>) {
        do {
            let directory = try result.get()
            try sourceStore.set(selectedDirectory: directory)
            sourceDirectory = directory
            checkForNewerSource()
            message = "Snapshot source saved. Refresh when ready."
        } catch { message = "Could not save snapshot source: \(error.localizedDescription)" }
    }

    private func selectSMBRoot(_ result: Result<URL, Error>) {
        do {
            let directory = try result.get()
            try mappingStore.set(publishedRootID: rootID.trimmingCharacters(in: .whitespacesAndNewlines), selectedDirectory: directory)
            rootID = ""
            mappings = try mappingStore.mappings()
        } catch { message = "Could not save SMB root: \(error.localizedDescription)" }
    }

    private func refreshSnapshot() {
        guard let sourceDirectory else { return }
        let gainedAccess = sourceDirectory.startAccessingSecurityScopedResource()
        defer { if gainedAccess { sourceDirectory.stopAccessingSecurityScopedResource() } }
        do {
            message = try client.update(from: sourceDirectory) ? "Snapshot updated." : "Already using the latest verified snapshot."
            updateAvailable = false
            loadState()
        } catch { message = "Snapshot refresh failed; the prior verified cache remains in use. \(error.localizedDescription)" }
    }

    private func removeMappings(at offsets: IndexSet) {
        do {
            for offset in offsets { try mappingStore.remove(publishedRootID: mappings[offset].publishedRootID) }
            mappings = try mappingStore.mappings()
        } catch { message = "Could not remove SMB root: \(error.localizedDescription)" }
    }

    private func checkForNewerSource() {
        guard let sourceDirectory else { updateAvailable = false; return }
        let gainedAccess = sourceDirectory.startAccessingSecurityScopedResource()
        defer { if gainedAccess { sourceDirectory.stopAccessingSecurityScopedResource() } }
        updateAvailable = (try? client.sourceManifestIsNewer(from: sourceDirectory)) ?? false
    }

    private var filteredAlbums: [ReadOnlyAlbum] {
        guard let catalogue else { return [] }
        return catalogue.albums.filter { $0.matches(searchText) && (!showsFavouritesOnly || favouriteAlbumIDs.contains($0.id)) }
    }

    private var recentlyPlayedAlbums: [ReadOnlyAlbum] {
        guard let catalogue else { return [] }
        let albumsByID = Dictionary(uniqueKeysWithValues: catalogue.albums.map { ($0.id, $0) })
        return recentlyPlayedAlbumIDs.compactMap { albumsByID[$0] }.filter { $0.matches(searchText) && (!showsFavouritesOnly || favouriteAlbumIDs.contains($0.id)) }
    }

    @ViewBuilder private func albumLink(_ album: ReadOnlyAlbum) -> some View {
        NavigationLink {
            PadAlbumDetailView(
                album: album,
                mappings: mappings,
                playback: playback,
                isFavourite: favouriteAlbumIDs.contains(album.id),
                onSetFavourite: { setFavourite($0, for: album.id) },
                onPlayed: { recordPlayed(albumID: album.id) }
            )
        } label: {
            PadAlbumRow(album: album, isFavourite: favouriteAlbumIDs.contains(album.id))
        }
    }

    private func setFavourite(_ isFavourite: Bool, for albumID: String) {
        do {
            try preferenceStore.setFavourite(isFavourite, albumID: albumID)
            if isFavourite { favouriteAlbumIDs.insert(albumID) }
            else { favouriteAlbumIDs.remove(albumID) }
        } catch {
            message = "Could not save device-local favourite: \(error.localizedDescription)"
        }
    }

    private func recordPlayed(albumID: String) {
        do {
            try preferenceStore.recordPlayed(albumID: albumID)
            recentlyPlayedAlbumIDs.removeAll { $0 == albumID }
            recentlyPlayedAlbumIDs.insert(albumID, at: 0)
        } catch {
            message = "Could not save device-local play history: \(error.localizedDescription)"
        }
    }

    private func clearRecentlyPlayed() {
        do {
            try preferenceStore.clearRecentlyPlayed()
            recentlyPlayedAlbumIDs = []
        } catch {
            message = "Could not clear device-local play history: \(error.localizedDescription)"
        }
    }
}

public struct PadAlbumRow: View {
    public let album: ReadOnlyAlbum
    public let isFavourite: Bool

    public init(album: ReadOnlyAlbum, isFavourite: Bool = false) { self.album = album; self.isFavourite = isFavourite }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(album.displayTitle)
                if isFavourite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
            }
            HStack(spacing: 6) {
                if let releaseYear = album.releaseYear { Text(String(releaseYear)) }
                if let rating = album.rating { Text("\(rating)★") }
                if album.hasCD { Text("CD") }
                if album.hasDigital { Text("Digital") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

public struct PadAlbumDetailView: View {
    public let album: ReadOnlyAlbum
    public let mappings: [SMBRootMapping]
    @ObservedObject public var playback: CompanionPlaybackController
    public let isFavourite: Bool
    public let onSetFavourite: (Bool) -> Void
    public let onPlayed: () -> Void

    public init(album: ReadOnlyAlbum, mappings: [SMBRootMapping] = [], playback: CompanionPlaybackController, isFavourite: Bool = false, onSetFavourite: @escaping (Bool) -> Void = { _ in }, onPlayed: @escaping () -> Void = {}) {
        self.album = album
        self.mappings = mappings
        self.playback = playback
        self.isFavourite = isFavourite
        self.onSetFavourite = onSetFavourite
        self.onPlayed = onPlayed
    }

    public var body: some View {
        List {
            Section("Edition") {
                LabeledContent("Title", value: album.title)
                if let editionLabel = album.editionLabel { LabeledContent("Edition", value: editionLabel) }
                if let releaseYear = album.releaseYear { LabeledContent("Release year", value: String(releaseYear)) }
                if let catalogueNumber = album.catalogueNumber { LabeledContent("Catalogue number", value: catalogueNumber) }
                if let rating = album.rating { LabeledContent("Rating", value: "\(rating) / 5") }
            }
            Section("Availability") {
                LabeledContent("CD", value: album.hasCD ? "Available" : "Not catalogued")
                LabeledContent("Digital", value: album.hasDigital ? "Available" : "Not catalogued")
            }
            if !album.discs.isEmpty {
                ForEach(album.discs) { disc in
                    Section(disc.title ?? "Disc \(disc.number)") {
                        ForEach(disc.tracks) { track in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(track.number). \(track.title)")
                                    if let rating = track.rating { Text("\(rating)★").font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    Button(playbackLabel(for: track)) {
                                        playOrPause(track)
                                    }
                                    .disabled(track.playableURL(using: mappings) == nil)
                                }
                                Text(assetStatus(for: track))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(album.displayTitle)
        .toolbar {
            Button(isFavourite ? "Remove Favourite" : "Add Favourite", systemImage: isFavourite ? "star.fill" : "star") {
                onSetFavourite(!isFavourite)
            }
        }
    }

    private func assetStatus(for track: ReadOnlyTrack) -> String {
        guard let asset = track.assets.first else { return "No digital file catalogued" }
        return switch asset.resolve(using: mappings) {
        case .mapped: "SMB root mapped"
        case .unmappedRoot: "SMB root is not mapped on this device"
        case .unavailable(let state): "Digital file unavailable (\(state))"
        case .unsafeRelativePath: "Unsafe published path refused"
        }
    }

    private func playbackLabel(for track: ReadOnlyTrack) -> String {
        playback.currentTrackID == track.id && playback.isPlaying ? "Pause" : "Play"
    }

    private func playOrPause(_ track: ReadOnlyTrack) {
        if playback.currentTrackID == track.id { playback.togglePause() }
        else {
            playback.play(track, mappings: mappings)
            onPlayed()
        }
    }
}
