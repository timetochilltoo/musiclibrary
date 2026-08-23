#!/usr/bin/env swift

import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: build-icns.swift ICONSET_DIRECTORY OUTPUT\n".utf8))
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

// Modern ICNS files may store PNG payloads directly. Building the container
// here avoids an iconutil encoder regression seen on current macOS releases,
// while retaining the standard chunk types understood by Finder and Dock.
let chunks: [(type: String, filename: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func fourCC(_ value: String) throws -> Data {
    guard let data = value.data(using: .ascii), data.count == 4 else {
        throw NSError(domain: "MusicLibraryIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid ICNS chunk type: \(value)"])
    }
    return data
}

func bigEndianUInt32(_ value: Int) throws -> Data {
    guard let encoded = UInt32(exactly: value) else {
        throw NSError(domain: "MusicLibraryIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "ICNS file is too large"])
    }
    var bigEndian = encoded.bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}

do {
    var payload = Data()
    for chunk in chunks {
        let png = try Data(contentsOf: iconsetURL.appendingPathComponent(chunk.filename))
        payload.append(try fourCC(chunk.type))
        payload.append(try bigEndianUInt32(png.count + 8))
        payload.append(png)
    }

    var icns = Data()
    icns.append(try fourCC("icns"))
    icns.append(try bigEndianUInt32(payload.count + 8))
    icns.append(payload)
    try icns.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Could not build ICNS: \(error.localizedDescription)\n".utf8))
    exit(1)
}
