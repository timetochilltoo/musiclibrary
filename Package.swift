// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MusicLibrary",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "MusicDomain", targets: ["MusicDomain"]),
        .library(name: "MusicPersistence", targets: ["MusicPersistence"]),
        .library(name: "MusicApplication", targets: ["MusicApplication"]),
        .library(name: "MusicReadOnlyClient", targets: ["MusicReadOnlyClient"]),
        .library(name: "MusicLibraryPadShell", targets: ["MusicLibraryPadShell"]),
        .library(name: "MusicUIComponents", targets: ["MusicUIComponents"]),
        .executable(name: "MusicLibraryMac", targets: ["MusicLibraryMac"]),
        .executable(name: "MusicLibraryPad", targets: ["MusicLibraryPad"])
    ],
    targets: [
        .target(name: "MusicDomain"),
        .target(
            name: "MusicPersistence",
            dependencies: ["MusicDomain"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "MusicApplication",
            dependencies: ["MusicDomain", "MusicPersistence"]
        ),
        .target(name: "MusicReadOnlyClient"),
        .target(name: "MusicLibraryPadShell", dependencies: ["MusicReadOnlyClient"]),
        .executableTarget(name: "MusicLibraryPad", dependencies: ["MusicLibraryPadShell"]),
        .target(
            name: "MusicUIComponents",
            dependencies: ["MusicDomain"]
        ),
        .executableTarget(
            name: "MusicLibraryMac",
            dependencies: ["MusicDomain", "MusicApplication", "MusicUIComponents"]
        ),
        .testTarget(name: "MusicDomainTests", dependencies: ["MusicDomain"]),
        .testTarget(name: "MusicPersistenceTests", dependencies: ["MusicDomain", "MusicPersistence"]),
        .testTarget(name: "MusicApplicationTests", dependencies: ["MusicDomain", "MusicApplication"]),
        .testTarget(name: "MusicReadOnlyClientTests", dependencies: ["MusicReadOnlyClient"])
    ]
)
