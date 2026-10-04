import AppKit
import SwiftUI
import MusicDomain
import MusicApplication

struct ImportReviewWorkspace: View {
    let batchID: ImportBatchID
    let proposals: [ImportReleaseProposal]
    let previews: [UUID: ImportProposalPreview]
    let candidates: [ImportCandidate]
    let selections: [UUID: ExternalMetadataSelection]
    let library: LibraryStore
    let onAdd: (ImportReleaseProposal) async throws -> AlbumID
    let onStatus: (ImportReleaseProposal, ImportProposalStatus) async throws -> Void
    let onAttach: (ImportReleaseProposal, AlbumID) async throws -> AlbumID
    let onSelectRelease: (ImportReleaseProposal, ExternalReleasePreview) async throws -> Void
    let onApplyMetadata: (ExternalMetadataSelection, ExternalMetadataFieldSelection) async throws -> Void
    let onOpenAlbum: (AlbumID) -> Void
    @AppStorage private var savedCategory: String
    @AppStorage private var savedSelection: String
    @State private var selectedID: UUID?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var lastAdded: (title: String, id: AlbumID)?
    @State private var lastAction = "Added"
    @State private var showsLookup = false
    @State private var showsAttachment = false

    init(batchID: ImportBatchID, proposals: [ImportReleaseProposal], previews: [UUID: ImportProposalPreview], candidates: [ImportCandidate], selections: [UUID: ExternalMetadataSelection], library: LibraryStore, onAdd: @escaping (ImportReleaseProposal) async throws -> AlbumID, onStatus: @escaping (ImportReleaseProposal, ImportProposalStatus) async throws -> Void, onAttach: @escaping (ImportReleaseProposal, AlbumID) async throws -> AlbumID, onSelectRelease: @escaping (ImportReleaseProposal, ExternalReleasePreview) async throws -> Void, onApplyMetadata: @escaping (ExternalMetadataSelection, ExternalMetadataFieldSelection) async throws -> Void, onOpenAlbum: @escaping (AlbumID) -> Void) {
        self.batchID = batchID; self.proposals = proposals; self.previews = previews; self.candidates = candidates; self.selections = selections
        self.library = library
        self.onAdd = onAdd; self.onStatus = onStatus; self.onAttach = onAttach; self.onSelectRelease = onSelectRelease; self.onApplyMetadata = onApplyMetadata; self.onOpenAlbum = onOpenAlbum
        _savedCategory = AppStorage(wrappedValue: ImportReviewCategory.all.rawValue, "MusicLibrary.importReview.\(batchID).category")
        _savedSelection = AppStorage(wrappedValue: "", "MusicLibrary.importReview.\(batchID).selection")
    }

    private var category: ImportReviewCategory { .init(rawValue: savedCategory) ?? .all }
    private var visible: [ImportReleaseProposal] { proposals.filter(category.includes) }
    private var selected: ImportReleaseProposal? { visible.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Review Albums").font(.title2.bold())
                Spacer()
                Picker("Show", selection: $savedCategory) {
                    ForEach(ImportReviewCategory.allCases, id: \.self) { item in
                        Text("\(item.rawValue) (\(proposals.filter(item.includes).count))").tag(item.rawValue)
                    }
                }.frame(maxWidth: 260)
            }
            Text("Choose Add New Album, Link to Existing Album, or Skip. Ready still requires your explicit approval; source files are never changed.")
                .font(.caption).foregroundStyle(.secondary)
            if let lastAdded {
                HStack {
                    Label("\(lastAction) \(lastAdded.title)", systemImage: "checkmark.circle.fill").foregroundStyle(.green).lineLimit(1)
                    Spacer()
                    Button("Open Album") { onOpenAlbum(lastAdded.id) }
                }.font(.callout)
            }
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
            if isBusy { ProgressView("Saving catalogue changes…").controlSize(.small) }
            GeometryReader { geometry in
                if geometry.size.width >= 900 {
                    HStack(spacing: 0) {
                        candidateList.frame(width: 280)
                        Divider()
                        selectedDetail
                    }
                } else {
                    VStack(spacing: 12) {
                        if !visible.isEmpty {
                            Picker("Album candidate", selection: $selectedID) {
                                ForEach(visible) { proposal in Text(proposal.title).tag(Optional(proposal.id)) }
                            }.padding(.horizontal, 12)
                        }
                        selectedDetail
                    }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        }
        .disabled(isBusy)
        .onAppear { restoreSelection() }
        .onChange(of: proposals) { _, _ in restoreSelection() }
        .onChange(of: savedCategory) { _, _ in restoreSelection() }
        .onChange(of: selectedID) { _, id in savedSelection = id?.uuidString ?? ""; errorMessage = nil; showsLookup = false; showsAttachment = false }
    }

