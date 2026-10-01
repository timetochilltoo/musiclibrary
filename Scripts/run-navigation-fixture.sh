#!/bin/zsh
set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
cd "${repository_directory}"

# Always build Debug and resolve its current output. A historical binary might
# ignore fixture flags and start the live library; current Release refuses them.
swift build -c debug --product MusicLibraryMac
navigation_binary_directory="$(swift build -c debug --show-bin-path)"
navigation_fixture_directory="$(mktemp -d "${TMPDIR:-/tmp}/musiclibrary-navigation.XXXXXX")"
navigation_fixture_app="${navigation_fixture_directory}/Music Library Navigation Fixture.app"
mkdir -p "${navigation_fixture_app}/Contents/MacOS"
cp Packaging/NavigationFixture-Info.plist "${navigation_fixture_app}/Contents/Info.plist"
ditto "${navigation_binary_directory}/MusicLibraryMac" "${navigation_fixture_app}/Contents/MacOS/MusicLibraryMac"
codesign --force --sign - "${navigation_fixture_app}"
codesign --verify --deep --strict "${navigation_fixture_app}"
open -n "${navigation_fixture_app}" --args --navigation-fixture
echo "Opened disposable fixture: ${navigation_fixture_app}"
