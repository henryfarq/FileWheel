import CoreGraphics
import Foundation

public enum WheelHit: Equatable { case slice(Int), center, none }

/// Maths shared by the wheel drawing, the mouse hit-testing and the window placement.
public enum WheelGeometry {
    public static let diameter: CGFloat = 300
    public static let centerRadius: CGFloat = 52

    /// Which part of the wheel a point is over. `point` is relative to the wheel centre, y pointing down.
    /// Slices run clockwise from 12 o'clock.
    public static func hit(_ point: CGPoint, sliceCount: Int, outerRadius: CGFloat = diameter / 2) -> WheelHit {
        let r = hypot(point.x, point.y)
        if r <= centerRadius { return .center }
        if r > outerRadius || sliceCount == 0 { return .none }
        var angle = atan2(point.x, -point.y)          // 0 at 12 o'clock, clockwise positive
        if angle < 0 { angle += 2 * .pi }
        return .slice(min(Int(angle / (2 * .pi / Double(sliceCount))), sliceCount - 1))
    }

    /// Where to put the wheel's centre: right of the file, or left if it wouldn't fit on screen.
    public static func center(besideFile file: CGRect, screen: CGRect, gap: CGFloat = 12) -> CGPoint {
        let half = diameter / 2
        let rightX = file.maxX + gap + half
        let x = (rightX + half <= screen.maxX) ? rightX : file.minX - gap - half
        let minY = screen.minY + half, maxY = screen.maxY - half
        return CGPoint(x: x, y: min(max(file.midY, minY), maxY))
    }
}
