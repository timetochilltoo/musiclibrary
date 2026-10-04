import Foundation
import Testing
import MusicDomain
@testable import MusicApplication

@Suite("Import attachment review")
struct ImportAttachmentReviewTests {
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
