import SwiftUI
import MusicApplication
import MusicDomain
import UniformTypeIdentifiers

struct MusicFolderScanControls: View {
    @ObservedObject var library: LibraryStore
    let root: StorageRoot
    let latestBatch: ImportBatch?
    let onReview: (ImportBatchID) -> Void
    @State private var isStarting = false
    @State private var isCheckingAccess = false
    @State private var errorMessage: String?
    @State private var showsRenewalPicker = false
    @State private var renewalStatus: String?

    private var activeBatch: ImportBatch? {
        library.importBatches.first { $0.storageRootID == root.id && $0.status == .scanning }
    }
    private var isBusy: Bool { isStarting || isCheckingAccess || activeBatch != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Use", selection: Binding(get: { root.scope }, set: { scope in
                Task {
                    do { try await library.updateStorageRootScope(root.id, to: scope) }
                    catch { errorMessage = error.localizedDescription }
                }
            })) {
                ForEach(StorageRootScope.allCases, id: \.self) { scope in Text(scope.displayName).tag(scope) }
            }
            .pickerStyle(.menu).disabled(isBusy)
            HStack {
                Button(latestBatch == nil ? "Scan Folder" : "Rescan Folder", systemImage: "arrow.clockwise") {
                    start { try await library.startImportScan(rootID: root.id) }
                }
                .disabled(root.status != .available || isBusy)
                if let batch = activeBatch ?? latestBatch {
                    Button("Review Scan", systemImage: "list.bullet.rectangle") { onReview(batch.id) }
                        .disabled(isStarting || isCheckingAccess)
                }
                Button("Check Access", systemImage: "folder.badge.questionmark") { checkAccess() }
                    .disabled(isBusy)
                Button("Renew Access…") { showsRenewalPicker = true }
                    .disabled(isBusy)
                    .help("Select the same registered folder to renew its access permission.")
            }
            if isStarting {
                ProgressView("Starting scan…").controlSize(.small)
            } else if isCheckingAccess {
                ProgressView("Checking folder access…").controlSize(.small)
            } else if let batch = activeBatch {
                ProgressView("Scanning folder…").controlSize(.small)
                if let progress = library.importScanProgress[batch.id] {
                    Text("\(progress.examinedItemCount) items checked · \(progress.audioCandidateCount) audio files found")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let batch = latestBatch {
                Text("\(batch.status.rawValue.capitalized) · \(batch.candidateCount) audio files · \(batch.errorCount) errors")
                    .font(.caption).foregroundStyle(.secondary)
                if let failure = batch.errorSummary { Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            } else {
                Text("Not scanned yet. Scan this folder, then review the releases you want to add.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if root.status != .available {
                Text("Reconnect the drive and choose Check Access, or use Renew Access to select this same registered folder: \(root.lastKnownPath)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let renewalStatus { Text(renewalStatus).font(.callout).foregroundStyle(.secondary) }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
            }
            #if DEBUG
            if Bundle.main.bundleIdentifier == "com.timetochilltoo.MusicLibraryNavigationFixture",
               ProcessInfo.processInfo.arguments.contains("--registered-folder-fixture") {
                Button("Show Synthetic Folder Scan Error") {
                    start {
                        throw NSError(domain: "FolderScanFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Synthetic folder scan failure — no scan or file operation was run."])
                    }
                }.font(.caption).disabled(isBusy)
            }
            #endif
        }
        .fileImporter(isPresented: $showsRenewalPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): renewAccess(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func start(_ operation: @escaping () async throws -> ImportBatchID) {
        guard !isBusy else { return }
        errorMessage = nil
        isStarting = true
        Task {
            defer { isStarting = false }
            do { onReview(try await operation()) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func checkAccess() {
        guard !isBusy else { return }
        errorMessage = nil
        isCheckingAccess = true
        Task {
            defer { isCheckingAccess = false }
            do { try await library.refreshStorageRootAccess() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func renewAccess(_ url: URL) {
        guard !isBusy else { return }
        errorMessage = nil
        renewalStatus = nil
        isCheckingAccess = true
        Task {
            defer { isCheckingAccess = false }
            do {
                try await library.renewStorageRootAccess(root.id, selecting: url)
                renewalStatus = "Folder access renewed. Existing album and file references were kept; no scan was started."
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
