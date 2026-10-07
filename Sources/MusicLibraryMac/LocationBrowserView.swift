import SwiftUI
import MusicDomain
import MusicApplication

struct LocationBrowserView: View {
    @ObservedObject var library: LibraryStore
    let onShowAlbum: (AlbumID) -> Void
    let onRename: (PhysicalLocation) -> Void
    let onMove: (PhysicalLocation) -> Void
    let onDelete: (PhysicalLocation) -> Void
    @State private var selection: PhysicalLocationID?
    @State private var search = ""
    private var hierarchy: LocationBrowseSummary { .init(locations: library.locations) }

    var body: some View {
        RetainedBrowseWorkspace(showsDetail: selection != nil) {
            VStack(spacing: 0) {
                HStack {
                    Text("\(library.locations.count) location\(library.locations.count == 1 ? "" : "s")").font(.callout)
                    Spacer()
                    TextField("Search location paths", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                }.padding(16)
                List {
                    ForEach(hierarchy.ordered.filter { search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hierarchy.path(of: $0).localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespacesAndNewlines)) }) { location in
                        Button { selection = location.id } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "archivebox").font(.title2).foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(location.name).font(.headline)
                                    if location.parentID != nil { Text(hierarchy.path(of: location)).font(.caption).foregroundStyle(.secondary) }
                                    Text(counts(location)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }.padding(.vertical, 8)
                                .padding(.leading, CGFloat(max(0, hierarchy.ancestors(of: location).count - 1)) * 14)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).contextMenu { management(location) }
                    }
                }
                .overlay {
                    if library.isReady && library.locations.isEmpty {
                        ContentUnavailableView("No Locations", systemImage: "archivebox", description: Text("Use Add Location to create a room, cabinet or shelf."))
                    } else if !search.isEmpty && !hierarchy.ordered.contains(where: { hierarchy.path(of: $0).localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
                        ContentUnavailableView {
                            Label("No Matching Locations", systemImage: "magnifyingglass")
                        } actions: { Button("Clear Search") { search = "" } }
                    }
                }
            }
        } detail: {
            if let location = library.locations.first(where: { $0.id == selection }) {
                locationContents(location)
            }
        }
        .onChange(of: library.locations) { _, locations in
            if let selection, !locations.contains(where: { $0.id == selection }) { self.selection = nil }
        }
    }

    private func counts(_ location: PhysicalLocation) -> String {
        let direct = hierarchy.directAlbums(at: location.id, albums: library.catalogueAlbums).count
        let boxes = hierarchy.boxes(at: location.id, boxSets: library.boxSets)
        let boxed = boxes.reduce(0) { $0 + (library.boxAlbumIDs[$1.id]?.count ?? 0) }
        return "\(direct) standalone · \(boxes.count) box set\(boxes.count == 1 ? "" : "s") · \(boxed) boxed album\(boxed == 1 ? "" : "s")"
    }

    @ViewBuilder private func management(_ location: PhysicalLocation) -> some View {
        Button("Rename…") { onRename(location) }
        Button("Move…") { onMove(location) }
        Divider()
        Button("Delete…", role: .destructive) { onDelete(location) }
    }

    private func locationContents(_ location: PhysicalLocation) -> some View {
        let children = hierarchy.children(of: location.id)
        let direct = hierarchy.directAlbums(at: location.id, albums: library.catalogueAlbums)
        let boxes = hierarchy.boxes(at: location.id, boxSets: library.boxSets)
        let albumsByID = Dictionary(library.catalogueAlbums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Button("All Locations", systemImage: "chevron.left") { selection = nil }
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            ForEach(hierarchy.ancestors(of: location)) { ancestor in
                                if ancestor.id == location.id {
                                    Text(ancestor.name).foregroundStyle(.secondary)
                                } else {
                                    Button(ancestor.name) { selection = ancestor.id }.buttonStyle(.link)
                                }
                                if ancestor.id != location.id { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        Text(hierarchy.path(of: location)).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Text(location.name).font(.largeTitle.bold()).textSelection(.enabled)
                    Text(counts(location)).foregroundStyle(.secondary)
                    Text("Contents at this exact location. Child locations are listed separately.").font(.caption).foregroundStyle(.secondary)
                    if let notes = location.notes, !notes.isEmpty { Text(notes).textSelection(.enabled) }
                    Menu("Manage Location", systemImage: "ellipsis.circle") { management(location) }
                        .fixedSize(horizontal: true, vertical: false)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
                if !children.isEmpty {
                    Text("Inside This Location").font(.title2.bold())
                    ForEach(children) { child in
                        Button { selection = child.id } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(child.name, systemImage: "archivebox").font(.headline)
                                Text(counts(child)).font(.caption).foregroundStyle(.secondary)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
                Text("Box Sets (\(boxes.count))").font(.title2.bold())
                if boxes.isEmpty { Text("No box sets stored here.").foregroundStyle(.secondary) }
                ForEach(boxes) { box in
                    DisclosureGroup {
                        LazyVStack(spacing: 10) {
                            ForEach(library.boxAlbumIDs[box.id] ?? [], id: \.self) { id in
                                if let album = albumsByID[id] { albumRow(album) }
                            }
                        }.padding(.top, 10)
                        if (library.boxAlbumIDs[box.id] ?? []).isEmpty { Text("This box set has no active albums.").foregroundStyle(.secondary) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(box.title, systemImage: "shippingbox").font(.headline)
                            if let edition = box.editionLabel { Text(edition).font(.caption).foregroundStyle(.secondary) }
                            Text("\(library.boxAlbumIDs[box.id]?.count ?? 0) albums").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(16).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                }
                Text("Standalone Albums (\(direct.count))").font(.title2.bold())
                if direct.isEmpty { Text("No standalone albums stored here.").foregroundStyle(.secondary) }
                LazyVStack(spacing: 10) { ForEach(direct) { album in albumRow(album) } }
            }.padding(24).padding(.bottom, 32)
        }
    }

    private func albumRow(_ album: Album) -> some View {
        Button { onShowAlbum(album.id) } label: {
            HStack(spacing: 14) {
                AlbumArtworkImage(path: library.albumFrontArtworkPaths[album.id]).frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(album.displayTitle).font(.headline)
                    if let artist = library.albumBrowseSummaries[album.id]?.artistDisplayName { Text(artist).font(.callout).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }.padding(12).contentShape(Rectangle())
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityHint("Open album details")
    }
}
