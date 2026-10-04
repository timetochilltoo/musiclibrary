import Foundation
import MusicDomain

public enum ImportAttachmentReview {
    public static func pendingProposals(_ proposals: [ImportReleaseProposal]) -> [ImportReleaseProposal] {
        proposals.filter { $0.createdAlbumID == nil && $0.status != .dismissed }
    }
    /// UI gate only; database compatibility and path uniqueness are revalidated on commit.
    public static func canConfirm(_ preview: ImportAttachmentPreview?, proposalID: UUID, albumID: AlbumID?, acknowledged: Bool) -> Bool {
        guard acknowledged, let preview, let albumID else { return false }
        return preview.proposalID == proposalID && preview.albumID == albumID && preview.isCompatible
    }
}
