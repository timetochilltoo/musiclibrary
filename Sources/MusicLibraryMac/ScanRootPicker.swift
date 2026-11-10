import SwiftUI
import MusicApplication
import MusicDomain
import UniformTypeIdentifiers

struct ScanRootPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    var onStarted: (ImportBatchID) -> Void = { _ in }
    @State private var showsChildFolderPicker = false
    @State private var isStarting = false
    @State private var errorMessage: String?

    private var hasAvailableFolder: Bool { library.storageRoots.contains { $0.status == .available } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose a registered music folder to scan, or select an album subfolder inside one.")
                    .foregroundStyle(.secondary)
                Text("Review the scan before adding releases. Source audio stays in place.")
                    .font(.caption).foregroundStyle(.secondary)
                #if DEBUG
                if Bundle.main.bundleIdentifier == "com.timetochilltoo.MusicLibraryNavigationFixture",
                   ProcessInfo.processInfo.arguments.contains("--registered-folder-fixture") {
                    Button("Show Synthetic Scan Error") {
                        start {
                            throw NSError(domain: "ScanEntryFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Synthetic scan startup failure — no scan or file operation was run."])
                        }
                    }.font(.caption)
                }
                #endif
                List(library.storageRoots) { root in
                    Button { start { try await library.startImportScan(rootID: root.id) } } label: {
                        HStack {
                            Image(systemName: "folder").accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(root.displayName).font(.headline)
                                Text(root.lastKnownPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(root.lastKnownPath)
                            }
                            Spacer()
                            Text(root.status == .available ? "Scan" : "Unavailable").font(.callout)
                        }.padding(.vertical, 6)
                    }
                    .disabled(root.status != .available)
                }
                .overlay {
                    if library.storageRoots.isEmpty {
                        ContentUnavailableView("No registered music folders", systemImage: "folder.badge.plus", description: Text("Add a folder in Settings → Music Folders, then return here to scan it."))
                    }
                }
                if !library.storageRoots.isEmpty && !hasAvailableFolder {
                    Text("No folder is available. In Settings → Music Folders, check access or reconnect the drive, then try again.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .navigationTitle("Import Music Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Choose Album Subfolder…", systemImage: "folder") { showsChildFolderPicker = true }
                        .disabled(!hasAvailableFolder)
                }
            }
        }
        .disabled(isStarting)
        .overlay { if isStarting { ProgressView("Starting scan…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) } }
        .interactiveDismissDisabled(isStarting)
        .frame(minWidth: 580, idealWidth: 640, minHeight: 440, idealHeight: 500)
        .fileImporter(isPresented: $showsChildFolderPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): start { try await library.startImportScan(containing: url) }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func start(_ operation: @escaping () async throws -> ImportBatchID) {
        guard !isStarting else { return }
        errorMessage = nil
        isStarting = true
        Task {
            defer { isStarting = false }
            do { let id = try await operation(); onStarted(id); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
