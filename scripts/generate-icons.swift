import AppKit
import Foundation

let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let directory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : project.appendingPathComponent("build/Voco.iconset")
let brand = project.appendingPathComponent("Resources/Brand")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)

// Seven capsules descend to a central trough, forming the V in Voco.
let bars: [CGRect] = zip([3, 17, 31, 45, 59, 73, 87], [0, 6, 19, 31, 19, 6, 0])
    .enumerated().map { index, pair in
        CGRect(x: pair.0, y: pair.1, width: 10, height: index == 0 || index == 6 ? 36 : 42)
    }
let orange = NSColor(deviceRed: 1, green: 116.0 / 255, blue: 47.0 / 255, alpha: 1)
let capsules = bars.map { "<rect x=\"\(Int($0.minX))\" y=\"\(Int($0.minY))\" width=\"10\" height=\"\(Int($0.height))\" rx=\"5\"/>" }.joined()
let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 76\" fill=\"#ff742f\">\(capsules)</svg>\n"
try svg.write(to: brand.appendingPathComponent("voco-mark.svg"), atomically: true, encoding: .utf8)

func render(size: Int, appIcon: Bool) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    if appIcon {
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 62 * scale, y: 62 * scale, width: 900 * scale, height: 900 * scale),
            xRadius: 200 * scale, yRadius: 200 * scale).fill()
    }
    let width = CGFloat(size) * (appIcon ? 0.64 : 0.96)
    let unit = width / 100
    let offsetX = (CGFloat(size) - width) / 2
    let offsetY = (CGFloat(size) - 76 * unit) / 2
    (appIcon ? orange : NSColor.black).setFill()
    for bar in bars {
        let bounds = NSRect(x: offsetX + bar.minX * unit,
            y: offsetY + (76 - bar.maxY) * unit, width: bar.width * unit, height: bar.height * unit)
        NSBezierPath(roundedRect: bounds, xRadius: 5 * unit, yRadius: 5 * unit).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    return png
}

for (name, size) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    try render(size: size, appIcon: true).write(to: directory.appendingPathComponent("\(name).png"))
}
try render(size: 1024, appIcon: true).write(to: brand.appendingPathComponent("voco-app.png"))
try render(size: 22, appIcon: false).write(to: brand.appendingPathComponent("voco-trayTemplate.png"))
try render(size: 44, appIcon: false).write(to: brand.appendingPathComponent("voco-trayTemplate@2x.png"))
