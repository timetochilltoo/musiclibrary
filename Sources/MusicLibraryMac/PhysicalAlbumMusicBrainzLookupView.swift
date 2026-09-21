import AppKit
import SwiftUI
import MusicApplication

struct PhysicalAlbumMusicBrainzLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let onSelected: (ExternalReleasePreview) -> Void

    @State private var title: String
    @State private var artist: String
    @State private var results: [ExternalReleasePreview] = []
    @State private var selectedResultID: String?
    @State private var selectedReleaseDetail: ExternalReleasePreview?
    @State private var isSearching = false
    @State private var isLoadingReleaseDetail = false
    @State private var isApplying = false
    @State private var hasSearched = false
    @State private var errorMessage: String?

    init(
        library: LibraryStore,
        title: String,
        artist: String?,
        onSelected: @escaping (ExternalReleasePreview) -> Void
    ) {
        self.library = library
        self.onSelected = onSelected
        _title = State(initialValue: title)
        _artist = State(initialValue: artist ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Search MusicBrainz").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Album title").frame(width: 96, alignment: .trailing)
                            TextField("Album title", text: $title)
                        }
                        GridRow {
                            Text("Artist (optional)").frame(width: 96, alignment: .trailing)
                            TextField("Artist", text: $artist)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                HStack(spacing: 12) {
                    Button("Search MusicBrainz", systemImage: "magnifyingglass") { search() }
                        .disabled(isSearching || trimmedTitle == nil)
                    Text("Only the title and artist are sent. Nothing is added until you use the selected release and save the album.")
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
                        ContentUnavailableView("No matching releases", systemImage: "magnifyingglass", description: Text("Try a different album title or artist."))
                        Spacer()
                    } else if !results.isEmpty {
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

                            Divider()

                            PhysicalAlbumMusicBrainzReleaseDetail(
                                result: displayedResult,
                                isLoading: isLoadingReleaseDetail
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        Spacer()
                        ContentUnavailableView("Find a physical release", systemImage: "opticaldisc", description: Text("Search by album title and optionally artist, then choose the matching pressing to fill the physical-album form."))
                        Spacer()
                    }
                }
            }
            .navigationTitle("MusicBrainz Physical Release")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isApplying ? "Applying…" : "Use Selected Release") { useSelectedRelease() }
                        .disabled(selectedResult == nil || isApplying)
                }
            }
            .alert("MusicBrainz search failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 900, idealWidth: 1_100, maxWidth: 1_400, minHeight: 600, idealHeight: 720, maxHeight: 900)
        .background(PhysicalAlbumMusicBrainzSheetResizability())
        .task(id: selectedResultID) { await loadSelectedReleaseDetail() }
    }

    private var trimmedTitle: String? {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
        guard let trimmedTitle else { return }
        isSearching = true
        hasSearched = true
        results = []
        selectedResultID = nil
        selectedReleaseDetail = nil
        Task {
            do {
                results = try await library.searchMusicBrainz(title: trimmedTitle, artist: artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : artist)
                selectedResultID = results.first?.id
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func loadSelectedReleaseDetail() async {
        guard let selectedResultID else {
            selectedReleaseDetail = nil
            return
        }
        isLoadingReleaseDetail = true
        defer { isLoadingReleaseDetail = false }
        do {
            selectedReleaseDetail = try await library.musicBrainzReleaseDetails(id: selectedResultID)
        } catch {
            selectedReleaseDetail = nil
        }
    }

    private func useSelectedRelease() {
        guard let selectedResult else { return }
        isApplying = true
        Task {
            do {
                let release = selectedReleaseDetail?.id == selectedResult.id
                    ? selectedReleaseDetail!
                    : try await library.musicBrainzReleaseDetails(id: selectedResult.id)
                onSelected(release)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isApplying = false
        }
    }
}

private struct PhysicalAlbumMusicBrainzReleaseDetail: View {
    let result: ExternalReleasePreview?
    let isLoading: Bool

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
                                Text("Use Selected Release fills the album fields on the previous form. It does not create the catalogue record yet.")
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
                            if result.trackTitles.isEmpty {
                                Text("MusicBrainz did not return a track listing for this release.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(Array(result.trackTitles.enumerated()), id: \.offset) { index, title in
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("\(index + 1).").foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                                            Text(title)
                                        }
                                    }
                                }
                            }
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

private struct PhysicalAlbumMusicBrainzSheetResizability: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.minSize = .init(width: 900, height: 600)
            window.maxSize = .init(width: 1_400, height: 900)
        }
    }
}
