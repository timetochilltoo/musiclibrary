import SwiftUI

struct AlbumLibraryEmptyState: View {
    let hasMusicFolders: Bool
    let addPhysicalAlbum: () -> Void
    let importMusicFolder: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Start your music library").font(.largeTitle.bold())
                Text("Keep your physical collection and digital music together.")
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { physicalCard; digitalCard }
                    VStack(spacing: 16) { physicalCard; digitalCard }
                }
                Text("Your source audio stays in place. Sharing with iPad is optional.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
    }

    private var physicalCard: some View {
        entryCard("Physical collection", symbol: "opticaldisc",
                  detail: "Catalogue CDs, vinyl and other editions. Find release details on MusicBrainz or enter them yourself.",
                  action: "Add Physical Album", perform: addPhysicalAlbum)
    }

    private var digitalCard: some View {
        entryCard("Digital music", symbol: "folder",
                  detail: hasMusicFolders
                    ? "Scan a registered music folder, then review the releases you want to add."
                    : "First, grant access to a local or NAS music folder. Then scan and review releases before adding them.",
                  action: "Import Music Folder", perform: importMusicFolder)
    }

    private func entryCard(_ title: String, symbol: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.title).foregroundStyle(.tint)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(action, action: perform).buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}
