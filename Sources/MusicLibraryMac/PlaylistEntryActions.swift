import SwiftUI

/// Secondary listening actions; organization keeps its explicit movement controls.
struct PlaylistEntryActions: View {
    let title: String
    let canShowAlbum: Bool
    let onPlay: () -> Void
    let onShowAlbum: () -> Void
    let onOrganize: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Menu {
            Button("Play from Here", systemImage: "play.fill", action: onPlay)
            Button("Show Album", systemImage: "square.stack", action: onShowAlbum)
                .disabled(!canShowAlbum)
            Button("Organize Tracks", systemImage: "arrow.up.arrow.down", action: onOrganize)
            Divider()
            Button("Remove from Playlist…", systemImage: "minus.circle", role: .destructive, action: onRemove)
        } label: {
            Label("Actions for \(title)", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 28)
        .help("Actions for \(title)")
        .accessibilityLabel("Actions for \(title)")
    }
}
