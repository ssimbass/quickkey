import AppKit
import CoreText
import Foundation

// Render every size directly from the same vector drawing, retaining a transparent margin.
// No screenshots, downloaded imagery, or display-server capture are used.
let taskRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assetDirectory = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? taskRoot.appendingPathComponent("Assets", isDirectory: true)
let iconset = assetDirectory.appendingPathComponent("QuickKey.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ rectangle: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rectangle, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func renderIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconError("无法创建 \(size)px 图标画布")
    }
    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }
    let context = graphics.cgContext
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    let factor = CGFloat(size) / 1024
    context.scaleBy(x: factor, y: factor)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let body = rounded(CGRect(x: 100, y: 91, width: 824, height: 824), radius: 184)
    let face = rounded(CGRect(x: 100, y: 112, width: 824, height: 812), radius: 184)

    // The low blue rim gives the tile the slight depth of a physical keyboard key.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -13), blur: 28, color: rgb(0x16305B, alpha: 0.22).cgColor)
    context.addPath(body)
    context.setFillColor(rgb(0x1056C9).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(face)
    context.clip()
    let colors = [rgb(0x2CA7FF).cgColor, rgb(0x1687F5).cgColor, rgb(0x1269E5).cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                                    locations: [0, 0.48, 1]) else { throw IconError("无法创建图标渐变") }
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 112), options: [])

    // Restrained top light and an inset edge keep the small-size silhouette clean.
    let lightColors = [rgb(0xFFFFFF, alpha: 0.18).cgColor, rgb(0xFFFFFF, alpha: 0).cgColor] as CFArray
    if let light = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: lightColors, locations: [0, 1]) {
        context.drawLinearGradient(light, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 570), options: [])
    }
    context.restoreGState()
    context.addPath(rounded(CGRect(x: 101.5, y: 113.5, width: 821, height: 809), radius: 182.5))
    context.setStrokeColor(rgb(0xFFFFFF, alpha: 0.22).cgColor)
    context.setLineWidth(3)
    context.strokePath()

    // CoreText supplies the actual Command glyph; its vector bounds determine centering.
    let baseFont = NSFont.systemFont(ofSize: 620, weight: .medium) as CTFont
    let glyphFont = CTFontCreateForString(baseFont, "⌘" as CFString, CFRange(location: 0, length: 1))
    var character: UniChar = 0x2318
    var glyph: CGGlyph = 0
    guard CTFontGetGlyphsForCharacters(glyphFont, &character, &glyph, 1),
          let commandPath = CTFontCreatePathForGlyph(glyphFont, glyph, nil) else {
        throw IconError("无法读取 Command 字形")
    }
    let bounds = commandPath.boundingBoxOfPath
    let glyphScale = min(452 / bounds.width, 452 / bounds.height)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -3), blur: 5, color: rgb(0x0752C3, alpha: 0.20).cgColor)
    context.translateBy(x: 512 - bounds.midX * glyphScale, y: 518 - bounds.midY * glyphScale)
    context.scaleBy(x: glyphScale, y: glyphScale)
    context.addPath(commandPath)
    context.setFillColor(rgb(0xFFFFFF).cgColor)
    context.fillPath()
    context.restoreGState()
    graphics.flushGraphics()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw IconError("无法编码 PNG") }
    return data
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (filename, size) in variants {
    try renderIcon(size: size).write(to: iconset.appendingPathComponent(filename))
}
let master = assetDirectory.appendingPathComponent("QuickKey-1024.png")
try renderIcon(size: 1024).write(to: master)
let output = assetDirectory.appendingPathComponent("QuickKey.icns")
let converter = Process()
converter.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
converter.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try converter.run()
converter.waitUntilExit()
guard converter.terminationStatus == 0 else { throw IconError("iconutil 转换失败") }
print("已生成 1024px 母版、10 个标准/Retina PNG 和 ICNS：\(output.path)")
print("母版：\(master.path)")

struct IconError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
