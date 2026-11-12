public enum LibraryLaunchMode: Equatable, Sendable {
    case catalogue, browseFixture, navigationFixture, unavailableFixture

    /// Fixture bundles must remain isolated when Launch Services or UI tools
    /// reopen them without arguments. Unsupported fixture launches fail closed.
    public static func resolve(bundleIdentifier: String?, arguments: [String], supportsFixtures: Bool) -> Self {
        let navigation = bundleIdentifier == "com.timetochilltoo.MusicLibraryNavigationFixture"
            || arguments.contains("--navigation-fixture")
            || arguments.contains("--import-review-fixture")
            || arguments.contains("--empty-library-fixture")
            || arguments.contains("--registered-folder-fixture")
            || arguments.contains("--folder-recovery-fixture")
            || arguments.contains("--folder-recovery-files-fixture")
        let browse = bundleIdentifier == "com.timetochilltoo.MusicLibraryBrowseFixture"
            || arguments.contains("--browse-fixture")
        guard navigation || browse else { return .catalogue }
        guard supportsFixtures else { return .unavailableFixture }
        return navigation ? .navigationFixture : .browseFixture
    }
}