    private var candidateList: some View {
        List(visible, selection: $selectedID) { proposal in
            VStack(alignment: .leading, spacing: 5) {
                Text(proposal.title).font(.headline).lineLimit(2)
                Text(proposal.artist ?? "Artist not recorded").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(ImportReviewCategory.category(of: proposal).rawValue).font(.caption2).foregroundStyle(.secondary)
            }.padding(.vertical, 5).tag(proposal.id)
        }
    }

    private var selectedDetail: some View {
        ScrollView {
            if let proposal = selected {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        artwork(for: proposal)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(proposal.title).font(.title2.bold())
                            Text(proposal.artist ?? "Artist not recorded").foregroundStyle(.secondary)
                            Text(pressingSummary(proposal)).font(.caption).foregroundStyle(.secondary)
                            Text(ImportReviewCategory.category(of: proposal).rawValue).font(.caption.bold())
                        }
                    }
                    actionControls(proposal)
                    if showsAttachment, proposal.createdAlbumID == nil, proposal.status != .dismissed {
                        ImportAttachmentReviewView(library: library, proposal: proposal, onBusyChange: { isBusy = $0 }, onAttach: { targetID in
                            let id = try await onAttach(proposal, targetID)
                            lastAction = "Linked"; lastAdded = (proposal.title, id)
                            showsAttachment = false
                            advance(after: proposal)
                        }, onReviewMatching: { showsAttachment = false; showsLookup = true }, onCancel: { showsAttachment = false })
                        .id(proposal.id)
                    }
                    if showsLookup, proposal.createdAlbumID == nil, proposal.status != .dismissed {
                        GroupBox("Find on MusicBrainz") {
                            MusicBrainzReleaseLookupView(library: library, title: proposal.title, artist: proposal.artist, isImportReview: true, onBusyChange: { isBusy = $0 }) { release in
                                try await onSelectRelease(proposal, release)
                                showsLookup = false
                            }
                            .id(proposal.id)
                            .frame(height: 620)
                        }
                    }
                    if !showsAttachment, proposal.createdAlbumID == nil, proposal.status != .dismissed, let selection = selections[proposal.id] {
                        ImportMetadataReviewView(proposal: proposal, selection: selection, importedTracks: previews[proposal.id]?.trackTitles ?? []) { selection, fields in
                            guard !isBusy else { return }
                            isBusy = true
                            defer { isBusy = false }
                            try await onApplyMetadata(selection, fields)
                        }
                        .id(proposal.id)
                    }
                    GroupBox("Tracks to import") { ImportReviewTrackList(candidates: candidates.filter { $0.proposalID == proposal.id }) }
                    DisclosureGroup("Details — source tags and paths") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Metadata source: \(proposal.provenance)")
                            Text("Grouping confidence: \(Int(proposal.confidence * 100))% — not an automatic approval")
                            ForEach(candidates.filter { $0.proposalID == proposal.id }) { candidate in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.payload?.relativePath ?? "Path unavailable").textSelection(.enabled)
                                    ForEach((candidate.metadata?.rawTags ?? [:]).keys.sorted(), id: \.self) { key in
                                        Text("\(key): \(candidate.metadata?.rawTags[key] ?? "")").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }.font(.caption)
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(proposals.isEmpty ? "No album candidates yet" : "Nothing in \(category.rawValue)", systemImage: "tray", description: Text(proposals.isEmpty ? "Read metadata for new files, or expand Scan and File Details below." : "Choose another category to continue reviewing."))
                    .padding(24)
            }
        }
    }

    @ViewBuilder private func actionControls(_ proposal: ImportReleaseProposal) -> some View {
        if let albumID = proposal.createdAlbumID {
            Button("Open Album", systemImage: "rectangle.on.rectangle") { onOpenAlbum(albumID) }
        } else if proposal.status == .dismissed {
            Button("Return to Review", systemImage: "arrow.uturn.backward") { changeStatus(proposal, to: .proposed) }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Button("Add New Album", systemImage: "plus") { add(proposal) }.buttonStyle(.borderedProminent)
                    Button(showsAttachment ? "Close Linking" : "Link to Existing Album", systemImage: "link") { showsAttachment.toggle(); showsLookup = false }
                    Button("Skip") { changeStatus(proposal, to: .dismissed) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Button("Add New Album", systemImage: "plus") { add(proposal) }.buttonStyle(.borderedProminent)
                    Button(showsAttachment ? "Close Linking" : "Link to Existing Album", systemImage: "link") { showsAttachment.toggle(); showsLookup = false }
                    Button("Skip") { changeStatus(proposal, to: .dismissed) }
                }
            }
            HStack {
                Button(showsLookup ? "Close MusicBrainz Lookup" : "Find on MusicBrainz", systemImage: "magnifyingglass") { showsLookup.toggle(); showsAttachment = false }
                if selections[proposal.id] != nil { Text("Selected release fields are below").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func restoreSelection() {
        selectedID = category.selection(in: proposals, preferredID: selectedID ?? UUID(uuidString: savedSelection))
    }

    private func advance(after proposal: ImportReleaseProposal) {
        selectedID = ImportReviewCategory.nextPending(after: proposal.id, in: proposals)
        if let selectedID, let next = proposals.first(where: { $0.id == selectedID }), !category.includes(next) {
            savedCategory = ImportReviewCategory.category(of: next).rawValue
        }
    }

    private func add(_ proposal: ImportReleaseProposal) {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        Task {
            defer { isBusy = false }
            do { let id = try await onAdd(proposal); lastAction = "Added"; lastAdded = (proposal.title, id); advance(after: proposal) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func changeStatus(_ proposal: ImportReleaseProposal, to status: ImportProposalStatus) {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await onStatus(proposal, status)
                if status == .proposed { savedCategory = ImportReviewCategory.needsReview.rawValue; selectedID = proposal.id }
                else { advance(after: proposal) }
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func pressingSummary(_ proposal: ImportReleaseProposal) -> String {
        ["\(proposal.discCount) disc\(proposal.discCount == 1 ? "" : "s")", "\(proposal.trackCount) file\(proposal.trackCount == 1 ? "" : "s")", proposal.countryCode, proposal.catalogueNumber].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private func artwork(for proposal: ImportReleaseProposal) -> some View {
        if let url = previews[proposal.id]?.artworkURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill().frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "music.note.list").font(.title2).foregroundStyle(.secondary).frame(width: 96, height: 96).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ImportReviewTrackList: View {
    let candidates: [ImportCandidate]
    private var grouped: [Int: [ImportCandidate]] { Dictionary(grouping: candidates, by: { $0.metadata?.discNumber ?? 1 }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(grouped.keys.sorted(), id: \.self) { disc in
                Text("Disc \(disc)").font(.subheadline.bold())
                ForEach((grouped[disc] ?? []).sorted { ($0.metadata?.trackNumber ?? Int.max) < ($1.metadata?.trackNumber ?? Int.max) }) { candidate in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(candidate.metadata?.trackNumber.map(String.init) ?? "—").foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                        Text(candidate.metadata?.title ?? candidate.payload?.fileName ?? "Title unavailable")
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
