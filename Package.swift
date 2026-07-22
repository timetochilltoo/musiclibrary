// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MusicLibrary",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MusicDomain", targets: ["MusicDomain"]),
        .library(name: "MusicPersistence", targets: ["MusicPersistence"]),
        .library(name: "MusicApplication", targets: ["MusicApplication"]),
        .library(name: "MusicUIComponents", targets: ["MusicUIComponents"]),
        .executable(name: "MusicLibraryMac", targets: ["MusicLibraryMac"])
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
        .target(
            name: "MusicUIComponents",
            dependencies: ["MusicDomain"]
        ),
        .executableTarget(
            name: "MusicLibraryMac",
            dependencies: ["MusicDomain", "MusicApplication", "MusicUIComponents"]
        ),
        .testTarget(name: "MusicDomainTests", dependencies: ["MusicDomain"]),
        .testTarget(name: "MusicPersistenceTests", dependencies: ["MusicDomain", "MusicPersistence"])
    ]
)
