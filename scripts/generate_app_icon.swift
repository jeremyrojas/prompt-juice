#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("Usage: generate_app_icon.swift <source.png> <output.icns>\n".utf8)
    )
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let fileManager = FileManager.default
let iconsetURL = outputURL
    .deletingPathExtension()
    .appendingPathExtension("iconset")

guard let mascot = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(
        Data("Could not read mascot icon source at \(sourceURL.path)\n".utf8)
    )
    exit(66)
}

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(
    at: iconsetURL,
    withIntermediateDirectories: true
)

func makeIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        mascot.draw(
            in: rect,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
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
