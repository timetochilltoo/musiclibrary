import Foundation
import Testing
import MusicDomain
@testable import MusicApplication

@Suite("Import review presentation")
struct ImportReviewPresentationTests {
    private func proposal(_ status: ImportProposalStatus, added: Bool = false) -> ImportReleaseProposal {
        .init(id: UUID(), batchID: .init(), title: "Synthetic", artist: nil, discCount: 1, trackCount: 1, confidence: 0.9, provenance: "fixture", status: status, createdAlbumID: added ? .init() : nil)
    }

    @Test("Categories map persisted states without implying automatic import")
    func categories() {
        #expect(ImportReviewCategory.category(of: proposal(.proposed)) == .needsReview)
        #expect(ImportReviewCategory.category(of: proposal(.approved)) == .ready)
        #expect(ImportReviewCategory.category(of: proposal(.dismissed)) == .skipped)
        for status in ImportProposalStatus.allCases {
            #expect(ImportReviewCategory.category(of: proposal(status, added: true)) == .added)
        }
    }

    @Test("Selection restores valid IDs and recovers from hidden, removed or empty candidates")
    func selection() {
        let first = proposal(.proposed), second = proposal(.approved), skipped = proposal(.dismissed)
        let proposals = [first, second, skipped]
        #expect(ImportReviewCategory.all.selection(in: proposals, preferredID: second.id) == second.id)
        #expect(ImportReviewCategory.needsReview.selection(in: proposals, preferredID: second.id) == first.id)
        #expect(ImportReviewCategory.all.selection(in: proposals, preferredID: UUID()) == first.id)
        #expect(ImportReviewCategory.added.selection(in: proposals, preferredID: first.id) == nil)
        #expect(ImportReviewCategory.all.selection(in: [], preferredID: first.id) == nil)
    }

    @Test("Advancing skips completed and skipped candidates, wraps, and never selects the submitted candidate")
    func advance() {
        let first = proposal(.proposed), skipped = proposal(.dismissed), added = proposal(.approved, added: true), last = proposal(.approved)
        let proposals = [first, skipped, added, last]
        #expect(ImportReviewCategory.nextPending(after: first.id, in: proposals) == last.id)
        #expect(ImportReviewCategory.nextPending(after: last.id, in: proposals) == first.id)
        #expect(ImportReviewCategory.nextPending(after: first.id, in: [first, skipped, added]) == nil)
    }
}
