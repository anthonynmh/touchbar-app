import AppKit
import CoreGraphics
import SnappyNestCore

/// Paints the tennis court page's ground: a hedge and fence under the live
/// sky, a hard-court surface with cream lines seen side-on, and the net.
/// The strip is only 30 points tall, so the court is drawn as a shallow
/// band with a slight perspective skew (the far sideline sits a few points
/// above the near one). Cached by `SkyPainter.Key` like the terrains; the
/// surface dims with `time.daylight` at night.
public enum CourtPainter {
    /// Vertical layout of the band, in points from the top of the strip.
    public static let hedgeTopY: CGFloat = 13
    public static let farSidelineY: CGFloat = 19
    /// The near sideline is the world's ground line (`middle.maxY - 4`).
    public static let nearSidelineY: CGFloat = 26
    /// Run-off outside the baselines, in points.
    public static let runOff: CGFloat = 12
    /// The service line's position along each half.
    public static let serviceLineFraction: CGFloat = 0.6

    public static func image(size: CGSize, court: CGRect, time: WorldTime, scale: CGFloat) -> CGImage {
        PetSprites.render(size: size, scale: scale) { ctx in
            let dim = 0.45 + 0.55 * time.daylight
            func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
                CGColor(red: r * dim, green: g * dim, blue: b * dim, alpha: a)
            }
            let full = CGRect(origin: .zero, size: size)

            // Hedge: a dark green band with a lighter, bumpy top.
            ctx.setFillColor(c(0.16, 0.36, 0.20))
            ctx.fill(CGRect(x: 0, y: hedgeTopY, width: full.width, height: farSidelineY - hedgeTopY + 1))
            ctx.setFillColor(c(0.24, 0.50, 0.27))
            var x: CGFloat = 0
            var bump = 0
            while x < full.width {
                let h: CGFloat = bump % 3 == 0 ? 2 : 1
                ctx.fill(CGRect(x: x, y: hedgeTopY - h + 1, width: 5, height: h))
                x += 5
                bump += 1
            }
            // Chain-link fence: thin posts and a top rail in front of the hedge.
            ctx.setFillColor(c(0.62, 0.66, 0.70, 0.9))
            ctx.fill(CGRect(x: 0, y: hedgeTopY - 3, width: full.width, height: 1))
            x = court.minX - runOff
            while x <= court.maxX + runOff {
                ctx.fill(CGRect(x: x, y: hedgeTopY - 3, width: 1, height: farSidelineY - hedgeTopY + 3))
                x += 40
            }

            // Grass between the hedge and the ground line, then dark soil
            // below it like the world page.
            ctx.setFillColor(c(0.30, 0.52, 0.26))
            ctx.fill(CGRect(x: 0, y: farSidelineY, width: full.width, height: nearSidelineY - farSidelineY))
            ctx.setFillColor(Palette.ground)
            ctx.fill(CGRect(x: 0, y: nearSidelineY, width: full.width, height: full.height - nearSidelineY))

            // Clay run-off, then the hard-court surface between the baselines,
            // both skewed: the far edge is pulled in by the perspective.
            let skew: CGFloat = 3
            func band(_ minX: CGFloat, _ maxX: CGFloat, color: CGColor) {
                ctx.setFillColor(color)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: minX + skew, y: farSidelineY))
                ctx.addLine(to: CGPoint(x: maxX - skew, y: farSidelineY))
                ctx.addLine(to: CGPoint(x: maxX, y: nearSidelineY))
                ctx.addLine(to: CGPoint(x: minX, y: nearSidelineY))
                ctx.closePath()
                ctx.fillPath()
            }
            band(court.minX - runOff, court.maxX + runOff, color: c(0.66, 0.33, 0.20))
            band(court.minX, court.maxX, color: c(0.18, 0.43, 0.55))

            // Lines: sidelines along the band's edges, baselines and service
            // lines (a centre service line read as a road at this height).
            let line = c(0.98, 0.91, 0.75)
            ctx.setFillColor(line)
            ctx.fill(CGRect(x: court.minX + skew, y: farSidelineY, width: court.width - 2 * skew, height: 1))
            ctx.fill(CGRect(x: court.minX, y: nearSidelineY - 1, width: court.width, height: 1))
            func vertical(_ atX: CGFloat) {
                // From the far sideline (skewed in) down to the near one.
                let t = (atX - court.minX) / court.width
                let farX = court.minX + skew + t * (court.width - 2 * skew)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: farX, y: farSidelineY))
                ctx.addLine(to: CGPoint(x: farX + 1, y: farSidelineY))
                ctx.addLine(to: CGPoint(x: atX + 1, y: nearSidelineY))
                ctx.addLine(to: CGPoint(x: atX, y: nearSidelineY))
                ctx.closePath()
                ctx.fillPath()
            }
            vertical(court.minX)
            vertical(court.maxX - 1)
            let half = court.width / 2
            vertical(court.midX - half * serviceLineFraction)
            vertical(court.midX + half * serviceLineFraction)
            // Net: shadow on the surface, two posts, a mesh with a cream tape.
            let netTop = nearSidelineY - TennisGame.netHeight
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.18))
            ctx.fill(CGRect(x: court.midX + 1, y: farSidelineY + 1, width: 4, height: nearSidelineY - farSidelineY - 1))
            ctx.setFillColor(c(0.92, 0.92, 0.92, 0.55))
            ctx.fill(CGRect(x: court.midX - 2, y: netTop, width: 4, height: TennisGame.netHeight))
            ctx.setFillColor(c(0.35, 0.35, 0.38, 0.6))
            var my = netTop + 2
            while my < nearSidelineY {
                ctx.fill(CGRect(x: court.midX - 2, y: my, width: 4, height: 0.5))
                my += 2
            }
            ctx.setFillColor(c(0.30, 0.30, 0.32))
            ctx.fill(CGRect(x: court.midX - 3, y: netTop - 1, width: 1, height: TennisGame.netHeight + 1))
            ctx.fill(CGRect(x: court.midX + 2, y: netTop - 1, width: 1, height: TennisGame.netHeight + 1))
            ctx.setFillColor(line)
            ctx.fill(CGRect(x: court.midX - 3, y: netTop - 1, width: 6, height: 1.5))
        }
    }
}
