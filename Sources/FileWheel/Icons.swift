import AppKit

/// The menu-bar icon, drawn in code: a ring of four rounded segments around a centre dot.
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
}
