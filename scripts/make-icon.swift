// Renders the viewfinder-and-name-tag icon into an .icns file (and optionally a PNG).
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns [Resources/icon.png]
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: 80% rounded tile, indigo to set it apart from Voice Notes' blue.
    let tile = NSBezierPath(roundedRect: NSRect(x: s * 0.1, y: s * 0.1,
                                              width: s * 0.8, height: s * 0.8),
                            xRadius: s * 0.18, yRadius: s * 0.18)
    let shadow = NSShadow()
    NSGraphicsContext.saveGraphicsState()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.024
    shadow.set()
    NSColor.systemIndigo.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.47, green: 0.45, blue: 1.0, alpha: 1),
               ending: NSColor(calibratedRed: 0.27, green: 0.20, blue: 0.80, alpha: 1))!
        .draw(in: tile, angle: -90)
    NSColor.white.withAlphaComponent(0.22).setStroke()
    tile.lineWidth = s * 0.002
    tile.stroke()

    // Viewfinder corners.
    NSColor.white.setStroke()
    let inset = s * 0.25, arm = s * 0.12, far = s - inset
    for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (far, inset, -1.0, 1.0),
                           (inset, far, 1.0, -1.0), (far, far, -1.0, -1.0)] {
        let corner = NSBezierPath()
        corner.move(to: NSPoint(x: x, y: y + dy * arm))
        corner.line(to: NSPoint(x: x, y: y))
        corner.line(to: NSPoint(x: x + dx * arm, y: y))
        corner.lineWidth = s * 0.04
        corner.lineCapStyle = .round
        corner.lineJoinStyle = .round
        corner.stroke()
    }

    // A name tag in the middle: the screenshot now has words.
    let tag = NSBezierPath(roundedRect: NSRect(x: s * 0.33, y: s * 0.41, width: s * 0.34, height: s * 0.18),
                           xRadius: s * 0.045, yRadius: s * 0.045)
    NSGraphicsContext.saveGraphicsState()
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    shadow.shadowBlurRadius = s * 0.016
    shadow.set()
    NSColor.white.setFill()
    tag.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(calibratedRed: 0.33, green: 0.27, blue: 0.86, alpha: 1).setFill()
    for (y, width) in [(0.517, 0.22), (0.457, 0.14)] {
        NSBezierPath(roundedRect: NSRect(x: s * 0.39, y: s * y, width: s * width, height: s * 0.027),
                     xRadius: s * 0.0135, yRadius: s * 0.0135).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// ICNS supports PNG payloads directly; writing the container avoids an external encoder.
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}

var chunks = Data()
for (type, size) in [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
                     ("ic08", 256), ("ic09", 512), ("ic10", 1024),
                     ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)] {
    let png = render(size)
    chunks.append(Data(type.utf8))
    chunks.append(bigEndian(png.count + 8))
    chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndian(chunks.count + 8))
icon.append(chunks)
try icon.write(to: output)
if CommandLine.arguments.count > 2 {
    try render(256).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
