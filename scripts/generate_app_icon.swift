#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: generate_app_icon.swift <output.icns>\n".utf8))
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default
let iconsetURL = outputURL
    .deletingPathExtension()
    .appendingPathExtension("iconset")

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(
    at: iconsetURL,
    withIntermediateDirectories: true
)

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()
    defer {
        image.unlockFocus()
    }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.22
    let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.08, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.14, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.04, alpha: 1)
        ]
    )?.draw(in: background, angle: -45)

    let glow = NSBezierPath(ovalIn: NSRect(
        x: size * 0.16,
        y: size * 0.56,
        width: size * 0.52,
        height: size * 0.32
    ))
    NSColor(calibratedRed: 0.22, green: 0.82, blue: 1, alpha: 0.18).setFill()
    glow.fill()

    let drop = NSBezierPath()
    drop.move(to: NSPoint(x: size * 0.50, y: size * 0.80))
    drop.curve(
        to: NSPoint(x: size * 0.24, y: size * 0.42),
        controlPoint1: NSPoint(x: size * 0.38, y: size * 0.66),
        controlPoint2: NSPoint(x: size * 0.24, y: size * 0.55)
    )
    drop.curve(
        to: NSPoint(x: size * 0.50, y: size * 0.18),
        controlPoint1: NSPoint(x: size * 0.24, y: size * 0.27),
        controlPoint2: NSPoint(x: size * 0.36, y: size * 0.18)
    )
    drop.curve(
        to: NSPoint(x: size * 0.76, y: size * 0.42),
        controlPoint1: NSPoint(x: size * 0.64, y: size * 0.18),
        controlPoint2: NSPoint(x: size * 0.76, y: size * 0.27)
    )
    drop.curve(
        to: NSPoint(x: size * 0.50, y: size * 0.80),
        controlPoint1: NSPoint(x: size * 0.76, y: size * 0.55),
        controlPoint2: NSPoint(x: size * 0.62, y: size * 0.66)
    )
    drop.close()

    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.24, green: 0.88, blue: 1, alpha: 1),
            NSColor(calibratedRed: 0.09, green: 0.52, blue: 1, alpha: 1)
        ]
    )?.draw(in: drop, angle: 90)

    let shine = NSBezierPath(ovalIn: NSRect(
        x: size * 0.39,
        y: size * 0.56,
        width: size * 0.16,
        height: size * 0.16
    ))
    NSColor.white.withAlphaComponent(0.34).setFill()
    shine.fill()

    return image
}

func writePNG(size: CGFloat, fileName: String) throws {
    let image = makeIcon(size: size)

    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(
            domain: "PromptJuiceIcon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not render \(fileName)"]
        )
    }

    try pngData.write(to: iconsetURL.appendingPathComponent(fileName))
}

let outputs: [(CGFloat, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for output in outputs {
    try writePNG(size: output.0, fileName: output.1)
}

try? fileManager.removeItem(at: outputURL)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    iconsetURL.path,
    "-o",
    outputURL.path
]

try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    exit(process.terminationStatus)
}

try? fileManager.removeItem(at: iconsetURL)
