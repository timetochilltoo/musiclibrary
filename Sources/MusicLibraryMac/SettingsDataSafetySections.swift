import SwiftUI

struct SettingsBackupRecoverySections: View {
    let databaseStatus: String
    let archiveStatus: String?
    let canBackUpDatabase: Bool
    let isBusy: Bool
    let onExportArchive: () -> Void
    let onRestoreArchive: () -> Void
    let onBackUpDatabase: () -> Void
    let onRestoreDatabase: () -> Void
    @State private var showsDatabaseOnly = false

    var body: some View {
        Section {
            Text("Recommended for catalogue recovery")
                .font(.headline)
            Text("A complete archive contains the verified catalogue database and managed artwork. Source audio is not included; back up your music files separately.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Export Complete Catalogue Archive…", systemImage: "archivebox", action: onExportArchive)
                .buttonStyle(.borderedProminent)
            Button("Restore Complete Catalogue Archive…", systemImage: "arrow.counterclockwise.circle", role: .destructive, action: onRestoreArchive)
            Text("Restore verifies the archive and creates a local recovery archive of the current catalogue before replacement.")
                .font(.caption).foregroundStyle(.secondary)
            if isBusy { ProgressView("Working on catalogue recovery data…").controlSize(.small) }
            if let archiveStatus { Text(archiveStatus).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Label("Complete Catalogue Archive", systemImage: "archivebox")
        }
        .disabled(isBusy)

        Section {
            DisclosureGroup("Database-only backup (advanced)", isExpanded: $showsDatabaseOnly) {
                Text("Contains catalogue records only, not managed artwork or source audio. This is not a complete catalogue recovery archive.")
                    .font(.callout).foregroundStyle(.secondary)
                Text(databaseStatus).font(.caption).foregroundStyle(.secondary)
                Text("Database backups use the MasterBackups folder inside the iPad sharing destination.")
                    .font(.caption).foregroundStyle(.secondary)
                if !canBackUpDatabase {
                    Text("To enable database-only backup, choose a sharing folder in iPad Sharing. Complete archives do not require sharing to be configured.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Back Up Database Only", action: onBackUpDatabase).disabled(!canBackUpDatabase)
                Button("Restore Database-only Backup…", role: .destructive, action: onRestoreDatabase)
            }
        } header: {
            Text("Other Backup Options")
        }
        .disabled(isBusy)
    }
}

struct SettingsSharingSection: View {
    let status: String
    let destinationPath: String?
    let revision: Int64
    let publishedRevision: Int64?
    let isPending: Bool
    let lastPublishedAt: Date?
    let failure: String?
    let onChooseFolder: () -> Void
    let onUpdate: () -> Void

    var body: some View {
        Section {
            Text("Share a read-only catalogue with your iPad. Source audio is not copied, and the shared library is not a recovery backup.")
                .font(.callout).foregroundStyle(.secondary)
            Text(status).foregroundStyle(.secondary)
            if let destinationPath {
                Text(destinationPath).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).textSelection(.enabled)
            }
            if let lastPublishedAt {
                Text("Last successful update \(lastPublishedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let failure { Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            Button("Choose Sharing Folder…", action: onChooseFolder)
            Button(failure == nil ? "Update Shared Library" : "Retry Update", action: onUpdate)
                .buttonStyle(.borderedProminent).disabled(destinationPath == nil)
            DisclosureGroup("Technical details") {
                Text("Catalogue revision \(revision) · last shared \(publishedRevision.map(String.init) ?? "never")\(isPending ? " · pending" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Label("iPad Sharing", systemImage: "ipad.and.iphone")
        }
    }
}
