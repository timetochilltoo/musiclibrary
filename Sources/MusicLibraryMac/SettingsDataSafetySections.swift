import SwiftUI
import MusicApplication

private struct SettingsTransferFeedback: View {
    let state: SettingsTransferTasks.State
    let progress: String

    var body: some View {
        switch state {
        case .idle: EmptyView()
        case .running: ProgressView(progress).controlSize(.small)
        case let .succeeded(message):
            Label(message, systemImage: "checkmark.circle").font(.callout).textSelection(.enabled)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.red).textSelection(.enabled)
        }
    }
}

struct SettingsBackupRecoverySections: View {
    let databaseStatus: String
    let archiveStatus: String?
    let canBackUpDatabase: Bool
    let isBusy: Bool
    let databaseTransfer: SettingsTransferTasks.State
    let transfersBusy: Bool
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
        .disabled(isBusy || transfersBusy)

        Section {
            DisclosureGroup("Database-only backup (advanced)", isExpanded: $showsDatabaseOnly) {
                Text("Contains catalogue records only, not managed artwork or source audio. This is not a complete catalogue recovery archive.")
                    .font(.callout).foregroundStyle(.secondary)
                if databaseTransfer != .running { Text(databaseStatus).font(.caption).foregroundStyle(.secondary) }
                SettingsTransferFeedback(state: databaseTransfer, progress: "Creating verified database backup…")
                Text("Database backups use the MasterBackups folder inside the iPad sharing destination.")
                    .font(.caption).foregroundStyle(.secondary)
                if !canBackUpDatabase {
                    Text("To enable database-only backup, choose a sharing folder in iPad Sharing. Complete archives do not require sharing to be configured.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(databaseTransfer.failure == nil ? "Back Up Database Only" : "Retry Database Backup", action: onBackUpDatabase)
                    .disabled(!canBackUpDatabase || isBusy || transfersBusy)
                Button("Restore Database-only Backup…", role: .destructive, action: onRestoreDatabase)
                    .disabled(isBusy || transfersBusy)
            }
        } header: {
            Text("Other Backup Options")
        }
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
    let transfer: SettingsTransferTasks.State
    let isBusy: Bool
    let onChooseFolder: () -> Void
    let onUpdate: () -> Void

    var body: some View {
        Section {
            Text("Share a read-only catalogue with your iPad. Source audio is not copied, and the shared library is not a recovery backup.")
                .font(.callout).foregroundStyle(.secondary)
            if transfer != .running { Text(status).foregroundStyle(.secondary) }
            if let destinationPath {
                Text(destinationPath).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).textSelection(.enabled)
            }
            if let lastPublishedAt {
                Text("Last successful update \(lastPublishedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsTransferFeedback(state: transfer, progress: "Updating shared library…")
            if transfer != .running, let failure, failure != transfer.failure {
                Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            Button("Choose Sharing Folder…", action: onChooseFolder)
                .disabled(isBusy)
            Button(transfer.failure != nil || failure != nil ? "Retry Update" : "Update Shared Library", action: onUpdate)
                .buttonStyle(.borderedProminent).disabled(destinationPath == nil || isBusy)
            DisclosureGroup("Technical details") {
                Text("Catalogue revision \(revision) · last shared \(publishedRevision.map(String.init) ?? "never")\(isPending ? " · pending" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Label("iPad Sharing", systemImage: "ipad.and.iphone")
        }
    }
}
