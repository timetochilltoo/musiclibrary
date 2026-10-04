import MusicDomain

/// Explicit field choices for an uncommitted import proposal, never automatic approval.
public struct ImportMetadataReviewDraft: Equatable, Sendable {
    public var fields = ExternalMetadataFieldSelection(title: false, artist: false, discCount: false)
    public init() {}

    public func permittedFields(proposal: ImportReleaseProposal, selection: ExternalMetadataSelection) -> ExternalMetadataFieldSelection? {
        guard proposal.id == selection.importProposalID, proposal.createdAlbumID == nil,
              proposal.status != .dismissed else { return nil }
        var result = fields
        result.trackTitles = result.trackTitles && Self.trackTitlesMatch(proposal: proposal, selection: selection)
        guard result.title || result.artist || result.discCount || result.countryCode || result.catalogueNumber || result.releaseDate || result.trackTitles || result.frontArtwork else { return nil }
        return result
    }

    public static func trackTitlesMatch(proposal: ImportReleaseProposal, selection: ExternalMetadataSelection) -> Bool {
        proposal.trackCount == selection.trackTitles.count && !selection.trackTitles.isEmpty
    }
}
