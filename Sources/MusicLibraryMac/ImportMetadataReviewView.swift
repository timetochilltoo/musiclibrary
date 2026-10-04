import SwiftUI
import MusicDomain
import MusicApplication

struct ImportMetadataReviewView: View {
    let proposal: ImportReleaseProposal
    let selection: ExternalMetadataSelection
    let importedTracks: [String]
    let onApply: (ExternalMetadataSelection, ExternalMetadataFieldSelection) async throws -> Void
    @State private var draft = ImportMetadataReviewDraft()
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var applied = false

    var body: some View {
        GroupBox("Review MusicBrainz Fields") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Selected release: \(selection.title)").font(.headline)
                Text("Choose the fields to use. Applying updates this proposal only; Add New Album is still a separate step. Audio tags are never changed.")
                    .font(.caption).foregroundStyle(.secondary)
                field("Album title", current: proposal.title, proposed: selection.title, choice: $draft.fields.title)
                field("Artist", current: proposal.artist, proposed: selection.artist, choice: $draft.fields.artist)
                field("Disc count", current: String(proposal.discCount), proposed: String(selection.discCount), choice: $draft.fields.discCount)
                field("Country / region", current: proposal.countryCode, proposed: selection.countryCode, choice: $draft.fields.countryCode)
                field("Catalogue number", current: proposal.catalogueNumber, proposed: selection.catalogueNumber, choice: $draft.fields.catalogueNumber)
                field("Release date", current: "From imported audio tags", proposed: selection.releaseDate, choice: $draft.fields.releaseDate)
                DisclosureGroup("Compare track titles (\(importedTracks.count) imported / \(selection.trackTitles.count) MusicBrainz)") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<max(importedTracks.count, selection.trackTitles.count), id: \.self) { index in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1). Imported: \(index < importedTracks.count ? importedTracks[index] : "—")")
                                Text("MusicBrainz: \(index < selection.trackTitles.count ? selection.trackTitles[index] : "—")").foregroundStyle(.secondary)
                            }.font(.caption)
                        }
                    }
                }
                Toggle("Use MusicBrainz track titles", isOn: $draft.fields.trackTitles)
                    .disabled(!ImportMetadataReviewDraft.trackTitlesMatch(proposal: proposal, selection: selection))
                if !ImportMetadataReviewDraft.trackTitlesMatch(proposal: proposal, selection: selection) {
                    Text("Track counts differ or MusicBrainz has no track list. Track titles cannot be applied; review the pressing or keep the imported titles.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Use MusicBrainz front cover", isOn: $draft.fields.frontArtwork)
                Text("Cover selection downloads into managed library storage only. If it fails, retry or uncheck the cover and apply again.").font(.caption).foregroundStyle(.secondary)
                if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
                if applied { Label("Selected fields applied to this proposal", systemImage: "checkmark.circle").foregroundStyle(.green).font(.callout) }
                HStack {
                    Button(isApplying ? "Applying…" : "Apply Selected Fields") { apply() }
                        .disabled(draft.permittedFields(proposal: proposal, selection: selection) == nil)
                    if isApplying { ProgressView().controlSize(.small) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        .disabled(isApplying)
        .onChange(of: selection) { _, _ in draft = .init(); applied = false; errorMessage = nil }
    }

    private func field(_ name: String, current: String?, proposed: String?, choice: Binding<Bool>) -> some View {
        Toggle(isOn: choice) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.bold())
                Text("Imported: \(current ?? "—")").font(.caption)
                Text("MusicBrainz: \(proposed ?? "—")").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func apply() {
        guard !isApplying, let fields = draft.permittedFields(proposal: proposal, selection: selection) else { return }
        isApplying = true; errorMessage = nil; applied = false
        Task {
            defer { isApplying = false }
            do { try await onApply(selection, fields); draft = .init(); applied = true }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
