import AppKit
import CoreGraphics
import SnappyNestCore

/// Procedurally drawn pet sized for the 30-point strip.
///
/// Every action maps to a pose + expression (`pose(action:frame:)`), shared
/// by every species; a `PetSpeciesDrawer` turns that pose into a body.
/// Details are kept at 2×2 px or larger at 2× backing scale so they survive
/// the Touch Bar's size; a few accents above the head carry the expression.
///
/// Rendered images are cached per (species, action, frame, facing, scale).
public enum PetSprites {
    /// Sprite cell. The pet stands on the bottom edge; the top rows hold
    /// accents (`?`, `z`, sparkle) above the head.
    public static let cellSize = CGSize(width: 24, height: 24)

    /// Vertical lift (points, upward) applied by the renderer for hop frames.
    public static func lift(species: PetSpecies = .cat, action: PetAction, frame: Int) -> CGFloat {
        drawer(for: species).lift(action: action, frame: frame)
    }

    static func drawer(for species: PetSpecies) -> PetSpeciesDrawer.Type {
        switch species {
        case .cat:         return CatSprite.self
        case .mecha:       return CatSprite.self
        case .cactus:      return CatSprite.self
        case .eldritchEye: return CatSprite.self
        }
    }

    /// The hop table the cat uses; species without their own reuse it.
    static func defaultLift(action: PetAction, frame: Int) -> CGFloat {
        let f = frame % action.frameCount
        switch action {
        case .jump:      return [0, 4, 6, 3][f]
        case .happy:     return [0, 3, 0, 2][f]
        case .surprised: return [4, 2, 0][f]
        case .celebrate: return f == 1 ? 2 : 0
        case .walk, .progressFollow: return f == 1 ? 1 : 0
        case .suitUp:    return f == 2 ? 1 : 0   // little hop as the hat lands
        default:         return 0
        }
    }

    private struct Key: Hashable {
        let species: PetSpecies
        let action: PetAction
        let frame: Int
        let facingRight: Bool
        let scale: CGFloat
    }
    private static var cache: [Key: CGImage] = [:]

    public static func image(species: PetSpecies = .cat, action: PetAction, frame: Int,
                             facing: PetFacing, scale: CGFloat) -> CGImage {
        let key = Key(species: species, action: action, frame: frame % action.frameCount,
                      facingRight: facing == .right, scale: scale)
        if let hit = cache[key] { return hit }
        let p = pose(action: action, frame: key.frame)
        let img = render(size: cellSize, scale: scale) { ctx in
            ctx.saveGState()
            if !key.facingRight {
                ctx.translateBy(x: cellSize.width, y: 0)
                ctx.scaleBy(x: -1, y: 1)
            }
            drawer(for: species).draw(ctx: ctx, pose: p, frame: key.frame)
            ctx.restoreGState()
            // Glyphs above the head are text-like, so never mirror them.
            let accentX = key.facingRight ? cellSize.width / 2 + 6 : cellSize.width / 2 - 10
            drawAccent(ctx, p.accent, aboveX: accentX, topY: 0, frame: key.frame)
        }
        cache[key] = img
        return img
    }

    // MARK: - Pose model

    enum Eyes { case open, wide, closed, squint, happy, up, side }
    enum Mouth { case none, smile, open, small }

    struct Pose {
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
        var hat: CGFloat? = nil         // hard hat; value = lift above the head
        var spanner = false
        var spannerTilt: CGFloat = 0
        var bodyHidden = false          // teleport: only the poof is drawn
        var poof = 0                    // teleport sparkle burst radius step (0 = none)
    }

    enum Accent { case none, question, sparkle, star, zee, note, heart, droplets, exclaim }

    static func pose(action: PetAction, frame f: Int) -> Pose {
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
        case .suitUp:
            // The hat drops from above and squashes the pet a little on landing.
            p.eyes = f == 3 ? .happy : .up
            p.hat = [7, 4, 1, 0][f]
            p.bodyDY = f == 2 ? -1 : 0
            p.bodyDX = f == 2 ? 1 : 0
            p.mouth = f == 3 ? .smile : .small
        case .suitDown:
            p.eyes = f == 3 ? .open : .up
            p.hat = [0, 1, 4, 7][f]
            p.mouth = .small
        case .tinker:
            p.hat = 0
            p.spanner = true
            p.spannerTilt = [0, -1, 0, 1][f]
            p.eyes = f == 2 ? .closed : .side
            p.mouth = f == 1 || f == 3 ? .smile : .small
            p.bodyDY = f == 1 || f == 3 ? -1 : 0
        case .teleportOut:
            p = teleportPose(step: f)
        case .teleportIn:
            p = teleportPose(step: 3 - f)
        }
        return p
    }

    /// The poof, as a squash from the full pet (step 0) to nothing but
    /// sparkles (step 3). `.teleportOut` plays it forward, `.teleportIn`
    /// backward so the pet lands on its normal idle pose.
    private static func teleportPose(step: Int) -> Pose {
        var p = Pose()
        switch step {
        case 0:
            break                       // the plain idle pose
        case 1:
            p.eyes = .closed
            p.bodyDX = 2; p.bodyDY = -4
            p.earLift = -1
            p.poof = 1
        case 2:
            p.eyes = .closed
            p.mouth = .none
            p.bodyDX = -4; p.bodyDY = -8
            p.earLift = -1
            p.tailUp = false
            p.poof = 2
        default:
            p.bodyHidden = true
            p.poof = 3
        }
        return p
    }

    // MARK: - Shared drawing (cell is 24×24, y grows downward)

    static let outline = Palette.brown
    static let blushPink = CGColor(red: 0xF2/255, green: 0x6A/255, blue: 0x6A/255, alpha: 0.85)

    static func drawEyes(_ ctx: CGContext, _ eyes: Eyes, leftX: CGFloat, rightX: CGFloat, y: CGFloat) {
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

    /// Teleport sparkles: four cream flecks flying outward from the body's
    /// centre, farther each step, with a faint ring on the last step.
    static func drawPoof(_ ctx: CGContext, step: Int, centerX cx: CGFloat, ground: CGFloat) {
        guard step > 0 else { return }
        let cy = ground - 8
        let r = CGFloat(2 + step * 2)
        ctx.setFillColor(Palette.cream)
        for (dx, dy) in [(1, 1), (-1, 1), (1, -1), (-1, -1)] as [(CGFloat, CGFloat)] {
            let x = cx + dx * r, y = cy + dy * (r * 0.6)
            ctx.fill(CGRect(x: x - 0.5, y: y - 1.5, width: 1, height: 3))
            ctx.fill(CGRect(x: x - 1.5, y: y - 0.5, width: 3, height: 1))
        }
        if step == 3 {
            ctx.setStrokeColor(Palette.cream)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: CGRect(x: cx - 5, y: cy - 3, width: 10, height: 6))
        }
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

    static func drawTriangle(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint, fill: CGColor) {
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

/// One body per species. `draw` renders the given pose into the 24×24 cell
/// with the feet on the bottom edge and must be a pure function of the
/// pose, so `teleportIn` frame 3 lands on exactly the `idle` frame 0 image.
protocol PetSpeciesDrawer {
    static func draw(ctx: CGContext, pose: PetSprites.Pose, frame: Int)
    /// Vertical lift for hop frames (see `PetSprites.defaultLift`).
    static func lift(action: PetAction, frame: Int) -> CGFloat
}
