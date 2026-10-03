import Foundation
import MusicDomain

/// Presentation categories only: never grant authority for unattended import.
public enum ImportReviewCategory: String, CaseIterable, Sendable {
    case all = "All", needsReview = "Needs Review", ready = "Ready", added = "Added", skipped = "Skipped"

    public static func category(of proposal: ImportReleaseProposal) -> Self {
        if proposal.createdAlbumID != nil { return .added }
        switch proposal.status {
        case .proposed: return .needsReview
        case .approved: return .ready
        case .dismissed: return .skipped
        }
    }

    public func includes(_ proposal: ImportReleaseProposal) -> Bool {
        self == .all || Self.category(of: proposal) == self
    }

    public func selection(in proposals: [ImportReleaseProposal], preferredID: UUID?) -> UUID? {
        let visible = proposals.filter(includes)
        return visible.first(where: { $0.id == preferredID })?.id ?? visible.first?.id
    }

    public static func nextPending(after id: UUID, in proposals: [ImportReleaseProposal]) -> UUID? {
        let pending = proposals.filter { $0.id != id && [.needsReview, .ready].contains(category(of: $0)) }
        let pendingIDs = Set(pending.map(\.id))
        guard let index = proposals.firstIndex(where: { $0.id == id }) else { return pending.first?.id }
        return proposals.dropFirst(index + 1).first(where: { pendingIDs.contains($0.id) })?.id ?? pending.first?.id
    }
}
