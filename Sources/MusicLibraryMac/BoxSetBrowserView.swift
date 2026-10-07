import SwiftUI
import MusicDomain
import MusicApplication

struct BoxSetBrowserView: View {
    @ObservedObject var library: LibraryStore
    @Binding var selection: BoxSetID?
    @Binding var search: String
    let onDelete: (BoxSet) -> Void
    private var boxes: [BoxSet] { BoxSetBrowseSummary.matching(library.boxSets, locations: library.locations, query: search) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(boxes.count) box set\(boxes.count == 1 ? "" : "s")").font(.callout)
                Spacer()
                TextField("Search title, edition or location", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            }.padding(16)
            List(boxes) { box in
                Button { selection = box.id } label: {
                    HStack(spacing: 16) {
                        BoxSetIdentityArtwork(library: library, boxID: box.id, size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(box.title).font(.headline)
                            if let edition = box.editionLabel, !edition.isEmpty { Text(edition).font(.callout).foregroundStyle(.secondary) }
                            Text(boxLocation(box, library: library)).font(.caption).foregroundStyle(.secondary)
                            let count = library.boxAlbumIDs[box.id]?.count ?? 0
                            Text("\(count) album\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .contextMenu { Button("Move Empty Box Set to Recently Deleted", role: .destructive) { onDelete(box) } }
            }
            .overlay {
                if library.isReady && boxes.isEmpty {
                    ContentUnavailableView {
                        Label(library.boxSets.isEmpty ? "No Box Sets" : "No Matching Box Sets", systemImage: "shippingbox")
                    } description: {
                        Text(library.boxSets.isEmpty ? "Use Add Box Set to group albums at a shared physical location." : "Try another title, edition or location.")
                    } actions: {
                        if !search.isEmpty { Button("Clear Search") { search = "" } }
                    }
                }
            }
        }
    }
}

@MainActor func boxLocation(_ box: BoxSet, library: LibraryStore) -> String {
    guard let location = library.locations.first(where: { $0.id == box.physicalLocationID }) else { return "Location unavailable" }
    return LocationBrowseSummary(locations: library.locations).path(of: location)
}

struct BoxSetIdentityArtwork: View {
    @ObservedObject var library: LibraryStore
    let boxID: BoxSetID
    let size: CGFloat
    var body: some View {
        Group {
            if let first = library.boxAlbumIDs[boxID]?.first, let path = library.albumFrontArtworkPaths[first] {
                AlbumArtworkImage(path: path).help("Cover from the first member album, not separate box artwork")
            } else {
                Image(systemName: "shippingbox").font(.system(size: size * 0.4))
                    .foregroundStyle(Color.accentColor).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.1))
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.16))
            .accessibilityHidden(true)
    }
}
