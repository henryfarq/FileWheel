import AppKit

/// FileWheel's look, drawn in code: a ring of four rounded segments around a centre dot.
enum Icons {
    /// Draws the wheel into `rect`. Segments run clockwise from 12 o'clock like the real wheel.
    static func drawWheel(in rect: NSRect, color: NSColor, ringWidth: CGFloat, gapDegrees: CGFloat, dot: CGFloat) {
        let c = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2 - ringWidth / 2
        // Round line ends poke into the gaps, so widen the drawn gap by their size to keep the visible gap true.
        let cap = (ringWidth / 2) / radius * 180 / .pi
        let gap = gapDegrees + 2 * cap
        color.set()
        for i in 0..<4 {
            let start = 90 - CGFloat(i) * 90 - gap / 2
            let p = NSBezierPath()
            p.appendArc(withCenter: c, radius: radius, startAngle: start, endAngle: start - 90 + gap, clockwise: true)
            p.lineWidth = ringWidth
            p.lineCapStyle = .round
            p.stroke()
        }
        NSBezierPath(ovalIn: NSRect(x: c.x - dot / 2, y: c.y - dot / 2, width: dot, height: dot)).fill()
    }

    /// The menu-bar icon. A "template" image, so macOS tints it to match a light or dark menu bar.
    static func menuBar() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            drawWheel(in: r.insetBy(dx: 1, dy: 1), color: .black, ringWidth: 2.6, gapDegrees: 22, dot: 4.5)
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "FileWheel"
        return img
    }

    /// The app icon: a white wheel on a warm orange-to-pink rounded square.
    static func app(size s: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
            let tile = r.insetBy(dx: s * 0.1, dy: s * 0.1)      // macOS icons leave a margin around the tile
            let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
            NSGradient(colors: [NSColor(red: 1.0, green: 0.62, blue: 0.2, alpha: 1),
                                NSColor(red: 0.93, green: 0.22, blue: 0.45, alpha: 1)])?.draw(in: shape, angle: -60)
            drawWheel(in: tile.insetBy(dx: tile.width * 0.2, dy: tile.width * 0.2), color: .white,
                      ringWidth: tile.width * 0.1, gapDegrees: 18, dot: tile.width * 0.14)
            return true
        }
    }

    /// The menu-bar icon drawn large on white, so it can be checked by eye.
    static func menuBarPreview(size px: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: px, height: px).fill()
        menuBar().draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Writes AppIcon.iconset (all the sizes macOS wants) so `iconutil` can turn it into an .icns file.
    static func writeIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                app(size: CGFloat(px)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}
