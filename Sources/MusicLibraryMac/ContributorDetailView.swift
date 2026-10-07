import SwiftUI
import MusicDomain
import MusicApplication

struct ContributorIdentityAvatar: View {
    let name: String
    var size: CGFloat = 48
    private var initials: String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.22))
            .accessibilityHidden(true)
    }
}

struct ContributorDetailView: View {
    @ObservedObject var library: LibraryStore
    let contributor: Contributor
    @Binding var selectedRole: ContributorRole?
    let onShowAlbum: (AlbumID) -> Void
    @State private var contributorToEdit: Contributor?
    private var summary: ContributorBrowseSummary { library.contributorBrowseSummaries[contributor.id] ?? .init() }
    private var albums: [Album] {
        let ids = summary.albumIDs(role: selectedRole)
        return library.catalogueAlbums.filter { ids.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    ContributorIdentityAvatar(name: contributor.name, size: 88)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(contributor.name).font(.largeTitle.bold()).textSelection(.enabled)
                        if let sort = contributor.sortName, sort != contributor.name {
                            Text("Sort name: \(sort)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Text(summary.roles.isEmpty ? "No active credits" : summary.roles.map(\.displayName).joined(separator: " · "))
                            .foregroundStyle(.secondary)
                        Label("\(summary.albumIDs().count) credited album\(summary.albumIDs().count == 1 ? "" : "s")", systemImage: "square.stack")
                            .font(.callout)
                        Button("Correct Shared Name…", systemImage: "pencil") { contributorToEdit = contributor }
                            .help("Correct this contributor’s catalogue name wherever this identity is credited")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Credited Albums").font(.title2.bold())
                    Picker("Credit role", selection: $selectedRole) {
                        Text("All Roles (\(summary.albumIDs().count))").tag(Optional<ContributorRole>.none)
                        ForEach(summary.roles, id: \.self) { role in
                            Text("\(role.displayName) (\(summary.albumIDs(role: role).count))").tag(Optional(role))
                        }
                    }.pickerStyle(.menu).frame(maxWidth: 350, alignment: .leading)
                    Text("Album and track credits are included. Each album appears once.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if albums.isEmpty {
                    ContentUnavailableView {
                        Label(selectedRole == nil ? "No Active Album Credits" : "No Albums for This Role", systemImage: "person.crop.square")
                    } description: {
                        Text(selectedRole == nil ? "Add an album or track credit to connect this contributor to your collection." : "Choose another role to see this contributor’s albums.")
                    } actions: {
                        if selectedRole != nil { Button("Show All Roles") { selectedRole = nil } }
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(albums) { album in
                            Button { onShowAlbum(album.id) } label: {
                                HStack(alignment: .top, spacing: 16) {
                                    AlbumArtworkImage(path: library.albumFrontArtworkPaths[album.id])
                                        .frame(width: 76, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(album.displayTitle).font(.headline)
                                        if let artist = library.albumBrowseSummaries[album.id]?.artistDisplayName { Text(artist).foregroundStyle(.secondary) }
                                        Text(ContributorRole.allCases.filter { summary.albumRoles[album.id]?.contains($0) == true }.map(\.displayName).joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                        if let year = album.releaseYear { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                                }
                                .padding(14)
                                .contentShape(Rectangle())
                                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Open album details")
                        }
                    }
                }
            }.padding(24).padding(.bottom, 32)
        }
        .onChange(of: summary.roles) { _, roles in
            if let selectedRole, !roles.contains(selectedRole) { self.selectedRole = nil }
        }
        .sheet(item: $contributorToEdit) { captured in
            EditContributorEditor(library: library, contributor: captured, onSaved: {})
        }
    }
}
