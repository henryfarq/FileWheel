// Turns the icon artwork into the app's icon file.
// The artwork is a rounded square on a white background: this finds the square, cuts it out with
// transparent corners, sizes it on Apple's 1024px icon grid, and writes AppIcon.icns.
//
//   swift scripts/make-icon.swift Assets/AppIcon-source.png Assets/AppIcon.icns
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: swift scripts/make-icon.swift <artwork.png> <out.icns>"); exit(1)
}

// 1. Find the coloured square: every pixel that is clearly not white or the faint glow around it.
let w = cg.width, h = cg.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
        let hi = max(r, g, b), lo = min(r, g, b)
        let saturation = hi == 0 ? 0 : (hi - lo) / hi
        if saturation > 0.35 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
// Bitmap rows run top-down; CoreGraphics rects run bottom-up.
let tile = CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
print("square found at \(tile)")

// 2. Draw it onto Apple's grid: 1024 canvas, 824 square, transparent outside its rounded corners.
func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(px) / 1024
    let dest = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    NSBezierPath(roundedRect: dest, xRadius: 185 * s, yRadius: 185 * s).addClip()
    // Crop a hair inside the square's edge so no white fringe shows.
    let inset = tile.insetBy(dx: tile.width * 0.004, dy: tile.height * 0.004)
    NSGraphicsContext.current?.cgContext.draw(cg.cropping(to: CGRect(x: inset.minX, y: CGFloat(h) - inset.maxY,
                                                                     width: inset.width, height: inset.height))!,
                                              in: dest)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// 3. Write every size macOS wants, then pack them into an .icns.
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(base * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", args[2]]
try iconutil.run(); iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "wrote \(args[2])" : "iconutil failed")
