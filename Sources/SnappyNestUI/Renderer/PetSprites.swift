import AppKit
import CoreGraphics
import SnappyNestCore

/// Procedurally drawn pet: a round cat-like blob sized for the 30-point strip.
///
/// Every action maps to a pose + expression. Details are kept at 2×2 px or
/// larger at 2× backing scale so they survive the Touch Bar's size; ears,
/// eyes, mouth, and a few accents above the head carry the expression.
///
/// Rendered images are cached per (action, frame, facing, scale).
public enum PetSprites {
    /// Sprite cell. The pet stands on the bottom edge; the top rows hold
    /// accents (`?`, `z`, sparkle) above the head.
    public static let cellSize = CGSize(width: 24, height: 24)

    /// Vertical lift (points, upward) applied by the renderer for hop frames.
    public static func lift(action: PetAction, frame: Int) -> CGFloat {
        let f = frame % action.frameCount
        switch action {
        case .jump:      return [0, 4, 6, 3][f]
        case .happy:     return [0, 3, 0, 2][f]
        case .surprised: return [4, 2, 0][f]
        case .celebrate: return f == 1 ? 2 : 0
        case .walk, .progressFollow: return f == 1 ? 1 : 0
        default:         return 0
        }
    }

    private struct Key: Hashable {
        let action: PetAction
        let frame: Int
        let facingRight: Bool
        let scale: CGFloat
    }
    private static var cache: [Key: CGImage] = [:]

    public static func image(action: PetAction, frame: Int, facing: PetFacing, scale: CGFloat) -> CGImage {
        let key = Key(action: action, frame: frame % action.frameCount, facingRight: facing == .right, scale: scale)
        if let hit = cache[key] { return hit }
        let img = render(size: cellSize, scale: scale) { ctx in
            ctx.saveGState()
            if !key.facingRight {
                ctx.translateBy(x: cellSize.width, y: 0)
                ctx.scaleBy(x: -1, y: 1)
            }
            draw(ctx: ctx, action: action, frame: key.frame)
            ctx.restoreGState()
            // Glyphs above the head are text-like, so never mirror them.
            let accentX = key.facingRight ? cellSize.width / 2 + 6 : cellSize.width / 2 - 10
            drawAccent(ctx, pose(action: action, frame: key.frame).accent, aboveX: accentX, topY: 0, frame: key.frame)
        }
        cache[key] = img
        return img
    }

    // MARK: - Pose model

    private enum Eyes { case open, wide, closed, squint, happy, up, side }
    private enum Mouth { case none, smile, open, small }

    private struct Pose {
        var eyes: Eyes = .open
        var mouth: Mouth = .small
        var earLift: CGFloat = 0        // ears up (+) or flat (−)
        var bodyDX: CGFloat = 0         // squash/stretch on width
        var bodyDY: CGFloat = 0         // squash/stretch on height
        var lean: CGFloat = 0           // horizontal skew of the top
        var blush = false
        var legs = 0                    // 0 none, 1/2 alternate walking frames
        var accent: Accent = .none
        var speedLines = false
        var tailUp = true
    }

    private enum Accent { case none, question, sparkle, star, zee, note, heart, droplets, exclaim }

