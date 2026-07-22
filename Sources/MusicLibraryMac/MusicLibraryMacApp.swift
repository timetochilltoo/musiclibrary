import SwiftUI
import UniformTypeIdentifiers
import MusicApplication
import MusicDomain
import MusicUIComponents

@main
struct MusicLibraryMacApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup("Music Library") {
            LibraryShellView(library: library)
                .frame(minWidth: 980, minHeight: 640)
                .task { await library.start() }
        }
    }
}

private struct LibraryShellView: View {
    private enum Section: Hashable, CaseIterable, Identifiable {
        case albums, locations, boxSets, importInbox, playlists, settings
        var id: Self { self }
        var title: String {
            switch self {
            case .albums: "Albums"
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
            case .locations: "archivebox"
            case .boxSets: "shippingbox"
            case .importInbox: "tray"
            case .playlists: "music.note.list"
            case .settings: "gearshape"
            }
        }
    }

    @ObservedObject var library: LibraryStore
    @State private var section: Section? = .albums
    @State private var selectedAlbumID: AlbumID?
    @State private var selectedBoxSetID: BoxSetID?
    @State private var searchText = ""
    @State private var showsAlbumEditor = false
    @State private var showsLocationEditor = false
    @State private var showsBoxSetEditor = false
    @State private var albumToEdit: Album?

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
        .sheet(item: $albumToEdit) { album in EditAlbumEditor(library: library, album: album) }
        .alert("Music Library", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.dismissError() } }
        )) {
            Button("OK", role: .cancel) { library.dismissError() }
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .albums:
            List(library.albums, selection: $selectedAlbumID) { album in
                AlbumRow(album: album).tag(album.id)
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
        case .boxSets:
            List(library.boxSets, selection: $selectedBoxSetID) { box in
                VStack(alignment: .leading) {
                    Text(box.title).font(.headline)
                    if let edition = box.editionLabel, !edition.isEmpty { Text(edition).foregroundStyle(.secondary) }
                }.tag(box.id)
            }
            .overlay {
                if library.isReady && library.boxSets.isEmpty {
                    ContentUnavailableView("No box sets", systemImage: "shippingbox", description: Text("Create a box set to group its member albums at one location."))
                }
            }
        default:
            ContentUnavailableView(section?.title ?? "Music Library", systemImage: section?.symbol ?? "music.note")
        }
    }

    @ViewBuilder private var detail: some View {
        if section == .boxSets, let selectedBoxSetID, let box = library.boxSets.first(where: { $0.id == selectedBoxSetID }) {
            BoxSetDetail(library: library, boxSet: box)
        } else if let selectedAlbumID, let album = library.albums.first(where: { $0.id == selectedAlbumID }) {
            AlbumDetail(library: library, album: album, locations: library.locations, onEdit: { albumToEdit = album })
        } else {
            ContentUnavailableView("Select an album", systemImage: "opticaldisc", description: Text("Album details will appear here."))
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(section == .locations ? "Add Location" : section == .boxSets ? "Add Box Set" : "Add Album", systemImage: "plus") {
                switch section {
                case .locations: showsLocationEditor = true
                case .boxSets: showsBoxSetEditor = true
                default: showsAlbumEditor = true
                }
            }
        }
    }
}

private struct AlbumDetail: View {
    @ObservedObject var library: LibraryStore
    let album: Album
    let locations: [PhysicalLocation]
    let onEdit: () -> Void
    @State private var placement: AlbumBoxPlacement?
    @State private var discs: [Disc] = []
    @State private var tracksByDisc: [DiscID: [Track]] = [:]
    @State private var credits: [ContributorCredit] = []
    @State private var aliases: [AlbumAlias] = []
    @State private var artwork: [Artwork] = []
    @State private var showsAddDisc = false
    @State private var discForTrack: Disc?
    @State private var showsAddAlias = false
    @State private var showsAddContributor = false
    @State private var trackForContributor: Track?
    @State private var showsArtworkPicker = false

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
                        Text(disc.title ?? "Disc \(disc.number)").font(.headline)
                        ForEach(tracksByDisc[disc.id] ?? []) { track in
                            HStack {
                                Text("\(track.number). \(track.title)")
                                Spacer()
                                Button("Credit", systemImage: "person.badge.plus") { trackForContributor = track }
                                    .labelStyle(.iconOnly)
                                Button("Remove", systemImage: "trash", role: .destructive) { Task { try? await library.deleteTrack(track.id); await loadContent() } }
                                    .labelStyle(.iconOnly)
                            }
                        }
                        Button("Add Track", systemImage: "plus") { discForTrack = disc }
                    }
                }
            } else {
                Section("Tracks") { Button("Add Disc", systemImage: "plus") { showsAddDisc = true } }
            }
            Section("Contributors") {
                ForEach(credits) { Text("\($0.contributor.name) — \($0.role.rawValue)") }
                Button("Add Contributor", systemImage: "plus") { showsAddContributor = true }
            }
            Section("Aliases") {
                ForEach(aliases) { alias in
                    HStack { Text("\(alias.name) (\(alias.kind.rawValue))"); Spacer(); Button("Remove", systemImage: "trash", role: .destructive) { Task { try? await library.deleteAlbumAlias(alias.id); await loadContent() } }.labelStyle(.iconOnly) }
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
        .fileImporter(isPresented: $showsArtworkPicker, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result { Task { try? await library.addAlbumArtwork(albumID: album.id, localPath: url.path, role: .front); await loadContent() } }
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
        for disc in loadedDiscs { mapped[disc.id] = (try? await library.tracks(discID: disc.id)) ?? [] }
        tracksByDisc = mapped
        credits = (try? await library.albumContributors(albumID: album.id)) ?? []
        aliases = (try? await library.albumAliases(albumID: album.id)) ?? []
        artwork = (try? await library.albumArtwork(albumID: album.id)) ?? []
    }
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
    private func add() { Task { try? await library.addDisc(albumID: albumID, title: title.nilIfBlank); await onAdded(); dismiss() } }
}

private struct AddTrackEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let disc: Disc
    let onAdded: () async -> Void
    @State private var title = ""
    var body: some View {
        Form { TextField("Track title", text: $title) }
            .padding().frame(width: 360)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { add() }.disabled(title.nilIfBlank == nil) } }
    }
    private func add() { Task { try? await library.addTrack(discID: disc.id, draft: .init(title: title)); await onAdded(); dismiss() } }
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
    private func add() { Task { try? await library.addAlbumAlias(albumID: albumID, name: name, kind: kind, locale: locale.nilIfBlank); await onAdded(); dismiss() } }
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
    private func add() { Task { try? await library.addAlbumContributor(albumID: albumID, name: name, role: role, creditedName: creditedName.nilIfBlank); await onAdded(); dismiss() } }
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
    private func add() { Task { try? await library.addTrackContributor(trackID: track.id, name: name, role: role, creditedName: creditedName.nilIfBlank); await onAdded(); dismiss() } }
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
                    physicalLocationID: selectedBoxSetID == nil ? selectedLocationID : nil
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
