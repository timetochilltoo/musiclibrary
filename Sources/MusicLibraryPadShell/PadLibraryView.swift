import SwiftUI
import MusicReadOnlyClient

public struct PadLibraryView: View {
    @State private var snapshotStatus = "No verified snapshot loaded"
    @State private var mappings: [SMBRootMapping] = []
    private let client: SnapshotClient
    private let mappingStore: SMBRootMappingStore
    private let snapshotDirectory: URL

    public init(snapshotDirectory: URL, mappingStoreURL: URL) {
        self.snapshotDirectory = snapshotDirectory
        client = SnapshotClient(cacheDirectory: snapshotDirectory)
        mappingStore = SMBRootMappingStore(url: mappingStoreURL)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Catalogue") { Text(snapshotStatus); Text("Read-only companion").foregroundStyle(.secondary) }
                Section("SMB music roots") {
                    if mappings.isEmpty { Text("No device-local SMB mappings").foregroundStyle(.secondary) }
                    ForEach(mappings, id: \.publishedRootID) { mapping in VStack(alignment: .leading) { Text(mapping.publishedRootID); Text(mapping.localURL.path).font(.caption).foregroundStyle(.secondary) } }
                }
            }
            .navigationTitle("Music Library")
            .task { mappings = (try? mappingStore.mappings()) ?? []; snapshotStatus = FileManager.default.fileExists(atPath: snapshotDirectory.appending(path: "manifest.json").path) ? "Verified local snapshot available" : "No verified snapshot loaded" }
        }
    }
}