    private static func pose(action: PetAction, frame f: Int) -> Pose {
        var p = Pose()
        switch action {
        case .idle:
            p.bodyDY = f == 1 ? -1 : 0
        case .blink:
            p.eyes = f == 1 ? .closed : .open
        case .walk:
            p.legs = f + 1
        case .progressFollow:
            p.legs = f + 1
            p.accent = .note
        case .dash:
            p.legs = f + 1
            p.eyes = .squint
            p.lean = 3
            p.bodyDX = 2; p.bodyDY = -1
            p.speedLines = true
        case .jump:
            p.eyes = f == 2 ? .happy : .open
            p.mouth = .open
            p.bodyDY = f == 1 || f == 2 ? 2 : -1
            p.bodyDX = f == 1 || f == 2 ? -1 : 1
            p.earLift = 1
        case .inspect:
            p.eyes = .side
            p.accent = .question
            p.lean = f == 1 ? 1 : 0
        case .splash:
            p.eyes = .happy
            p.mouth = .open
            p.accent = .droplets
            p.bodyDY = f == 1 ? -1 : 0
        case .stargaze:
            p.eyes = .up
            p.mouth = .none
            p.accent = f == 1 ? .sparkle : .none
        case .celebrate:
            p.eyes = .happy
            p.mouth = .open
            p.earLift = 1
            p.accent = .star
            p.blush = true
            p.bodyDY = f == 1 ? 1 : -1
        case .sleep:
            p.eyes = .closed
            p.mouth = .none
            p.earLift = -1
            p.bodyDY = -3; p.bodyDX = 2
            p.accent = f == 1 ? .zee : .none
            p.tailUp = false
        case .wake:
            p.eyes = .wide
            p.mouth = .open
            p.bodyDY = f == 1 ? 1 : -1
        case .happy:
            p.eyes = .happy
            p.mouth = .smile
            p.blush = true
            p.earLift = 1
            p.accent = f == 1 || f == 3 ? .heart : .none
            p.bodyDY = f == 1 ? 1 : (f == 2 ? -1 : 0)
        case .surprised:
            p.eyes = .wide
            p.mouth = .open
            p.earLift = 1
            p.accent = .exclaim
            p.bodyDY = f == 0 ? 2 : 0
            p.bodyDX = f == 0 ? -1 : 0
        }
        return p
    }

    // MARK: - Drawing (cell is 24×24, y grows downward)

    private static let outline = Palette.brown
    private static let fur = Palette.tangerine
    private static let furLight = CGColor(red: 0xFF/255, green: 0xA4/255, blue: 0x4A/255, alpha: 1)
    private static let belly = Palette.cream
    private static let blushPink = CGColor(red: 0xF2/255, green: 0x6A/255, blue: 0x6A/255, alpha: 0.85)

