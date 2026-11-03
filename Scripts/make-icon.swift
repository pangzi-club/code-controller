// Renders AppIcon.iconset from a programmatically drawn macOS-style icon:
// indigo gradient squircle with a white editor window — traffic-light dots in
// the chrome bar and syntax-colored code lines in the body. Run via
// `swift Scripts/make-icon.swift <output-dir>`.
import AppKit

let outputDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "build")

let masterSize: CGFloat = 1024

func masterIcon() -> NSImage {
    NSImage(size: NSSize(width: masterSize, height: masterSize), flipped: false) { _ in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }

        // Squircle tile: inset from canvas edges, corner radius ~22.5% of the tile.
        let inset: CGFloat = masterSize * 0.0977
        let tile = CGRect(x: inset, y: inset, width: masterSize - inset * 2, height: masterSize - inset * 2)
        let tileRadius: CGFloat = tile.width * 0.225
        let tilePath = CGPath(roundedRect: tile, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)

        // Soft drop shadow that separates the tile from light and dark desktops.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -masterSize * 0.012),
                          blur: masterSize * 0.030,
                          color: NSColor.black.withAlphaComponent(0.22).cgColor)
        context.addPath(tilePath)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
        context.restoreGState()

        // Diagonal indigo gradient fill.
        let bgColors = [NSColor(calibratedRed: 0.404, green: 0.420, blue: 0.965, alpha: 1).cgColor,
                        NSColor(calibratedRed: 0.216, green: 0.188, blue: 0.639, alpha: 1).cgColor] as CFArray
        let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: bgColors,
                                    locations: [0, 1])!
        context.saveGState()
        context.addPath(tilePath)
        context.clip()
        context.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: tile.minX, y: tile.maxY),
            end: CGPoint(x: tile.maxX, y: tile.minY),
            options: []
        )

        // Soft radial highlight behind the window, top-left weighted.
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor.white.withAlphaComponent(0.16).cgColor,
                                       NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                              locations: [0, 1])!
        context.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: tile.minX + tile.width * 0.22, y: tile.maxY - tile.height * 0.18),
            startRadius: 0,
            endCenter: CGPoint(x: tile.minX + tile.width * 0.22, y: tile.maxY - tile.height * 0.18),
            endRadius: tile.width * 0.75,
            options: []
        )
        context.restoreGState()

        // Editor window, floating slightly above center.
        let winWidth: CGFloat = tile.width * 0.62
        let winHeight: CGFloat = tile.height * 0.44
        let winRect = CGRect(x: tile.midX - winWidth / 2,
                             y: tile.midY - winHeight / 2 + tile.height * 0.02,
                             width: winWidth,
                             height: winHeight)
        let winRadius: CGFloat = winWidth * 0.075
        let winPath = CGPath(roundedRect: winRect, cornerWidth: winRadius, cornerHeight: winRadius, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -masterSize * 0.018),
                          blur: masterSize * 0.040,
                          color: NSColor.black.withAlphaComponent(0.28).cgColor)
        context.addPath(winPath)
        context.setFillColor(NSColor(calibratedWhite: 0.985, alpha: 1).cgColor)
        context.fillPath()
        context.restoreGState()

        // Chrome divider under the traffic lights.
        let chromeHeight: CGFloat = winHeight * 0.185
        let dividerY = winRect.maxY - chromeHeight
        context.saveGState()
        context.clip(to: CGRect(x: winRect.minX, y: dividerY - masterSize * 0.003,
                                width: winRect.width, height: masterSize * 0.006))
        context.setFillColor(NSColor(calibratedRed: 0.87, green: 0.88, blue: 0.91, alpha: 1).cgColor)
        context.fill(CGRect(x: winRect.minX, y: dividerY - masterSize * 0.003,
                            width: winRect.width, height: masterSize * 0.006))
        context.restoreGState()

        // Traffic lights.
        let dotRadius: CGFloat = chromeHeight * 0.26
        let dotSpacing: CGFloat = dotRadius * 3.1
        let firstDotX = winRect.minX + winRadius * 0.9 + dotRadius
        let dotY = dividerY - chromeHeight / 2
        let dotColors = [NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.34, alpha: 1),
                         NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.18, alpha: 1),
                         NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.26, alpha: 1)]
        for (index, color) in dotColors.enumerated() {
            let center = CGPoint(x: firstDotX + CGFloat(index) * dotSpacing, y: dotY)
            context.saveGState()
            context.addPath(CGPath(ellipseIn: CGRect(x: center.x - dotRadius, y: center.y - dotRadius,
                                                     width: dotRadius * 2, height: dotRadius * 2),
                                   transform: nil))
            context.setFillColor(color.cgColor)
            context.fillPath()
            context.restoreGState()
        }

        // Code lines, alternating indents like real code.
        let padX: CGFloat = winRect.width * 0.10
        let lineHeight: CGFloat = winHeight * 0.075
        let lineGap: CGFloat = winHeight * 0.085
        let lines: [(indent: CGFloat, width: CGFloat, color: NSColor)] = [
            (0.00, 0.30, NSColor(calibratedRed: 0.49, green: 0.36, blue: 0.88, alpha: 1)),
            (0.14, 0.52, NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1)),
            (0.14, 0.40, NSColor(calibratedRed: 0.93, green: 0.29, blue: 0.60, alpha: 1)),
            (0.00, 0.22, NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.14, alpha: 1)),
        ]
        let blockHeight = CGFloat(lines.count) * lineHeight + CGFloat(lines.count - 1) * lineGap
        let blockTop = dividerY - (dividerY - winRect.minY - blockHeight) / 2
        var lineY = blockTop - lineHeight
        for line in lines {
            let x = winRect.minX + padX + line.indent * winRect.width
            let rect = CGRect(x: x, y: lineY, width: line.width * winRect.width, height: lineHeight)
            context.saveGState()
            context.addPath(CGPath(roundedRect: rect, cornerWidth: lineHeight / 2,
                                   cornerHeight: lineHeight / 2, transform: nil))
            context.setFillColor(line.color.cgColor)
            context.fillPath()
            context.restoreGState()
            lineY -= lineHeight + lineGap
        }

        return true
    }
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
