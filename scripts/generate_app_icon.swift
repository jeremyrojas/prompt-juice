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

// Droplet geometry — kept in sync with app/PromptJuice/UI/DropletGeometry.swift.
// This script is standalone (run via `swift scripts/generate_app_icon.swift`),
// so it cannot import the package; the constants are duplicated on purpose.
let dropletTip = CGPoint(x: 0.5, y: 0.1208)
let dropletSegments: [(CGPoint, CGPoint, CGPoint)] = [
    (CGPoint(x: 0.5000, y: 0.1208), CGPoint(x: 0.2083, y: 0.4708), CGPoint(x: 0.2083, y: 0.6667)),
    (CGPoint(x: 0.2083, y: 0.8292), CGPoint(x: 0.3375, y: 0.9333), CGPoint(x: 0.5000, y: 0.9333)),
    (CGPoint(x: 0.6625, y: 0.9333), CGPoint(x: 0.7917, y: 0.8292), CGPoint(x: 0.7917, y: 0.6667)),
    (CGPoint(x: 0.7917, y: 0.4708), CGPoint(x: 0.5000, y: 0.1208), CGPoint(x: 0.5000, y: 0.1208))
]
let dropletFillTop: CGFloat = 0.17
let dropletFillBottom: CGFloat = 0.92

func dropletFraction(_ f: CGPoint, in r: NSRect) -> NSPoint {
    NSPoint(x: r.minX + f.x * r.width, y: r.minY + f.y * r.height)
}

func dropletPath(in r: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: dropletFraction(dropletTip, in: r))
    for segment in dropletSegments {
        path.curve(
            to: dropletFraction(segment.2, in: r),
            controlPoint1: dropletFraction(segment.0, in: r),
            controlPoint2: dropletFraction(segment.1, in: r)
        )
    }
    path.close()
    return path
}

func dropletWave(in r: NSRect, remaining: Double) -> NSBezierPath {
    let clamped = CGFloat(min(1, max(0, remaining)))
    let waterline = dropletFillTop + (1 - clamped) * (dropletFillBottom - dropletFillTop)
    let y = r.minY + waterline * r.height
    let amplitude = r.height * 0.02

    let path = NSBezierPath()
    path.move(to: NSPoint(x: r.minX, y: y))
    path.curve(
        to: NSPoint(x: r.maxX, y: y),
        controlPoint1: NSPoint(x: r.minX + r.width * 0.33, y: y - amplitude),
        controlPoint2: NSPoint(x: r.minX + r.width * 0.66, y: y + amplitude)
    )
    path.line(to: NSPoint(x: r.maxX, y: r.maxY))
    path.line(to: NSPoint(x: r.minX, y: r.maxY))
    path.close()
    return path
}

func dropPoint(_ fx: CGFloat, _ fy: CGFloat, in r: NSRect) -> NSPoint {
    dropletFraction(CGPoint(x: fx, y: fy), in: r)
}

func drawAppIcon(in rect: NSRect, detail: Bool) {
    let size = rect.width
    let background = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.086, green: 0.188, blue: 0.122, alpha: 1),
        NSColor(calibratedRed: 0.043, green: 0.102, blue: 0.071, alpha: 1),
        NSColor(calibratedRed: 0.020, green: 0.043, blue: 0.027, alpha: 1)
    ])?.draw(in: background, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    background.addClip()
    let glowCenter = NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.60)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.78, green: 1, blue: 0.24, alpha: 0.22),
        NSColor(calibratedRed: 0.78, green: 1, blue: 0.24, alpha: 0)
    ])?.draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: size * 0.44, options: [])
    NSGraphicsContext.restoreGraphicsState()

    let dropRect = NSRect(x: size * 0.22, y: size * 0.10, width: size * 0.56, height: size * 0.80)
    let drop = dropletPath(in: dropRect)

    NSColor.white.withAlphaComponent(0.10).setFill()
    drop.fill()

    NSGraphicsContext.saveGraphicsState()
    drop.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.92, green: 1.00, blue: 0.27, alpha: 1),
        NSColor(calibratedRed: 0.44, green: 0.886, blue: 0.10, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.60, blue: 0.35, alpha: 1)
    ])?.draw(in: dropletWave(in: dropRect, remaining: 0.74), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    if detail {
        let cursor = NSBezierPath()
        cursor.move(to: dropPoint(0.34, 0.58, in: dropRect))
        cursor.line(to: dropPoint(0.50, 0.71, in: dropRect))
        cursor.line(to: dropPoint(0.34, 0.84, in: dropRect))
        cursor.lineWidth = size * 0.034
        cursor.lineCapStyle = .round
        cursor.lineJoinStyle = .round
        NSColor.white.withAlphaComponent(0.95).setStroke()
        cursor.stroke()

        let underscore = NSBezierPath()
        underscore.move(to: dropPoint(0.56, 0.84, in: dropRect))
        underscore.line(to: dropPoint(0.74, 0.84, in: dropRect))
        underscore.lineWidth = size * 0.034
        underscore.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.95).setStroke()
        underscore.stroke()

        let highlight = NSBezierPath(ovalIn: NSRect(
            x: dropRect.minX + dropRect.width * 0.18,
            y: dropRect.minY + dropRect.height * 0.16,
            width: dropRect.width * 0.32,
            height: dropRect.height * 0.24
        ))
        NSColor.white.withAlphaComponent(0.16).setFill()
        highlight.fill()
    }

    NSColor.white.withAlphaComponent(0.30).setStroke()
    drop.lineWidth = max(1, size * 0.012)
    drop.lineJoinStyle = .round
    drop.stroke()
}

func makeIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
        drawAppIcon(in: rect, detail: size >= 64)
        return true
    }
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

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndianValue = value.bigEndian
    data.append(Data(bytes: &bigEndianValue, count: MemoryLayout<UInt32>.size))
}

func appendICNSEntry(type: String, pngURL: URL, to data: inout Data) throws {
    let pngData = try Data(contentsOf: pngURL)
    guard let typeData = type.data(using: .ascii), typeData.count == 4 else {
        throw NSError(
            domain: "PromptJuiceIcon",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Invalid ICNS type \(type)"]
        )
    }

    data.append(typeData)
    appendUInt32(UInt32(8 + pngData.count), to: &data)
    data.append(pngData)
}

func writeICNSFallback(from iconsetURL: URL, to outputURL: URL) throws {
    let entries: [(String, String)] = [
        ("icp4", "icon_16x16.png"),
        ("ic11", "icon_16x16@2x.png"),
        ("icp5", "icon_32x32.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"),
        ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png")
    ]

    var body = Data()
    for entry in entries {
        try appendICNSEntry(
            type: entry.0,
            pngURL: iconsetURL.appendingPathComponent(entry.1),
            to: &body
        )
    }

    var icns = Data("icns".utf8)
    appendUInt32(UInt32(8 + body.count), to: &icns)
    icns.append(body)
    try icns.write(to: outputURL, options: .atomic)
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
    FileHandle.standardError.write(
        Data("iconutil failed; writing PromptJuice.icns directly from generated PNGs.\n".utf8)
    )
    try writeICNSFallback(from: iconsetURL, to: outputURL)
}

try? fileManager.removeItem(at: iconsetURL)
