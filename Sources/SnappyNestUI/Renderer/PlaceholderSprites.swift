import AppKit
import CoreGraphics

/// Procedurally rendered scenery: the sun, the moon, and the ground props.
/// Cells are drawn in flipped (y-down) coordinates like the pet.
public enum PlaceholderSprites {
    public static let sunSize = CGSize(width: 18, height: 18)
    public static let moonSize = CGSize(width: 16, height: 16)
    public static let propSize = CGSize(width: 14, height: 14)

    private static var cache: [String: CGImage] = [:]

    public static func sunImage(scale: CGFloat) -> CGImage {
        cached("sun@\(scale)") {
            PetSprites.render(size: sunSize, scale: scale) { ctx in
                ctx.setShouldAntialias(true)
                ctx.setFillColor(Palette.golden.copy(alpha: 0.18) ?? Palette.golden)
                ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 18, height: 18))
                ctx.setFillColor(Palette.golden.copy(alpha: 0.35) ?? Palette.golden)
                ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 14, height: 14))
                ctx.setFillColor(Palette.golden)
                ctx.fillEllipse(in: CGRect(x: 4, y: 4, width: 10, height: 10))
                ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.75, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: 5.5, y: 5.5, width: 6, height: 6))
            }
        }
    }

    public static func moonImage(scale: CGFloat) -> CGImage {
        cached("moon@\(scale)") {
            PetSprites.render(size: moonSize, scale: scale) { ctx in
                ctx.setShouldAntialias(true)
                ctx.setFillColor(Palette.cream.copy(alpha: 0.14) ?? Palette.cream)
                ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 16, height: 16))
                ctx.setFillColor(CGColor(red: 0.96, green: 0.94, blue: 0.82, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: 3, y: 3, width: 10, height: 10))
                // Crescent shadow and two craters.
                ctx.setFillColor(CGColor(red: 0.10, green: 0.13, blue: 0.28, alpha: 0.9))
                ctx.fillEllipse(in: CGRect(x: 6.5, y: 1.5, width: 10, height: 10))
                ctx.setFillColor(CGColor(red: 0.80, green: 0.78, blue: 0.66, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: 5, y: 6, width: 2, height: 2))
                ctx.fillEllipse(in: CGRect(x: 7, y: 9.5, width: 1.5, height: 1.5))
            }
        }
    }

    public static func propImage(prop: String, scale: CGFloat) -> CGImage {
        cached("prop:\(prop)@\(scale)") {
            PetSprites.render(size: propSize, scale: scale) { ctx in
                drawProp(ctx: ctx, prop: prop)
            }
        }
    }

    // MARK: - Props (14×14, y-down, ground at y = 14)

    private static func drawProp(ctx: CGContext, prop: String) {
        let outline = Palette.brown
        switch prop {
        case "crystal":
            diamond(ctx, cx: 7, top: 2, bottom: 14, halfW: 4, color: outline)
            diamond(ctx, cx: 7, top: 3, bottom: 13, halfW: 3, color: Palette.cyan)
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.7))
            ctx.fill(CGRect(x: 5, y: 5, width: 1, height: 4))
        case "sprout":
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: 6, y: 7, width: 2, height: 7))
            let leaf = CGColor(red: 0.42, green: 0.75, blue: 0.38, alpha: 1)
            ctx.setFillColor(outline)
            ctx.fillEllipse(in: CGRect(x: 1, y: 4, width: 7, height: 5))
            ctx.fillEllipse(in: CGRect(x: 6, y: 2, width: 7, height: 5))
            ctx.setFillColor(leaf)
            ctx.fillEllipse(in: CGRect(x: 2, y: 5, width: 5, height: 3))
            ctx.fillEllipse(in: CGRect(x: 7, y: 3, width: 5, height: 3))
        case "cloud":
            ctx.setFillColor(CGColor(gray: 0.78, alpha: 0.9))
            ctx.fillEllipse(in: CGRect(x: 0, y: 6, width: 7, height: 6))
            ctx.fillEllipse(in: CGRect(x: 4, y: 3, width: 7, height: 8))
            ctx.fillEllipse(in: CGRect(x: 8, y: 6, width: 6, height: 6))
            ctx.setFillColor(CGColor(gray: 0.96, alpha: 0.95))
            ctx.fillEllipse(in: CGRect(x: 1, y: 5, width: 6, height: 5))
            ctx.fillEllipse(in: CGRect(x: 4, y: 2, width: 7, height: 7))
            ctx.fillEllipse(in: CGRect(x: 8, y: 5, width: 5, height: 5))
        case "puddle":
            ctx.setFillColor(CGColor(red: 0.20, green: 0.45, blue: 0.55, alpha: 0.9))
            ctx.fillEllipse(in: CGRect(x: 0, y: 9, width: 14, height: 5))
            ctx.setFillColor(Palette.cyan.copy(alpha: 0.85) ?? Palette.cyan)
            ctx.fillEllipse(in: CGRect(x: 1, y: 10, width: 12, height: 3))
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.6))
            ctx.fill(CGRect(x: 3, y: 10.5, width: 4, height: 1))
        case "lantern":
            ctx.setFillColor(Palette.golden.copy(alpha: 0.18) ?? Palette.golden)
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 14, height: 14))
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: 6, y: 7, width: 2, height: 7))
            ctx.fill(CGRect(x: 4, y: 13, width: 6, height: 1))
            ctx.fill(CGRect(x: 4, y: 1, width: 6, height: 7))
            ctx.setFillColor(Palette.golden)
            ctx.fill(CGRect(x: 5, y: 2, width: 4, height: 5))
            ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.75, alpha: 1))
            ctx.fill(CGRect(x: 6, y: 3, width: 2, height: 3))
        case "stargazingSpot":
            // A small log to sit on with a tuft of grass.
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: 0, y: 8, width: 14, height: 6))
            ctx.setFillColor(CGColor(red: 0.55, green: 0.36, blue: 0.20, alpha: 1))
            ctx.fill(CGRect(x: 1, y: 9, width: 12, height: 4))
            ctx.setFillColor(CGColor(red: 0.80, green: 0.62, blue: 0.40, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 10, y: 9, width: 3, height: 4))
            ctx.setFillColor(CGColor(red: 0.42, green: 0.75, blue: 0.38, alpha: 1))
            ctx.fill(CGRect(x: 2, y: 6, width: 1, height: 2))
            ctx.fill(CGRect(x: 4, y: 5, width: 1, height: 3))
        default:
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: 3, y: 6, width: 8, height: 8))
        }
    }

    private static func diamond(_ ctx: CGContext, cx: CGFloat, top: CGFloat, bottom: CGFloat, halfW: CGFloat, color: CGColor) {
        let midY = (top + bottom) / 2
        ctx.setFillColor(color)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx, y: top))
        ctx.addLine(to: CGPoint(x: cx + halfW, y: midY))
        ctx.addLine(to: CGPoint(x: cx, y: bottom))
        ctx.addLine(to: CGPoint(x: cx - halfW, y: midY))
        ctx.closePath()
        ctx.fillPath()
    }

    private static func cached(_ key: String, _ make: () -> CGImage) -> CGImage {
        if let hit = cache[key] { return hit }
        let img = make()
        cache[key] = img
        return img
    }
}
