import SwiftUI
import MusicDomain

/// Reads the published catalogue snapshot only. Repairs remain explicit workflows.
struct LibraryHealthIssuesView: View {
    let issues: [LibraryHealthIssue]
    let activeAlbumIDs: Set<AlbumID>
    let onShowAlbum: (AlbumID) -> Void
    let onShowMusicFolders: () -> Void

    private var groups: [(kind: LibraryHealthKind, issues: [LibraryHealthIssue])] {
        let grouped = Dictionary(grouping: issues, by: \.kind)
        return LibraryHealthKind.allCases.sorted { $0.repairPriority < $1.repairPriority }.compactMap { kind in
            guard let entries = grouped[kind], !entries.isEmpty else { return nil }
            return (kind, entries.sorted {
                let comparison = $0.albumTitle.localizedStandardCompare($1.albumTitle)
                return comparison == .orderedSame ? $0.albumID.description < $1.albumID.description : comparison == .orderedAscending
            })
        }
    }

    var body: some View {
        List {
            Section {
                Text("\(issues.count) recorded issue\(issues.count == 1 ? "" : "s")").font(.headline)
                Text("These are recorded catalogue findings, not a live file check. Viewing this page does not scan, relink or delete files.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Music Folders", systemImage: "externaldrive", action: onShowMusicFolders)
            }
            if issues.isEmpty {
                Section {
                    ContentUnavailableView("No Recorded Issues", systemImage: "checkmark.shield", description: Text("No catalogue issues are currently recorded. This does not verify current folder connectivity."))
                }
            }
            ForEach(groups, id: \.kind) { group in
                Section {
                    ForEach(group.issues) { issue in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(issue.albumTitle).font(.headline).textSelection(.enabled)
                            Text(issue.detail).font(.callout).foregroundStyle(.secondary)
                            Button("Show Album", systemImage: "square.stack") { onShowAlbum(issue.albumID) }
                                .disabled(!activeAlbumIDs.contains(issue.albumID))
                                .accessibilityLabel("Show album \(issue.albumTitle)")
                        }.padding(.vertical, 6)
                    }
                } header: {
                    Text("\(title(for: group.kind)) · \(group.issues.count)")
                }
            }
        }
    }

    private func title(for kind: LibraryHealthKind) -> String {
        switch kind {
        case .missing: "Audio unavailable"
        case .offline: "Music folders unavailable"
        case .partial: "Partially available albums"
        case .duplicate: "Possible duplicates"
        case .missingArtwork: "Missing artwork"
        }
    }
}
