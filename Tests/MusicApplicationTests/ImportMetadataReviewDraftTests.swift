import Foundation
import Testing
import MusicDomain
@testable import MusicApplication

@Suite("Import metadata review draft")
struct ImportMetadataReviewDraftTests {
    private func proposal(status: ImportProposalStatus = .proposed, added: Bool = false) -> ImportReleaseProposal {
        .init(id: UUID(), batchID: .init(), title: "Imported", artist: "Artist", discCount: 1, trackCount: 1, confidence: 0.9, provenance: "fixture", status: status, createdAlbumID: added ? .init() : nil)
    }
    private func selection(_ proposal: ImportReleaseProposal, tracks: [String] = ["Corrected track"]) -> ExternalMetadataSelection {
        .init(id: UUID(), importProposalID: proposal.id, provider: "musicbrainz", externalID: UUID().uuidString, title: "Corrected", artist: "Corrected artist", discCount: 1, trackTitles: tracks)
    }

    @Test("Review starts unchecked and permits only explicit choices on the matching pending proposal")
    func explicitFields() throws {
        let proposal = proposal(), selected = selection(proposal)
        var draft = ImportMetadataReviewDraft()
        #expect(draft.permittedFields(proposal: proposal, selection: selected) == nil)
        draft.fields.title = true
        let fields = try #require(draft.permittedFields(proposal: proposal, selection: selected))
        #expect(fields == .init(title: true, artist: false, discCount: false))
        #expect(draft.permittedFields(proposal: self.proposal(), selection: selected) == nil)
        for proposal in [self.proposal(status: .dismissed), self.proposal(added: true)] {
            #expect(draft.permittedFields(proposal: proposal, selection: selection(proposal)) == nil)
        }
    }

    @Test("Unavailable or mismatched tracks cannot be applied; other explicit fields remain usable")
    func trackMismatch() throws {
        let proposal = proposal()
        var draft = ImportMetadataReviewDraft()
        draft.fields.trackTitles = true
        for tracks in [[], ["One", "Two"]] {
            #expect(draft.permittedFields(proposal: proposal, selection: selection(proposal, tracks: tracks)) == nil)
        }
        draft.fields.title = true
        let fields = try #require(draft.permittedFields(proposal: proposal, selection: selection(proposal, tracks: [])))
        #expect(fields.title && !fields.trackTitles)
        #expect(draft.permittedFields(proposal: proposal, selection: selection(proposal))?.trackTitles == true)
    }
}
