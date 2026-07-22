import SwiftUI
import MusicReadOnlyClient

public struct PadLibraryView: View {
    @State private var snapshotStatus = "No verified snapshot loaded"
    @State private var mappings: [SMBRootMapping] = []
    @State private var sourceDirectory: URL?
    @State private var isSelectingSnapshotSource = false
    @State private var isSelectingSMBRoot = false
    @State private var rootID = ""
    @State private var message: String?
    private let client: SnapshotClient
    private let mappingStore: SMBRootMappingStore
    private let sourceStore: SnapshotSourceStore
    private let snapshotDirectory: URL

    public init(snapshotDirectory: URL, mappingStoreURL: URL, sourceStoreURL: URL? = nil) {
        self.snapshotDirectory = snapshotDirectory
        client = SnapshotClient(cacheDirectory: snapshotDirectory)
        mappingStore = SMBRootMappingStore(url: mappingStoreURL)
        sourceStore = SnapshotSourceStore(url: sourceStoreURL ?? mappingStoreURL.deletingLastPathComponent().appending(path: "snapshot-source.bookmark"))
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Catalogue") {
                    Text(snapshotStatus)
                    Text("Read-only companion").foregroundStyle(.secondary)
                    if let sourceDirectory {
                        Text(sourceDirectory.path).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Choose the published snapshot folder to refresh.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Choose snapshot source") { isSelectingSnapshotSource = true }
                    Button("Refresh snapshot") { refreshSnapshot() }.disabled(sourceDirectory == nil)
                }
                Section("SMB music roots") {
                    if mappings.isEmpty { Text("No device-local SMB mappings").foregroundStyle(.secondary) }
                    ForEach(mappings, id: \.publishedRootID) { mapping in
                        VStack(alignment: .leading) {
                            Text(mapping.publishedRootID)
                            Text(mapping.localURL.path).font(.caption).foregroundStyle(.secondary)
                        }
                    }.onDelete(perform: removeMappings)
                    TextField("Published root ID", text: $rootID)
                    Button("Choose SMB root") { isSelectingSMBRoot = true }.disabled(rootID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Music Library")
            .task { loadState() }
            .fileImporter(isPresented: $isSelectingSnapshotSource, allowedContentTypes: [.folder]) { result in
                selectSnapshotSource(result)
            }
            .fileImporter(isPresented: $isSelectingSMBRoot, allowedContentTypes: [.folder]) { result in
                selectSMBRoot(result)
            }
            .alert("Music Library", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private func loadState() {
        mappings = (try? mappingStore.mappings()) ?? []
        sourceDirectory = try? sourceStore.selectedDirectory()
        snapshotStatus = FileManager.default.fileExists(atPath: snapshotDirectory.appending(path: "manifest.json").path) ? "Verified local snapshot available" : "No verified snapshot loaded"
    }

    private func selectSnapshotSource(_ result: Result<URL, Error>) {
        do {
            let directory = try result.get()
            try sourceStore.set(selectedDirectory: directory)
            sourceDirectory = directory
            message = "Snapshot source saved. Refresh when ready."
        } catch { message = "Could not save snapshot source: \(error.localizedDescription)" }
    }

    private func selectSMBRoot(_ result: Result<URL, Error>) {
        do {
            let directory = try result.get()
            try mappingStore.set(publishedRootID: rootID.trimmingCharacters(in: .whitespacesAndNewlines), selectedDirectory: directory)
            rootID = ""
            mappings = try mappingStore.mappings()
        } catch { message = "Could not save SMB root: \(error.localizedDescription)" }
    }

    private func refreshSnapshot() {
        guard let sourceDirectory else { return }
        let gainedAccess = sourceDirectory.startAccessingSecurityScopedResource()
        defer { if gainedAccess { sourceDirectory.stopAccessingSecurityScopedResource() } }
        do {
            message = try client.update(from: sourceDirectory) ? "Snapshot updated." : "Already using the latest verified snapshot."
            loadState()
        } catch { message = "Snapshot refresh failed; the prior verified cache remains in use. \(error.localizedDescription)" }
    }

    private func removeMappings(at offsets: IndexSet) {
        do {
            for offset in offsets { try mappingStore.remove(publishedRootID: mappings[offset].publishedRootID) }
            mappings = try mappingStore.mappings()
        } catch { message = "Could not remove SMB root: \(error.localizedDescription)" }
    }
}
