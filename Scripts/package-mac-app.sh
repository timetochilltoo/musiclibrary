#!/bin/zsh
set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
app_directory="${repository_directory}/build/Music Library.app"

cd "${repository_directory}"
swift build -c release --product MusicLibraryMac
binary_directory="$(swift build -c release --show-bin-path)"

mkdir -p "${app_directory}/Contents/MacOS"
cp "${repository_directory}/Packaging/MusicLibraryMac-Info.plist" "${app_directory}/Contents/Info.plist"
ditto "${binary_directory}/MusicLibraryMac" "${app_directory}/Contents/MacOS/MusicLibraryMac"
codesign --force --sign - "${app_directory}"

echo "Packaged ${app_directory}"
