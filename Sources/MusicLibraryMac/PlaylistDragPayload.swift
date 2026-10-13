import SwiftUI
import UniformTypeIdentifiers
import MusicDomain

/// App-specific entry references only; never exports audio, artwork or file URLs.
struct PlaylistDragPayload: Codable, Transferable {
    let playlistID: PlaylistID
    let itemID: UUID
    let expectedItemIDs: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.timetochilltoo.MusicLibraryMac.playlist-entry"))
    }
}
