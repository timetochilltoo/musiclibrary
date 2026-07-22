import SwiftUI
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
    @State private var searchText = ""
    @State private var showsAlbumEditor = false
    @State private var showsLocationEditor = false
    @State private var showsBoxSetEditor = false

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
            List(library.boxSets) { box in
                VStack(alignment: .leading) {
                    Text(box.title).font(.headline)
                    if let edition = box.editionLabel, !edition.isEmpty { Text(edition).foregroundStyle(.secondary) }
                }
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
        if let selectedAlbumID, let album = library.albums.first(where: { $0.id == selectedAlbumID }) {
            AlbumDetail(album: album, locations: library.locations)
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
    let album: Album
    let locations: [PhysicalLocation]

    var body: some View {
        Form {
            Section("Album") {
                LabeledContent("Title", value: album.title)
                if let edition = album.editionLabel, !edition.isEmpty { LabeledContent("Edition", value: edition) }
                if let year = album.releaseYear { LabeledContent("Release year", value: String(year)) }
                if let country = album.countryCode { LabeledContent("Country", value: country) }
                if let catalogueNumber = album.catalogueNumber { LabeledContent("Catalogue no.", value: catalogueNumber) }
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
        }
        .formStyle(.grouped)
        .navigationTitle(album.displayTitle)
    }

    private var locationName: String {
        guard let id = album.physicalLocationID else { return "In a box set or not recorded" }
        return locations.first(where: { $0.id == id })?.name ?? "Unknown location"
    }
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
