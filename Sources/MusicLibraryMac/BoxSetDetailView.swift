import SwiftUI
import MusicDomain
import MusicApplication

struct BoxSetDetailView: View {
    @ObservedObject var library: LibraryStore
    let boxSet: BoxSet
    let onShowAlbum: (AlbumID) -> Void
    @State private var isOrganizing = false
    @State private var isUpdating = false
    @State private var showsAddMember = false
    @State private var memberToRemove: BoxSetMembership?
    @State private var errorMessage: String?
    private var ids: [AlbumID] { library.boxAlbumIDs[boxSet.id] ?? [] }
    private var members: [Album] { BoxSetBrowseSummary.members(ids: ids, albums: library.catalogueAlbums) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 6) {
                        BoxSetIdentityArtwork(library: library, boxID: boxSet.id, size: 88)
                        if let first = ids.first, library.albumFrontArtworkPaths[first] != nil {
                            Text("Member cover").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(boxSet.title).font(.largeTitle.bold()).textSelection(.enabled)
                        if let edition = boxSet.editionLabel, !edition.isEmpty { Text(edition).foregroundStyle(.secondary).textSelection(.enabled) }
                        Label(boxLocation(boxSet, library: library), systemImage: "archivebox").foregroundStyle(.secondary).textSelection(.enabled)
                        Text("\(members.count) album\(members.count == 1 ? "" : "s") · Members inherit this physical location").font(.callout)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(20).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
                ViewThatFits(in: .horizontal) {
                    HStack { actions; Spacer() }
                    VStack(alignment: .leading, spacing: 12) { actions }
                }
                if let errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        HStack {
                            Button("Refresh Contents") { refresh() }.disabled(isUpdating)
                            Button("Dismiss") { self.errorMessage = nil }.disabled(isUpdating)
                        }
                    }
                }
                if members.isEmpty {
                    ContentUnavailableView("No Member Albums", systemImage: "shippingbox", description: Text("Add an existing album to start this box set. Removing a member never deletes its album."))
                } else {
                    if isOrganizing { Text("Move albums earlier or later in the box order. Remove asks where to store the album next; it does not delete it.").font(.caption).foregroundStyle(.secondary) }
                    LazyVStack(spacing: 12) {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, album in
                            HStack(spacing: 12) {
                                Button { onShowAlbum(album.id) } label: {
                                    HStack(spacing: 14) {
                                        Text(String(index + 1)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 24)
                                        AlbumArtworkImage(path: library.albumFrontArtworkPaths[album.id]).frame(width: 68, height: 68).clipShape(RoundedRectangle(cornerRadius: 9))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(album.displayTitle).font(.headline)
                                            if let artist = library.albumBrowseSummaries[album.id]?.artistDisplayName { Text(artist).font(.callout).foregroundStyle(.secondary) }
                                            if let year = album.releaseYear { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        if !isOrganizing { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityHint("Open album details").disabled(isUpdating)
                                if isOrganizing {
                                    VStack(spacing: 8) {
                                        HStack(spacing: 8) {
                                            Button("Move Earlier", systemImage: "arrow.up") { move(album.id, earlier: true) }.disabled(index == 0 || isUpdating)
                                            Button("Move Later", systemImage: "arrow.down") { move(album.id, earlier: false) }.disabled(index == members.count - 1 || isUpdating)
                                        }
                                        Button("Remove from Box…", systemImage: "minus.circle") {
                                            memberToRemove = .init(album: album, boxSetID: boxSet.id, position: index + 1)
                                        }.disabled(isUpdating)
                                    }.labelStyle(.iconOnly).controlSize(.small)
                                }
                            }.padding(14).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }.padding(24).padding(.bottom, 32)
        }
        .sheet(isPresented: $showsAddMember) { AddBoxMemberEditor(library: library, boxSet: boxSet, onAdded: {}) }
        .sheet(item: $memberToRemove) { member in RemoveBoxMemberEditor(library: library, boxSet: boxSet, member: member, onRemoved: {}) }
    }

    @ViewBuilder private var actions: some View {
        Button("Add Existing Album…", systemImage: "plus") { showsAddMember = true }.disabled(isUpdating)
        Toggle("Organize Albums", isOn: $isOrganizing).toggleStyle(.checkbox).disabled(isUpdating)
        if isUpdating { ProgressView().controlSize(.small); Text("Updating box…").font(.caption).foregroundStyle(.secondary) }
    }

    private func move(_ albumID: AlbumID, earlier: Bool) {
        guard !isUpdating, let index = ids.firstIndex(of: albumID) else { return }
        let neighbor = index + (earlier ? -1 : 1)
        guard ids.indices.contains(neighbor) else { return }
        let neighborID = ids[neighbor]
        isUpdating = true
        let boxID = boxSet.id
        let expected = ids
        Task {
            defer { isUpdating = false }
            do { try await library.reorderAlbum(albumID, in: boxID, adjacentTo: neighborID, expectedAlbumIDs: expected); errorMessage = nil }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func refresh() {
        guard !isUpdating else { return }
        isUpdating = true
        Task {
            defer { isUpdating = false }
            do { try await library.reload(); errorMessage = nil }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
