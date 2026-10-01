import Testing
import MusicApplication

@Suite("Fixture launch safety")
struct LibraryLaunchModeTests {
    @Test("Fixture bundle identities remain isolated on argument-free relaunch")
    func identityFallback() {
        #expect(LibraryLaunchMode.resolve(bundleIdentifier: "com.timetochilltoo.MusicLibraryNavigationFixture", arguments: [], supportsFixtures: true) == .navigationFixture)
        #expect(LibraryLaunchMode.resolve(bundleIdentifier: "com.timetochilltoo.MusicLibraryBrowseFixture", arguments: [], supportsFixtures: true) == .browseFixture)
    }

    @Test("Release builds refuse fixture bundles and flags instead of opening the live catalogue")
    func failClosed() {
        for identifier in ["com.timetochilltoo.MusicLibraryNavigationFixture", "com.timetochilltoo.MusicLibraryBrowseFixture"] {
            #expect(LibraryLaunchMode.resolve(bundleIdentifier: identifier, arguments: [], supportsFixtures: false) == .unavailableFixture)
        }
        for flag in ["--navigation-fixture", "--browse-fixture"] {
            #expect(LibraryLaunchMode.resolve(bundleIdentifier: nil, arguments: [flag], supportsFixtures: false) == .unavailableFixture)
        }
    }

    @Test("Normal production launch is unaffected; explicit navigation fixtures take precedence")
    func normalLaunch() {
        for supported in [true, false] {
            #expect(LibraryLaunchMode.resolve(bundleIdentifier: "com.timetochilltoo.MusicLibraryMac", arguments: [], supportsFixtures: supported) == .catalogue)
        }
        #expect(LibraryLaunchMode.resolve(bundleIdentifier: nil, arguments: ["--browse-fixture", "--navigation-fixture"], supportsFixtures: true) == .navigationFixture)
    }
}
