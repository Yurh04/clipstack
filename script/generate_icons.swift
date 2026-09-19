import AppKit

// Reproducible vector artwork; run with: swift script/generate_icons.swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func render(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(size) / 1024)
    (transform as NSAffineTransform).concat()

    let tile = rounded(NSRect(x: 80, y: 80, width: 864, height: 864), 194)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(calibratedRed: 0.12, green: 0.35, blue: 0.85, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.36, blue: 0.91, alpha: 1),
               ending: NSColor(calibratedRed: 0.30, green: 0.72, blue: 1, alpha: 1))!
        .draw(in: tile, angle: 75)

    // Offset cards express the clipboard's history stack.
    NSColor.white.withAlphaComponent(0.35).setFill()
    rounded(NSRect(x: 365, y: 334, width: 380, height: 438), 58).fill()
    NSColor.white.withAlphaComponent(0.63).setFill()
    rounded(NSRect(x: 307, y: 276, width: 380, height: 438), 58).fill()
    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.45, alpha: 0.24)
    cardShadow.shadowBlurRadius = 24
    cardShadow.shadowOffset = NSSize(width: 0, height: -10)
    cardShadow.set()
    NSColor.white.setFill()
    rounded(NSRect(x: 249, y: 218, width: 380, height: 438), 58).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(calibratedRed: 0.16, green: 0.44, blue: 0.91, alpha: 1).setFill()
    rounded(NSRect(x: 350, y: 622, width: 178, height: 68), 29).fill()
    rounded(NSRect(x: 314, y: 485, width: 250, height: 28), 14).fill()
    NSColor(calibratedRed: 0.56, green: 0.73, blue: 0.96, alpha: 1).setFill()
    rounded(NSRect(x: 314, y: 415, width: 250, height: 28), 14).fill()
    rounded(NSRect(x: 314, y: 345, width: 164, height: 28), 14).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(size: points * scale).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try render(size: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))
