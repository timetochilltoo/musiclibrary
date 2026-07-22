import Foundation
import MusicLibraryPadShell
import SwiftUI

@main
struct MusicLibraryPadApp: App {
    private let storageDirectory: URL

    init() {
        let manager = FileManager.default
        let base = (try? manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? manager.temporaryDirectory
        storageDirectory = base.appending(path: "MusicLibraryPad", directoryHint: .isDirectory)
        try? manager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    var body: some Scene {
        WindowGroup {
            PadLibraryView(
                snapshotDirectory: storageDirectory.appending(path: "SnapshotCache", directoryHint: .isDirectory),
                mappingStoreURL: storageDirectory.appending(path: "SMBRootMappings.json"),
                sourceStoreURL: storageDirectory.appending(path: "SnapshotSource.bookmark")
            )
        }
    }
}
