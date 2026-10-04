import Foundation
import Testing
import MusicDomain
@testable import MusicApplication

@Suite("Import attachment review")
struct ImportAttachmentReviewTests {
    @Test("Album-origin selection offers only uncommitted proposed and approved candidates")
    func pendingCandidates() {
        func proposal(_ status: ImportProposalStatus, added: Bool = false) -> ImportReleaseProposal {
            .init(id: UUID(), batchID: .init(), title: "Synthetic", artist: nil, discCount: 1, trackCount: 1, confidence: 1, provenance: "fixture", status: status, createdAlbumID: added ? .init() : nil)
        }
        let proposed = proposal(.proposed), approved = proposal(.approved)
        let items = [proposed, approved, proposal(.dismissed), proposal(.approved, added: true)]
        #expect(ImportAttachmentReview.pendingProposals(items) == [proposed, approved])
        #expect(ImportAttachmentReview.pendingProposals([]).isEmpty)
    }
    @Test("Confirmation requires acknowledgment and compatible evidence for the exact proposal and target")
    func confirmationGate() {
        let proposalID = UUID(), albumID = AlbumID()
        let preview = ImportAttachmentPreview(proposalID: proposalID, albumID: albumID, albumTitle: "Target", mode: .populateEmptyAlbum, pairs: [], isCompatible: true, compatibilityMessage: "Synthetic")
        #expect(ImportAttachmentReview.canConfirm(preview, proposalID: proposalID, albumID: albumID, acknowledged: true))
        #expect(!ImportAttachmentReview.canConfirm(preview, proposalID: proposalID, albumID: albumID, acknowledged: false))
        #expect(!ImportAttachmentReview.canConfirm(nil, proposalID: proposalID, albumID: albumID, acknowledged: true))
        #expect(!ImportAttachmentReview.canConfirm(preview, proposalID: UUID(), albumID: albumID, acknowledged: true))
        #expect(!ImportAttachmentReview.canConfirm(preview, proposalID: proposalID, albumID: AlbumID(), acknowledged: true))
        #expect(!ImportAttachmentReview.canConfirm(preview, proposalID: proposalID, albumID: nil, acknowledged: true))
        let mismatch = ImportAttachmentPreview(proposalID: proposalID, albumID: albumID, albumTitle: "Target", mode: .attachToExistingTracks, pairs: [], isCompatible: false, compatibilityMessage: "Track-count mismatch")
        #expect(!ImportAttachmentReview.canConfirm(mismatch, proposalID: proposalID, albumID: albumID, acknowledged: true))
    }
}
