import Foundation

public enum LyricsKind: String, Codable, CaseIterable, Sendable { case plain, synchronized }

public struct LyricsEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let trackID: TrackID
    public let language: String?
    public let kind: LyricsKind
    public let text: String
    public let source: String
    public let providerID: String?
    public let isUserEdited: Bool
    public init(id: UUID = UUID(), trackID: TrackID, language: String? = nil, kind: LyricsKind = .plain, text: String, source: String = "manual", providerID: String? = nil, isUserEdited: Bool = true) { self.id = id; self.trackID = trackID; self.language = language; self.kind = kind; self.text = text; self.source = source; self.providerID = providerID; self.isUserEdited = isUserEdited }
}
