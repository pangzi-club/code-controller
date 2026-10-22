// Renders AppIcon.iconset from a programmatically drawn macOS-style icon:
// gradient squircle with a white folder glyph. Run via `swift Scripts/make-icon.swift <output-dir>`.
import AppKit

let outputDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "build")

let masterSize: CGFloat = 1024

func masterIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: masterSize, height: masterSize))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("no graphics context")
    }

    // Squircle tile: inset from canvas edges, corner radius ~22.5% of the tile.
    let inset: CGFloat = masterSize * 0.0977
    let tile = CGRect(x: inset, y: inset, width: masterSize - inset * 2, height: masterSize - inset * 2)
    let tileRadius: CGFloat = tile.width * 0.225

    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tileRadius, yRadius: tileRadius)

    // Diagonal gradient fill.
    let colors = [NSColor(calibratedRed: 0.30, green: 0.52, blue: 1.00, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.05, green: 0.72, blue: 0.86, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors,
                              locations: [0, 1])!
    context.saveGState()
    tilePath.addClip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: tile.minX, y: tile.maxY),
        end: CGPoint(x: tile.maxX, y: tile.minY),
        options: []
    )

    // Soft gloss along the top edge.
    let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [NSColor.white.withAlphaComponent(0.22).cgColor,
                                    NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
    context.drawLinearGradient(
        gloss,
        start: CGPoint(x: 0, y: tile.maxY),
        end: CGPoint(x: 0, y: tile.midY),
        options: []
    )
    context.restoreGState()

    // White folder glyph, centered.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 14
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()

    NSColor.white.setFill()
    let bodyWidth: CGFloat = tile.width * 0.56
    let bodyHeight: CGFloat = tile.height * 0.36
    let bodyX = tile.midX - bodyWidth / 2
    let bodyY = tile.midY - bodyHeight / 2 - tile.height * 0.02
    let corner: CGFloat = bodyHeight * 0.16

    // Tab sticking out above the body's top-left.
    let tabHeight: CGFloat = bodyHeight * 0.22
    let tabWidth: CGFloat = bodyWidth * 0.42
    let tabPath = NSBezierPath(roundedRect: CGRect(
        x: bodyX,
        y: bodyY + bodyHeight - corner,
        width: tabWidth,
        height: tabHeight + corner
    ), xRadius: corner, yRadius: corner)
    tabPath.fill()

    let bodyPath = NSBezierPath(roundedRect: CGRect(
        x: bodyX,
        y: bodyY,
        width: bodyWidth,
        height: bodyHeight
    ), xRadius: corner, yRadius: corner)
    bodyPath.fill()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, px size: Int, to url: URL) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()

    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: url)
}

let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset")
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let icon = masterIcon()
for size in [16, 32, 128, 256, 512] {
    writePNG(icon, px: size, to: iconsetDir.appendingPathComponent("icon_\(size)x\(size).png"))
    writePNG(icon, px: size * 2, to: iconsetDir.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
print("iconset written to \(iconsetDir.path)")
