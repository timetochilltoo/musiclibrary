#!/bin/zsh
set -euo pipefail

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
generated_source="${1:-${repository_directory}/Packaging/AppIcon-source.png}"
master_png="${repository_directory}/Packaging/AppIcon-1024.png"
temporary_directory="$(mktemp -d)"
iconset_directory="${temporary_directory}/AppIcon.iconset"
trap 'rm -rf "${temporary_directory}"' EXIT

swift -module-cache-path "${temporary_directory}/ModuleCache" "${script_directory}/prepare-app-icon.swift" "${generated_source}" "${master_png}"
mkdir -p "${iconset_directory}"

for specification in \
    "icon_16x16.png:16" \
    "icon_16x16@2x.png:32" \
    "icon_32x32.png:32" \
    "icon_32x32@2x.png:64" \
    "icon_128x128.png:128" \
    "icon_128x128@2x.png:256" \
    "icon_256x256.png:256" \
    "icon_256x256@2x.png:512" \
    "icon_512x512.png:512" \
    "icon_512x512@2x.png:1024"
do
    name="${specification%%:*}"
    size="${specification##*:}"
    sips -z "${size}" "${size}" "${master_png}" --out "${iconset_directory}/${name}" >/dev/null
done

swift -module-cache-path "${temporary_directory}/ModuleCache" "${script_directory}/build-icns.swift" "${iconset_directory}" "${repository_directory}/Packaging/AppIcon.icns"

# Validate that the system decoder accepts the generated container. Current
# macOS iconutil can decode this file even on versions where encoding an
# otherwise-valid iconset incorrectly reports "Invalid Iconset".
decoded_directory="${temporary_directory}/Decoded.iconset"
iconutil --convert iconset "${repository_directory}/Packaging/AppIcon.icns" --output "${decoded_directory}"
test -f "${decoded_directory}/icon_512x512@2x.png"
echo "Built and validated Packaging/AppIcon.icns"
