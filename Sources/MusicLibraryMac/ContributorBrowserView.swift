import SwiftUI
import MusicDomain
import MusicApplication

struct ContributorBrowserView: View {
    @ObservedObject var library: LibraryStore
    @Binding var selection: ContributorID?
    @Binding var search: String
    @Binding var role: ContributorRole?
    private var roles: [ContributorRole] {
        let present = Set(library.contributorBrowseSummaries.values.flatMap(\.roles))
        return ContributorRole.allCases.filter { present.contains($0) }
    }
    private var contributors: [Contributor] {
        ContributorBrowseSummary.matching(library.contributors, summaries: library.contributorBrowseSummaries, query: search, role: role)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Credit role", selection: $role) {
                    Text("All Roles").tag(Optional<ContributorRole>.none)
                    ForEach(roles, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }.pickerStyle(.menu).frame(maxWidth: 300, alignment: .leading)
                Spacer()
                Text("\(contributors.count) contributor\(contributors.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
            Divider()
            List(contributors, selection: $selection) { contributor in
                let summary = library.contributorBrowseSummaries[contributor.id] ?? .init()
                HStack(spacing: 14) {
                    ContributorIdentityAvatar(name: contributor.name)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contributor.name).font(.headline)
                        Text(summary.roles.isEmpty ? "No active credits" : summary.roles.map(\.displayName).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if let sort = contributor.sortName, sort != contributor.name {
                            Text("Sort name: \(sort)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(summary.albumIDs().count) album\(summary.albumIDs().count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .tag(contributor.id)
            }
            .overlay {
                if library.isReady && contributors.isEmpty {
                    ContentUnavailableView {
                        Label(library.contributors.isEmpty ? "No Contributors" : "No Matching Contributors", systemImage: "person.2")
                    } description: {
                        Text(library.contributors.isEmpty ? "Add contributors from an album or track credit." : "Try another name or credit role.")
                    } actions: {
                        if !library.contributors.isEmpty { Button("Clear Search and Role") { search = ""; role = nil } }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Contributor name or sort name")
        .onChange(of: roles) { _, values in if let role, !values.contains(role) { self.role = nil } }
    }
}
