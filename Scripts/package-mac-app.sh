#!/bin/zsh
set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${repository_directory}/Packaging/MusicLibraryMac-Info.plist")"
app_directory="${repository_directory}/build/Music Library ${version}.app"

cd "${repository_directory}"
swift build -c release --product MusicLibraryMac
binary_directory="$(swift build -c release --show-bin-path)"

mkdir -p "${app_directory}/Contents/MacOS" "${app_directory}/Contents/Resources"
cp "${repository_directory}/Packaging/MusicLibraryMac-Info.plist" "${app_directory}/Contents/Info.plist"
cp "${repository_directory}/Packaging/AppIcon.icns" "${app_directory}/Contents/Resources/AppIcon.icns"
ditto "${binary_directory}/MusicLibraryMac" "${app_directory}/Contents/MacOS/MusicLibraryMac"
codesign --force --sign - "${app_directory}"

echo "Packaged ${app_directory}"