    private static func draw(ctx: CGContext, action: PetAction, frame: Int) {
        let p = pose(action: action, frame: frame)
        let W = cellSize.width
        let ground = cellSize.height           // feet touch the bottom edge

        // Body: a rounded blob. Width/height flex with the pose.
        let bw = 18 + p.bodyDX
        let bh = 14 + p.bodyDY
        let bx = (W - bw) / 2
        let by = ground - bh - 1               // 1 px for the feet
        let body = CGRect(x: bx, y: by, width: bw, height: bh)

        // Tail (behind the body on the left = back side when facing right)
        ctx.setFillColor(outline)
        if p.tailUp {
            ctx.fillEllipse(in: CGRect(x: bx - 3, y: by + 3, width: 6, height: 6))
            ctx.setFillColor(fur)
            ctx.fillEllipse(in: CGRect(x: bx - 2, y: by + 4, width: 4, height: 4))
        } else {
            ctx.fill(CGRect(x: bx - 3, y: ground - 4, width: 5, height: 3))
            ctx.setFillColor(fur)
            ctx.fill(CGRect(x: bx - 2, y: ground - 3, width: 3, height: 1))
        }

        // Feet
        ctx.setFillColor(outline)
        let footY = ground - 2
        switch p.legs {
        case 1:
            ctx.fill(CGRect(x: bx + 3, y: footY, width: 4, height: 2))
            ctx.fill(CGRect(x: bx + bw - 6, y: footY - 1, width: 4, height: 2))
        case 2:
            ctx.fill(CGRect(x: bx + 3, y: footY - 1, width: 4, height: 2))
            ctx.fill(CGRect(x: bx + bw - 6, y: footY, width: 4, height: 2))
        default:
            ctx.fill(CGRect(x: bx + 3, y: footY, width: 4, height: 2))
            ctx.fill(CGRect(x: bx + bw - 7, y: footY, width: 4, height: 2))
        }

        // Ears: two triangles on top of the body.
        let earBaseY = by + 4
        let earH: CGFloat = 6 + p.earLift * 2
        for (i, earX) in [bx + 2, bx + bw - 8].enumerated() {
            let tilt: CGFloat = i == 0 ? -1 : 1
            drawTriangle(ctx, CGPoint(x: earX, y: earBaseY),
                         CGPoint(x: earX + 6, y: earBaseY),
                         CGPoint(x: earX + 3 + tilt, y: earBaseY - earH), fill: outline)
            drawTriangle(ctx, CGPoint(x: earX + 1, y: earBaseY),
                         CGPoint(x: earX + 5, y: earBaseY),
                         CGPoint(x: earX + 3 + tilt, y: earBaseY - earH + 2), fill: fur)
        }

        // Body outline + fill, with a light top highlight and cream belly.
        ctx.saveGState()
        if p.lean != 0 {
            // Skew the top of the body forward for dashes.
            let t = CGAffineTransform(a: 1, b: 0, c: p.lean / bh, d: 1, tx: -p.lean * (ground / bh) , ty: 0)
            ctx.concatenate(t)
        }
        ctx.setFillColor(outline)
        ctx.fillEllipse(in: body.insetBy(dx: -1, dy: -1))
        ctx.setFillColor(fur)
        ctx.fillEllipse(in: body)
        ctx.setFillColor(furLight)
        ctx.fillEllipse(in: CGRect(x: body.minX + 3, y: body.minY + 1, width: body.width - 6, height: 4))
        ctx.setFillColor(belly)
        ctx.fillEllipse(in: CGRect(x: body.midX - 4, y: body.maxY - 6, width: 8, height: 5))
        ctx.restoreGState()

        // Face: eyes sit in the upper half, toward the facing side.
        let eyeY = body.minY + 4
        let leftEyeX = body.midX - 5
        let rightEyeX = body.midX + 2
        drawEyes(ctx, p.eyes, leftX: leftEyeX, rightX: rightEyeX, y: eyeY)

        if p.blush {
            ctx.setFillColor(blushPink)
            ctx.fill(CGRect(x: leftEyeX - 1, y: eyeY + 5, width: 2, height: 2))
            ctx.fill(CGRect(x: rightEyeX + 3, y: eyeY + 5, width: 2, height: 2))
        }

        // Mouth
        ctx.setFillColor(outline)
        let mouthY = eyeY + 6
        switch p.mouth {
        case .none: break
        case .small:
            ctx.fill(CGRect(x: body.midX - 1, y: mouthY, width: 2, height: 1))
        case .smile:
            ctx.fill(CGRect(x: body.midX - 2, y: mouthY, width: 4, height: 1))
            ctx.fill(CGRect(x: body.midX - 3, y: mouthY - 1, width: 1, height: 1))
            ctx.fill(CGRect(x: body.midX + 2, y: mouthY - 1, width: 1, height: 1))
        case .open:
            ctx.fillEllipse(in: CGRect(x: body.midX - 1.5, y: mouthY - 0.5, width: 3, height: 3))
        }

        // Speed lines trail behind a dashing pet.
        if p.speedLines {
            ctx.setFillColor(Palette.cream.copy(alpha: 0.8) ?? Palette.cream)
            ctx.fill(CGRect(x: 0, y: by + 4, width: 4, height: 1))
            ctx.fill(CGRect(x: 1, y: by + 8, width: 3, height: 1))
        }

    }

