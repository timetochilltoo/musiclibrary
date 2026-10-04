import AppKit
import SwiftUI
import MusicApplication

struct MusicBrainzReleaseLookupView: View {
    private enum SearchMode: String, CaseIterable { case title = "Title / Artist", barcode = "Barcode", catalogue = "Catalogue Number", url = "Release URL" }
    @ObservedObject var library: LibraryStore
    let isImportReview: Bool
    let onBusyChange: (Bool) -> Void
    let onSelected: (ExternalReleasePreview) async throws -> Void

    @State private var title: String
    @State private var artist: String
    @State private var mode: SearchMode = .title
    @State private var barcode = ""
    @State private var catalogueNumber = ""
    @State private var releaseURL = ""
    @State private var searchGeneration = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var results: [ExternalReleasePreview] = []
    @State private var selectedResultID: String?
    @State private var selectedReleaseDetail: ExternalReleasePreview?
    @State private var isSearching = false
    @State private var isLoadingReleaseDetail = false
    @State private var isApplying = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @State private var isDownloadingArtwork = false
    @State private var artworkMessage: String?

    init(
        library: LibraryStore,
        title: String,
        artist: String?,
        isImportReview: Bool = false,
        onBusyChange: @escaping (Bool) -> Void = { _ in },
        onSelected: @escaping (ExternalReleasePreview) async throws -> Void
    ) {
        self.library = library
        self.onSelected = onSelected
        self.isImportReview = isImportReview
        self.onBusyChange = onBusyChange
        _title = State(initialValue: title)
        _artist = State(initialValue: artist ?? "")
    }

