import AppKit
import CoreGraphics

/// Procedurally rendered CGImages for the placeholder art. Ships now so we
/// can validate the pipeline end-to-end; a real sprite-atlas system replaces
/// these calls without touching renderer or state-machine code.
///
/// Labeled `placeholder: true` in log output.
public enum PlaceholderSprites {
    public static let cellSize = CGSize(width: 32, height: 32)

    public static func petImage(action: String, frame: Int, facing: String, scale: CGFloat) -> CGImage {
        return image(size: cellSize, scale: scale) { ctx in
            drawPet(ctx: ctx, action: action, frame: frame, facing: facing, size: cellSize)
        }
    }

    public static func sunImage(scale: CGFloat) -> CGImage {
        return image(size: CGSize(width: 14, height: 14), scale: scale) { ctx in
            ctx.setFillColor(Palette.golden); ctx.fillEllipse(in: CGRect(x: 1, y: 1, width: 12, height: 12))
            ctx.setFillColor(Palette.cream);  ctx.fillEllipse(in: CGRect(x: 3, y: 3, width: 8, height: 8))
        }
    }

    public static func moonImage(scale: CGFloat) -> CGImage {
        return image(size: CGSize(width: 12, height: 12), scale: scale) { ctx in
            ctx.setFillColor(Palette.cream)
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 12, height: 12))
            ctx.setFillColor(CGColor(gray: 0.2, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 5, y: 1, width: 6, height: 10))
        }
    }

    public static func propImage(prop: String, scale: CGFloat) -> CGImage {
        return image(size: CGSize(width: 10, height: 10), scale: scale) { ctx in
            drawProp(ctx: ctx, prop: prop, size: CGSize(width: 10, height: 10))
        }
    }

    // MARK: - Drawing primitives

    private static func drawPet(ctx: CGContext, action: String, frame: Int, facing: String, size: CGSize) {
        // Blob body
        let bodyRect = CGRect(x: 6, y: 10, width: 20, height: 16)
        ctx.setFillColor(Palette.brown)
        ctx.fill(bodyRect.insetBy(dx: -1, dy: -1))
        ctx.setFillColor(Palette.tangerine)
        ctx.fill(bodyRect)

        // Face patch
        let faceX: CGFloat = facing == "right" ? 14 : 8
        ctx.setFillColor(Palette.cream)
        ctx.fill(CGRect(x: faceX, y: 12, width: 10, height: 8))

        // Eye
        let eyeX: CGFloat = facing == "right" ? 20 : 10
        let eyeY: CGFloat = (action == "blink" && frame % 4 == 1) ? 15 : 14
        let eyeH: CGFloat = (action == "blink" && frame % 4 == 1) ? 1 : 3
        ctx.setFillColor(Palette.brown)
        ctx.fill(CGRect(x: eyeX, y: eyeY, width: 2, height: eyeH))

        // Ear tufts
        ctx.setFillColor(Palette.tangerine)
        ctx.fill(CGRect(x: 8, y: 6, width: 4, height: 5))
        ctx.fill(CGRect(x: 20, y: 8, width: 3, height: 4))

        // Cyan accent
        ctx.setFillColor(Palette.cyan)
        ctx.fill(CGRect(x: 15, y: 22, width: 2, height: 2))

        // Frame-anim: bob for walk/dash/celebrate
        // (Applied by the renderer via layer position, not here.)
        _ = frame
    }

    private static func drawProp(ctx: CGContext, prop: String, size: CGSize) {
        switch prop {
        case "crystal":
            ctx.setFillColor(Palette.cyan)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 5, y: 0))
            ctx.addLine(to: CGPoint(x: 9, y: 5))
            ctx.addLine(to: CGPoint(x: 5, y: 10))
            ctx.addLine(to: CGPoint(x: 1, y: 5))
            ctx.closePath()
            ctx.fillPath()
        case "sprout":
            ctx.setFillColor(Palette.brown)
            ctx.fill(CGRect(x: 4, y: 6, width: 2, height: 4))
            ctx.setFillColor(CGColor(red: 0.35, green: 0.65, blue: 0.35, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 6, height: 4))
        case "cloud":
            ctx.setFillColor(CGColor(gray: 0.85, alpha: 0.85))
            ctx.fillEllipse(in: CGRect(x: 0, y: 3, width: 6, height: 4))
            ctx.fillEllipse(in: CGRect(x: 3, y: 2, width: 5, height: 4))
            ctx.fillEllipse(in: CGRect(x: 5, y: 4, width: 5, height: 4))
        case "puddle":
            ctx.setFillColor(Palette.cyan.copy(alpha: 0.7) ?? Palette.cyan)
            ctx.fillEllipse(in: CGRect(x: 0, y: 6, width: 10, height: 3))
        case "lantern":
            ctx.setFillColor(Palette.brown)
            ctx.fill(CGRect(x: 4, y: 8, width: 2, height: 2))
            ctx.setFillColor(Palette.golden)
            ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 6, height: 6))
        case "stargazingSpot":
            ctx.setFillColor(Palette.brown)
            ctx.fill(CGRect(x: 1, y: 7, width: 8, height: 3))
            ctx.setFillColor(Palette.cream)
            ctx.fill(CGRect(x: 4, y: 2, width: 1, height: 1))
            ctx.fill(CGRect(x: 7, y: 4, width: 1, height: 1))
            ctx.fill(CGRect(x: 1, y: 3, width: 1, height: 1))
        default:
            ctx.setFillColor(Palette.brown)
            ctx.fill(CGRect(x: 2, y: 2, width: 6, height: 6))
        }
    }

    private static func image(size: CGSize, scale: CGFloat, drawing: (CGContext) -> Void) -> CGImage {
        let w = Int(size.width  * scale)
        let h = Int(size.height * scale)
        let space = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = 4 * w
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: bytesPerRow, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: scale, y: scale)
        drawing(ctx)
        return ctx.makeImage()!
    }
}