    private static func drawEyes(_ ctx: CGContext, _ eyes: Eyes, leftX: CGFloat, rightX: CGFloat, y: CGFloat) {
        func eye(_ x: CGFloat) {
            switch eyes {
            case .open, .side, .up:
                ctx.setFillColor(Palette.cream)
                ctx.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 6, height: 7))
                ctx.setFillColor(outline)
                let px: CGFloat = eyes == .side ? x + 2 : x + 1
                let py: CGFloat = eyes == .up ? y : y + 2
                ctx.fill(CGRect(x: px, y: py, width: 3, height: 3))
                ctx.setFillColor(Palette.cream)
                ctx.fill(CGRect(x: px + 2, y: py, width: 1, height: 1))
            case .wide:
                ctx.setFillColor(Palette.cream)
                ctx.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 6, height: 7))
                ctx.setFillColor(outline)
                ctx.fillEllipse(in: CGRect(x: x + 1, y: y + 1, width: 3, height: 4))
                ctx.setFillColor(Palette.cream)
                ctx.fill(CGRect(x: x + 2, y: y + 1, width: 1, height: 1))
            case .closed:
                ctx.setFillColor(outline)
                ctx.fill(CGRect(x: x, y: y + 3, width: 4, height: 1))
            case .squint:
                ctx.setFillColor(outline)
                ctx.fill(CGRect(x: x, y: y + 2, width: 4, height: 2))
            case .happy:
                // ^ ^ eyes: two 1px diagonals meeting at the top.
                ctx.setFillColor(outline)
                ctx.fill(CGRect(x: x, y: y + 3, width: 1, height: 1))
                ctx.fill(CGRect(x: x + 1, y: y + 2, width: 1, height: 1))
                ctx.fill(CGRect(x: x + 2, y: y + 2, width: 1, height: 1))
                ctx.fill(CGRect(x: x + 3, y: y + 3, width: 1, height: 1))
            }
        }
        eye(leftX)
        eye(rightX)
    }

    private static func drawAccent(_ ctx: CGContext, _ accent: Accent, aboveX x: CGFloat, topY: CGFloat, frame: Int) {
        let y = topY + 1
        switch accent {
        case .none:
            break
        case .question:
            ctx.setFillColor(Palette.cream)
            ctx.fill(CGRect(x: x, y: y, width: 4, height: 1))
            ctx.fill(CGRect(x: x + 3, y: y + 1, width: 1, height: 1))
            ctx.fill(CGRect(x: x + 1, y: y + 2, width: 3, height: 1))
            ctx.fill(CGRect(x: x + 1, y: y + 3, width: 1, height: 1))
            ctx.fill(CGRect(x: x + 1, y: y + 5, width: 1, height: 1))
        case .exclaim:
            ctx.setFillColor(Palette.cream)
            ctx.fill(CGRect(x: x + 1, y: y, width: 2, height: 4))
            ctx.fill(CGRect(x: x + 1, y: y + 5, width: 2, height: 1))
        case .sparkle:
            ctx.setFillColor(Palette.cream)
            ctx.fill(CGRect(x: x + 1, y: y, width: 1, height: 5))
            ctx.fill(CGRect(x: x - 1, y: y + 2, width: 5, height: 1))
        case .star:
            ctx.setFillColor(Palette.golden)
            ctx.fill(CGRect(x: x + 1, y: y, width: 1, height: 5))
            ctx.fill(CGRect(x: x - 1, y: y + 2, width: 5, height: 1))
            ctx.fill(CGRect(x: x, y: y + 1, width: 3, height: 3))
        case .zee:
            ctx.setFillColor(Palette.cream)
            ctx.fill(CGRect(x: x, y: y, width: 4, height: 1))
            ctx.fill(CGRect(x: x + 2, y: y + 1, width: 1, height: 1))
            ctx.fill(CGRect(x: x + 1, y: y + 2, width: 1, height: 1))
            ctx.fill(CGRect(x: x, y: y + 3, width: 4, height: 1))
        case .note:
            ctx.setFillColor(Palette.cyan)
            ctx.fill(CGRect(x: x + 2, y: y, width: 1, height: 4))
            ctx.fill(CGRect(x: x + 2, y: y, width: 2, height: 1))
            ctx.fillEllipse(in: CGRect(x: x, y: y + 3, width: 3, height: 2))
        case .heart:
            ctx.setFillColor(blushPink)
            ctx.fill(CGRect(x: x, y: y, width: 2, height: 1))
            ctx.fill(CGRect(x: x + 3, y: y, width: 2, height: 1))
            ctx.fill(CGRect(x: x - 1, y: y + 1, width: 7, height: 1))
            ctx.fill(CGRect(x: x, y: y + 2, width: 5, height: 1))
            ctx.fill(CGRect(x: x + 1, y: y + 3, width: 3, height: 1))
            ctx.fill(CGRect(x: x + 2, y: y + 4, width: 1, height: 1))
        case .droplets:
            ctx.setFillColor(Palette.cyan)
            let phase = CGFloat(frame % 2)
            ctx.fillEllipse(in: CGRect(x: x - 2, y: y + 1 + phase, width: 2, height: 2))
            ctx.fillEllipse(in: CGRect(x: x + 3, y: y + 2 - phase, width: 2, height: 2))
        }
    }

    private static func drawTriangle(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint, fill: CGColor) {
        ctx.setFillColor(fill)
        ctx.beginPath()
        ctx.move(to: a); ctx.addLine(to: b); ctx.addLine(to: c); ctx.closePath()
        ctx.fillPath()
    }

    // MARK: - Bitmap

    /// Draw into a flipped (y-down) bitmap context so the cell coordinates
    /// above read like the scene's flipped view coordinates.
    static func render(size: CGSize, scale: CGFloat, drawing: (CGContext) -> Void) -> CGImage {
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: 4 * w, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        drawing(ctx)
        return ctx.makeImage()!
    }
}
