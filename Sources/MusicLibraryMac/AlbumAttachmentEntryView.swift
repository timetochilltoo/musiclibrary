import SwiftUI
import MusicDomain
import MusicApplication

struct AlbumAttachmentEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let album: Album
    let onAttached: () async -> Void
    let onReviewMatching: (ImportBatchID) -> Void
    @State private var selectedBatchID: ImportBatchID?
    @State private var selectedProposalID: UUID?
    @State private var proposals: [ImportReleaseProposal] = []
    @State private var showsScanner = false
    @State private var isBusy = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didAttach = false

    private var batch: ImportBatch? { library.importBatches.first { $0.id == selectedBatchID } }
    private var pending: [ImportReleaseProposal] { ImportAttachmentReview.pendingProposals(proposals) }
    private var selected: ImportReleaseProposal? { pending.first { $0.id == selectedProposalID } }
    private var refreshKey: String { "\(selectedBatchID?.description ?? "none")|\(batch?.status.rawValue ?? "none")|\(batch?.candidateCount ?? 0)|\(library.catalogueRevision)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(album.displayTitle).font(.title2.bold())
                    Text("Attach to this album only. Select scanned files or explicitly scan a registered folder; review pairing before saving. Existing metadata and source audio stay unchanged.").font(.callout).foregroundStyle(.secondary)
                    if didAttach {
                        Label("Digital files linked to this album", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    } else if !library.catalogueAlbums.contains(where: { $0.id == album.id }) {
                        ContentUnavailableView("Album unavailable", systemImage: "exclamationmark.triangle", description: Text("The target is no longer in the active catalogue. Nothing can be attached here."))
                    } else {
                        Picker("Import batch", selection: Binding(get: { selectedBatchID }, set: { selectBatch($0) })) {
                            Text("Choose scanned files…").tag(Optional<ImportBatchID>.none)
                            ForEach(library.importBatches) { batch in
                                Text("\(batch.sourceDescription ?? "Music folder") · \(batch.status.rawValue)").tag(Optional(batch.id))
                            }
                        }
                        Button("Scan Registered Folder…", systemImage: "folder") { showsScanner = true }
                        Text("Register new music folders in Settings first. Closing this workspace does not cancel a scan or delete its proposals.").font(.caption).foregroundStyle(.secondary)
                        if let batch {
                            Text("\(batch.candidateCount) audio files · \(batch.errorCount) errors · \(batch.status.rawValue)").font(.caption).foregroundStyle(.secondary)
                            if batch.status == .scanning {
                                ProgressView("Scanning…")
                                Button("Cancel Scan") { Task { await library.cancelImportScan(batch.id) } }
                            } else {
                                Button("Read Metadata for New Files") { readMetadata(batch.id) }
                                if isLoading { ProgressView("Loading candidates…") }
                                if pending.isEmpty, !isLoading {
                                    Text("No pending album candidates. Read metadata if this scan contains new files; added and skipped proposals are not offered for attachment.").foregroundStyle(.secondary)
                                } else {
                                    Picker("Album candidate", selection: $selectedProposalID) {
                                        ForEach(pending) { proposal in Text("\(proposal.title) · \(proposal.trackCount) files").tag(Optional(proposal.id)) }
                                    }
                                }
                                if let selected {
                                    ImportAttachmentReviewView(library: library, proposal: selected, onBusyChange: { isBusy = $0 }, onAttach: { _ in
                                        // Never allow a UI selection to redirect an album-origin write.
                                        _ = try await library.attachImportReleaseProposal(selected.id, to: album.id)
                                        await onAttached()
                                        didAttach = true
                                    }, onReviewMatching: { onReviewMatching(batch.id); dismiss() }, onCancel: { dismiss() }, intendedTargetID: album.id, onSeparateAlbum: { onReviewMatching(batch.id); dismiss() })
                                    .id(selected.id)
                                }
                            }
                        }
                    }
                    if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                    if isBusy { ProgressView("Working…") }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(isBusy)
            .navigationTitle("Attach Digital Files")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(isBusy) } }
        }
        .frame(minWidth: 720, idealWidth: 850, minHeight: 560, idealHeight: 720)
        .interactiveDismissDisabled(isBusy)
        .task(id: refreshKey) { await loadProposals() }
        .sheet(isPresented: $showsScanner) {
            ScanRootPicker(library: library, onStarted: { selectBatch($0) })
        }
    }

    private func selectBatch(_ id: ImportBatchID?) {
        selectedBatchID = id; selectedProposalID = nil; proposals = []; errorMessage = nil; isLoading = false
    }
    private func loadProposals() async {
        guard let id = selectedBatchID, batch?.status != .scanning else { proposals = []; return }
        isLoading = true
        defer { if selectedBatchID == id { isLoading = false } }
        do {
            let result = try await library.importReleaseProposals(batchID: id)
            guard !Task.isCancelled, selectedBatchID == id else { return }
            proposals = result
            if !pending.contains(where: { $0.id == selectedProposalID }) { selectedProposalID = pending.first?.id }
        } catch {
            guard !Task.isCancelled, selectedBatchID == id else { return }
            errorMessage = error.localizedDescription
        }
    }
    private func readMetadata(_ id: ImportBatchID) {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        Task {
            defer { isBusy = false }
            do { try await library.analyzeImportBatch(id); await loadProposals() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
