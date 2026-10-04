import SwiftUI
import MusicDomain
import MusicApplication

struct ImportAttachmentReviewView: View {
    @ObservedObject var library: LibraryStore
    let proposal: ImportReleaseProposal
    let onBusyChange: (Bool) -> Void
    let onAttach: (AlbumID) async throws -> Void
    let onReviewMatching: () -> Void
    let onCancel: () -> Void
    var intendedTargetID: AlbumID? = nil
    var onSeparateAlbum: (() -> Void)? = nil
    @State private var searchText = ""
    @State private var selectedAlbumID: AlbumID?
    @State private var preview: ImportAttachmentPreview?
    @State private var requestID = UUID()
    @State private var isLoading = false
    @State private var isAttaching = false
    @State private var acknowledged = false
    @State private var errorMessage: String?

    private var albums: [Album] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.catalogueAlbums.filter { album in
            term.isEmpty || [album.title, album.editionLabel, album.catalogueNumber, album.countryCode, album.releaseYear.map(String.init)].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(term) }
        }.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }
    private var canAttach: Bool {
        !isLoading && !isAttaching && ImportAttachmentReview.canConfirm(preview, proposalID: proposal.id, albumID: selectedAlbumID, acknowledged: acknowledged)
    }

    var body: some View {
        GroupBox("Link Files to an Existing Album") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Existing titles, credits, artwork and edition metadata stay unchanged. Empty albums receive the imported disc/track structure. Source audio files are never copied, moved, renamed or retagged.").font(.caption).foregroundStyle(.secondary)
                if let intendedTargetID {
                    LabeledContent("Target album", value: library.catalogueAlbums.first(where: { $0.id == intendedTargetID })?.displayTitle ?? "Album unavailable")
                } else {
                TextField("Find an album by title, edition or catalogue number", text: $searchText)
                Picker("Target album", selection: Binding(get: { selectedAlbumID }, set: { selectedAlbumID = $0; invalidatePreview() })) {
                    Text("Select an album…").tag(Optional<AlbumID>.none)
                    ForEach(albums) { album in Text(album.displayTitle).tag(Optional(album.id)) }
                }
                if albums.isEmpty { Text("No albums match this search.").font(.caption).foregroundStyle(.secondary) }
                }
                if isLoading { ProgressView("Checking tracks and file paths…") }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    Button("Retry Preview") { invalidatePreview() }
                }
                if let preview, preview.albumID == selectedAlbumID, preview.proposalID == proposal.id {
                    Text(preview.albumTitle).font(.headline)
                    Label(preview.isCompatible ? "Ready for pairing review" : "Cannot attach safely", systemImage: preview.isCompatible ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(preview.isCompatible ? .green : .orange)
                    Text(preview.compatibilityMessage).font(.callout)
                    Text("File-to-track pairing").font(.subheadline.bold())
                    ForEach(preview.pairs) { pair in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Imported: \(pair.importedTitle)")
                            Text("Disc \(pair.discNumber) · Track \(pair.catalogueTrackNumber.map(String.init) ?? pair.importedTrackNumber.map(String.init) ?? "—"): \(pair.catalogueTitle ?? pair.importedTitle)")
                                .font(.callout).foregroundStyle(.secondary)
                            Text(pair.catalogueTitle == nil ? "New track will be created" : "Catalogue title preserved").font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("Source path") { Text(pair.relativePath).font(.caption).textSelection(.enabled) }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if preview.isCompatible {
                        Toggle("I reviewed the target album and file-to-track pairing", isOn: $acknowledged)
                    } else {
                        Button("Review Matching") { onReviewMatching() }
                        Button(intendedTargetID == nil ? "Return to Add a Separate Album" : "Add a Separate Album in Imports") { (onSeparateAlbum ?? onCancel)() }
                    }
                }
                HStack {
                    Button(isAttaching ? "Attaching…" : "Attach Digital Files") { attach() }.buttonStyle(.borderedProminent).disabled(!canAttach)
                    Button("Cancel Linking", action: onCancel)
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(isAttaching)
        .onAppear { if let intendedTargetID { selectedAlbumID = intendedTargetID; invalidatePreview() } }
        .task(id: requestID) { await loadPreview() }
        .onChange(of: searchText) { _, _ in
            if let id = selectedAlbumID, !albums.contains(where: { $0.id == id }) { selectedAlbumID = nil; invalidatePreview() }
        }
        .onChange(of: proposal) { _, _ in invalidatePreview() }
        .onChange(of: library.catalogueRevision) { _, _ in invalidatePreview() }
    }

    private func invalidatePreview() {
        requestID = UUID(); preview = nil; acknowledged = false; errorMessage = nil; isLoading = false
    }
    private func loadPreview() async {
        guard let albumID = selectedAlbumID else { return }
        let token = requestID
        isLoading = true
        defer { if token == requestID { isLoading = false } }
        do {
            let result = try await library.importAttachmentPreview(proposalID: proposal.id, albumID: albumID)
            guard !Task.isCancelled, token == requestID, selectedAlbumID == albumID else { return }
            preview = result
        } catch {
            guard !Task.isCancelled, token == requestID else { return }
            errorMessage = error.localizedDescription
        }
    }
    private func attach() {
        guard canAttach, let albumID = selectedAlbumID else { return }
        isAttaching = true; errorMessage = nil; onBusyChange(true)
        Task {
            defer { isAttaching = false; onBusyChange(false) }
            do { try await onAttach(albumID) }
            catch {
                invalidatePreview()
                await loadPreview()
                errorMessage = error.localizedDescription
            }
        }
    }
}
