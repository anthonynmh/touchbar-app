import AppKit
import CoreGraphics
import SnappyNestCore

/// A battery outline with proportional fill, a drawn charging bolt, and
/// three level colors. Cached per (percent, charging, available, scale).
public enum BatteryGlyph {
    public static let size = CGSize(width: 28, height: 14)

    private struct Key: Hashable {
        let percent: Int
        let charging: Bool
        let available: Bool
        let scale: CGFloat
    }
    private static var cache: [Key: CGImage] = [:]

    public static func fillColor(percentage: Double) -> CGColor {
        if percentage < 0.15 { return Palette.batteryLow }
        if percentage < 0.35 { return Palette.golden }
        return Palette.batteryFill
    }

    public static func image(snapshot: BatterySnapshot, scale: CGFloat) -> CGImage {
        let available = snapshot.percentage != nil
        let key = Key(percent: Int(((snapshot.percentage ?? 0) * 100).rounded()),
                      charging: snapshot.isCharging, available: available, scale: scale)
        if let hit = cache[key] { return hit }
        let img = PetSprites.render(size: size, scale: scale) { ctx in
            draw(ctx: ctx, percentage: snapshot.percentage, charging: snapshot.isCharging)
        }
        cache[key] = img
        return img
    }

    private static func draw(ctx: CGContext, percentage: Double?, charging: Bool) {
        let available = percentage != nil
        let stroke = available ? Palette.cream : Palette.unavailableTint
        let body = CGRect(x: 0.5, y: 1.5, width: 24, height: 11)

        // Outline + cap nub.
        ctx.setStrokeColor(stroke)
        ctx.setLineWidth(1)
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: 2, cornerHeight: 2, transform: nil))
        ctx.strokePath()
        ctx.setFillColor(stroke)
        ctx.fill(CGRect(x: 25.5, y: 5, width: 2, height: 4))

        // Level fill.
        if let pct = percentage {
            let inner = body.insetBy(dx: 2, dy: 2)
            let w = max(pct > 0 ? 1 : 0, (inner.width * CGFloat(pct)).rounded())
            ctx.setFillColor(fillColor(percentage: pct))
            ctx.addPath(CGPath(roundedRect: CGRect(x: inner.minX, y: inner.minY, width: w, height: inner.height),
                               cornerWidth: 1, cornerHeight: 1, transform: nil))
            ctx.fillPath()
        }

        // Charging bolt, outlined so it reads on any fill color.
        if charging {
            let bolt = CGMutablePath()
            bolt.move(to: CGPoint(x: 13.5, y: 2))
            bolt.addLine(to: CGPoint(x: 9, y: 8))
            bolt.addLine(to: CGPoint(x: 12, y: 8))
            bolt.addLine(to: CGPoint(x: 10.5, y: 12.5))
            bolt.addLine(to: CGPoint(x: 15.5, y: 6))
            bolt.addLine(to: CGPoint(x: 12.5, y: 6))
            bolt.closeSubpath()
            ctx.setShouldAntialias(true)
            ctx.setStrokeColor(Palette.brown)
            ctx.setLineWidth(1.5)
            ctx.setLineJoin(.round)
            ctx.addPath(bolt)
            ctx.strokePath()
            ctx.setFillColor(Palette.cream)
            ctx.addPath(bolt)
            ctx.fillPath()
        }
    }
}
