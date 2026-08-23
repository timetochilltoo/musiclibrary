#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: prepare-app-icon.swift INPUT OUTPUT\n".utf8))
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: inputURL) else {
    FileHandle.standardError.write(Data("Could not read \(inputURL.path)\n".utf8))
    exit(1)
}

let pixels = 1_024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("Could not create icon canvas\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("Could not create icon graphics context\n".utf8))
    exit(1)
}
NSGraphicsContext.current = context
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

// Image generation previews use a visible checkerboard around the artwork.
// Clip to the designed macOS squircle so the committed PNG has real alpha.
let iconBounds = NSRect(x: 66, y: 64, width: 892, height: 896)
NSBezierPath(roundedRect: iconBounds, xRadius: 270, yRadius: 270).addClip()
source.draw(
    in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
    from: NSRect(origin: .zero, size: source.size),
    operation: .sourceOver,
    fraction: 1
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Could not encode icon PNG\n".utf8))
    exit(1)
}
try data.write(to: outputURL, options: .atomic)