    var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Search MusicBrainz").font(.headline)
                    Picker("Find by", selection: $mode) {
                        ForEach(SearchMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).disabled(isApplying)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text(inputLabel).frame(width: 110, alignment: .trailing)
                            switch mode {
                            case .title: TextField("Album title", text: $title)
                            case .barcode: TextField("Barcode digits, including leading zeros", text: $barcode)
                            case .catalogue: TextField("Catalogue number", text: $catalogueNumber)
                            case .url: TextField("https://musicbrainz.org/release/…", text: $releaseURL)
                            }
                        }
                        if mode == .title || mode == .catalogue {
                        GridRow {
                            Text("Artist (optional)").frame(width: 110, alignment: .trailing)
                            TextField("Artist", text: $artist)
                        }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .disabled(isApplying)

                HStack(spacing: 12) {
                    Button("Search MusicBrainz", systemImage: "magnifyingglass") { search() }
                        .disabled(isSearching || isApplying || inputIsEmpty)
                    Text(isImportReview ? "Only entered text or the release ID is sent. Choosing a release saves a comparison reference; fields and audio files stay unchanged." : "Only entered search text or the release ID is sent to MusicBrainz. Nothing is saved until Add Album.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

                Divider()

                Group {
                    if isSearching {
                        Spacer()
                        ProgressView("Searching MusicBrainz…")
                        Spacer()
                    } else if hasSearched && results.isEmpty {
                        Spacer()
                        ContentUnavailableView("No matching releases", systemImage: "magnifyingglass", description: Text("Check the lookup value, or try Title / Artist to find another pressing."))
                        Spacer()
                    } else if !results.isEmpty {
                        if isImportReview {
                            VStack(spacing: 8) {
                                Picker("Release candidate", selection: $selectedResultID) {
                                    ForEach(results) { result in
                                        Text("\(result.title) · \(summary(for: result))").tag(Optional(result.id))
                                    }
                                }.padding(.horizontal, 16).disabled(isApplying)
                                PhysicalAlbumMusicBrainzReleaseDetail(result: displayedResult, isLoading: isLoadingReleaseDetail, isImportReview: true)
                            }
                        } else {
                        HStack(spacing: 0) {
                            List(selection: $selectedResultID) {
                                Section("Release candidates") {
                                    ForEach(results) { result in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(result.title)
                                                .font(.headline)
                                                .lineLimit(2)
                                            Text(summary(for: result))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                            Text("\(result.mediaCount) disc\(result.mediaCount == 1 ? "" : "s")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .tag(result.id)
                                    }
                                }
                            }
                            .frame(minWidth: 280, maxWidth: 340)
                            .disabled(isApplying)

                            Divider()

                            PhysicalAlbumMusicBrainzReleaseDetail(
                                result: displayedResult,
                                isLoading: isLoadingReleaseDetail
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        }
                    } else {
                        Spacer()
                        ContentUnavailableView("Find a release", systemImage: "opticaldisc", description: Text(isImportReview ? "Search explicitly, review the pressing, then choose a release for field comparison." : "Search by title, barcode or catalogue number, or paste a MusicBrainz release URL. Choose the matching pressing to fill Review."))
                        Spacer()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if isImportReview, let result = displayedResult {
                        Button(isDownloadingArtwork ? "Downloading Cover…" : "Save Cover JPEG…") { downloadArtwork(result) }
                            .disabled(isDownloadingArtwork || isApplying || result.coverArtworkURL == nil)
                    }
                    Spacer()
                    Button(isApplying ? "Loading Selection…" : (isImportReview ? "Choose for Comparison" : "Use Selected Release")) { useSelectedRelease() }
                        .disabled(selectedResult == nil || isApplying || isSearching)
                        .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
            .alert("MusicBrainz search failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Cover artwork", isPresented: Binding(get: { artworkMessage != nil }, set: { if !$0 { artworkMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(artworkMessage ?? "") }
        .task(id: selectedResultID) { await loadSelectedReleaseDetail() }
        .onChange(of: mode) { _, _ in
            searchGeneration += 1
            searchTask?.cancel()
            isSearching = false
            hasSearched = false
            results = []
            selectedResultID = nil
            selectedReleaseDetail = nil
            isLoadingReleaseDetail = false
            errorMessage = nil
        }
        .onDisappear { searchGeneration += 1; searchTask?.cancel() }
    }

    private var inputLabel: String {
        switch mode { case .title: "Album title"; case .barcode: "Barcode"; case .catalogue: "Catalogue no."; case .url: "Release URL" }
    }

    private var inputIsEmpty: Bool {
        let text: String
        switch mode { case .title: text = title; case .barcode: text = barcode; case .catalogue: text = catalogueNumber; case .url: text = releaseURL }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lookup: MusicBrainzReleaseLookup {
        switch mode {
        case .title: .title(title, artist: artist)
        case .barcode: .barcode(barcode)
        case .catalogue: .catalogueNumber(catalogueNumber, artist: artist)
        case .url: .releaseURL(releaseURL)
        }
    }

    private var selectedResult: ExternalReleasePreview? {
        results.first { $0.id == selectedResultID }
    }

    private var displayedResult: ExternalReleasePreview? {
        guard let selectedResult else { return nil }
        return selectedReleaseDetail?.id == selectedResult.id ? selectedReleaseDetail : selectedResult
    }

    private func summary(for result: ExternalReleasePreview) -> String {
        [result.artist, result.releaseDate, result.countryCode, result.labelName, result.catalogueNumber, result.barcode]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " · ")
    }

    private func search() {
        guard !inputIsEmpty, !isApplying else { return }
        searchGeneration += 1
        let generation = searchGeneration
        let request = lookup
        searchTask?.cancel()
        isSearching = true
        hasSearched = true
        results = []
        selectedResultID = nil
        selectedReleaseDetail = nil
        searchTask = Task {
            defer { if generation == searchGeneration { isSearching = false } }
            do {
                let found = try await library.lookupMusicBrainz(request)
                guard !Task.isCancelled, generation == searchGeneration else { return }
                results = found
                selectedResultID = results.first?.id
            } catch {
                guard !Task.isCancelled, generation == searchGeneration else { return }
                // A failed lookup is not a successful search with zero matches.
                hasSearched = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadSelectedReleaseDetail() async {
        guard let selectedResultID else {
            selectedReleaseDetail = nil
            return
        }
        isLoadingReleaseDetail = true
        defer { if self.selectedResultID == selectedResultID { isLoadingReleaseDetail = false } }
        do {
            let detail = try await library.musicBrainzReleaseDetails(id: selectedResultID)
            guard !Task.isCancelled, self.selectedResultID == selectedResultID else { return }
            selectedReleaseDetail = detail
        } catch {
            guard !Task.isCancelled, self.selectedResultID == selectedResultID else { return }
            selectedReleaseDetail = nil
        }
    }

    private func useSelectedRelease() {
        guard let selectedResult, !isApplying else { return }
        isApplying = true
        onBusyChange(true)
        Task {
            defer { isApplying = false; onBusyChange(false) }
            do {
                let release = selectedReleaseDetail?.id == selectedResult.id
                    ? selectedReleaseDetail!
                    : try await library.musicBrainzReleaseDetails(id: selectedResult.id)
                try await onSelected(release)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // Explicit JPEG export retained from import lookup; independent of field approval.
    private func downloadArtwork(_ result: ExternalReleasePreview) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = result.title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-") + ".jpg"
        panel.message = "Save a JPEG copy only. This does not change the proposal or catalogue cover."
        guard panel.runModal() == .OK, let destination = panel.url, let artworkURL = result.coverArtworkURL else { return }
        isDownloadingArtwork = true
        Task {
            defer { isDownloadingArtwork = false }
            do {
                let (data, response) = try await URLSession.shared.data(for: MusicNetworkRequestPolicy.request(url: artworkURL))
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let image = NSImage(data: data), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
                    throw NSError(domain: "MusicLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "MusicBrainz did not provide a usable front-cover image."])
                }
                try jpeg.write(to: destination, options: .atomic)
                artworkMessage = "Saved JPEG cover artwork to \(destination.lastPathComponent)."
            } catch { artworkMessage = "Could not save cover artwork: \(error.localizedDescription)" }
        }
    }
}

private struct PhysicalAlbumMusicBrainzReleaseDetail: View {
    let result: ExternalReleasePreview?
    let isLoading: Bool
    var isImportReview = false

    var body: some View {
        Group {
            if let result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 16) {
                            coverArtwork(for: result)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(result.title)
                                    .font(.title2.bold())
                                if let artist = result.artist, !artist.isEmpty {
                                    Text(artist).font(.headline)
                                }
                                Text("MusicBrainz release ID: \(result.id)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Text(isImportReview ? "Choose for Comparison retains this release reference. Only explicitly checked fields are applied in the import review area." : "Use Selected Release fills the Review step. Nothing is saved until Add Album.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        GroupBox("Physical edition fields") {
                            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                                detailRow("Release year", result.releaseYear.map(String.init))
                                detailRow("Country / region", result.countryCode)
                                detailRow("Record label", result.labelName)
                                detailRow("Catalogue number", result.catalogueNumber)
                                detailRow("Barcode", result.barcode)
                                detailRow("Media format", result.mediaFormat)
                                detailRow("Disc count", result.mediaCount > 0 ? String(result.mediaCount) : nil)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Loading full release details…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        GroupBox("Track listing") {
                            MusicBrainzTrackListingView(release: result)
                        }
                    }
                    .padding(24)
                }
            } else {
                ContentUnavailableView("Select a release", systemImage: "rectangle.and.text.magnifyingglass", description: Text("Select a MusicBrainz result to review its physical-edition fields."))
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
                        Text("No cover").font(.caption).foregroundStyle(.secondary)
                    }
                default: ProgressView()
                }
            }
            .id(result.id)
            .frame(width: 150, height: 150)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(width: 150, height: 150)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private func detailRow(_ label: String, _ value: String?) -> some View {
        GridRow {
            Text(label).font(.subheadline.weight(.medium))
            Text(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value! : "—")
                .textSelection(.enabled)
        }
    }
}

struct PhysicalAlbumMusicBrainzSheetResizability: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.minSize = .init(width: 720, height: 560)
            window.maxSize = .init(width: 1_400, height: 900)
        }
    }
}
