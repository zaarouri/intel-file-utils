import Foundation
import CoreGraphics

public enum RadialMode: String, Sendable {
    case conversions = "conversions"
    case tools = "tools"
    case actions = "actions"

    public var title: String {
        switch self {
        case .conversions: return "CONVERT"
        case .tools: return "TOOLS"
        case .actions: return "ACTIONS"
        }
    }

    public var symbol: String {
        switch self {
        case .conversions: return "arrow.triangle.2.circlepath"
        case .tools: return "wrench.and.screwdriver"
        case .actions: return "square.and.arrow.up"
        }
    }
}

public struct RadialGeometry {
    public static let innerRadius: CGFloat = 56.0
    public static let outerRadius: CGFloat = 152.0
    public static let gap: CGFloat = 4.5
    public static let cornerRadius: CGFloat = 12.0
    public static let totalSize: CGFloat = 330.0

    public static func centerAngle(for index: Int, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let step = (2.0 * CGFloat.pi) / CGFloat(count)
        return (CGFloat.pi / 2.0) - (CGFloat(index) * step)
    }

    public static func hitTest(point: CGPoint, center: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = hypot(dx, dy)

        if dist < innerRadius || dist > outerRadius {
            return nil
        }

        var angle = atan2(dy, dx)
        if angle < 0 {
            angle += 2.0 * CGFloat.pi
        }

        var normalized = (CGFloat.pi / 2.0) - angle
        if normalized < 0 {
            normalized += 2.0 * CGFloat.pi
        }

        let step = (2.0 * CGFloat.pi) / CGFloat(count)
        let index = Int(floor((normalized + step / 2.0) / step)) % count
        return index
    }

    public static func petalPath(index: Int, count: Int, center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        guard count > 0 else { return path }

        let step = (2.0 * CGFloat.pi) / CGFloat(count)
        let midAngle = centerAngle(for: index, count: count)

        let gapAngle = gap / ((innerRadius + outerRadius) / 2.0)
        let startAngle = midAngle - (step / 2.0) + (gapAngle / 2.0)
        let endAngle = midAngle + (step / 2.0) - (gapAngle / 2.0)

        path.addArc(center: center, radius: innerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: outerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()

        return path
    }

    public static func iconCenter(for index: Int, count: Int, center: CGPoint) -> CGPoint {
        let midAngle = centerAngle(for: index, count: count)
        let midR = innerRadius + (outerRadius - innerRadius) * 0.53
        return CGPoint(
            x: center.x + cos(midAngle) * midR,
            y: center.y + sin(midAngle) * midR
        )
    }
}
