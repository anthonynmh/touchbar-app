import AppKit
import CoreGraphics
import SnappyNestCore

/// A Gundam-style mobile suit: angular head with a golden V-fin, glowing
/// visor eyes, a cream torso with a red chest plate and steel pauldrons,
/// blocky legs. Hops are thruster bursts, the spanner is a beam saber and
/// a blush is overheating cheek vents.
///
/// Pose mapping: `earLift` raises the fin, `legs` steps the feet,
/// `tailUp` is the backpack thruster, `bodyDX/DY` flex the torso.
enum MechaSprite: PetSpeciesDrawer {
    private static var cellSize: CGSize { PetSprites.cellSize }
    private static let outline = Palette.steelDark
    private static let armour = Palette.steel
    private static let plate = Palette.cream
    private static let red = Palette.mechaRed
    private static let visor = Palette.cyan

    static func lift(action: PetAction, frame: Int) -> CGFloat {
        PetSprites.defaultLift(action: action, frame: frame)
    }

    static func draw(ctx: CGContext, pose p: PetSprites.Pose, frame: Int) {
        let W = cellSize.width
        let ground = cellSize.height

        if p.bodyHidden {
            PetSprites.drawPoof(ctx, step: p.poof, centerX: W / 2, ground: ground)
            return
        }
        defer { if p.poof > 0 { PetSprites.drawPoof(ctx, step: p.poof, centerX: W / 2, ground: ground) } }

        // Legs stand on the ground; the torso sits on them, the head on that.
        let legH: CGFloat = 4
        let bw = max(4, 12 + p.bodyDX)
        let bh = max(0, 8 + p.bodyDY)
        let bx = ((W - bw) / 2).rounded()
        let by = ground - legH - bh
        let torso = CGRect(x: bx, y: by, width: bw, height: bh)
        let midX = W / 2

        // Legs: two blocks, alternating a one-pixel step while walking.
        ctx.setFillColor(outline)
        let leftLift: CGFloat = p.legs == 1 ? 1 : 0
        let rightLift: CGFloat = p.legs == 2 ? 1 : 0
        let leftLeg = CGRect(x: bx + 1, y: ground - legH - leftLift, width: 4, height: legH)
        let rightLeg = CGRect(x: bx + bw - 5, y: ground - legH - rightLift, width: 4, height: legH)
        for leg in [leftLeg, rightLeg] {
            ctx.setFillColor(outline)
            ctx.fill(leg)
            ctx.setFillColor(armour)
            ctx.fill(CGRect(x: leg.minX + 1, y: leg.minY + 1, width: 2, height: 2))
            ctx.setFillColor(plate)
            ctx.fill(CGRect(x: leg.minX + 1, y: leg.maxY - 1, width: 3, height: 1))   // foot plate
        }

        ctx.saveGState()
        if p.lean != 0 {
            // Skew the upper body forward for dashes, pivoting at the feet.
            let t = CGAffineTransform(a: 1, b: 0, c: p.lean / (ground - legH), d: 1, tx: -p.lean, ty: 0)
            ctx.concatenate(t)
        }

        // Backpack thruster behind the torso (the "tail").
        if p.tailUp && bh > 2 {
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: bx - 3, y: by + 1, width: 3, height: min(5, bh - 1)))
            ctx.setFillColor(armour)
            ctx.fill(CGRect(x: bx - 2, y: by + 2, width: 1, height: min(3, bh - 3)))
        }

        // Torso: outlined cream plate with a red chest triangle.
        if bh > 0 {
            ctx.setFillColor(outline)
            ctx.fill(torso.insetBy(dx: -1, dy: -1))
            ctx.setFillColor(plate)
            ctx.fill(torso)
            if bh >= 5 {
                ctx.setFillColor(red)
                PetSprites.drawTriangle(ctx, CGPoint(x: midX - 3, y: by + 1), CGPoint(x: midX + 3, y: by + 1),
                                        CGPoint(x: midX, y: by + 5), fill: red)
                ctx.setFillColor(outline)
                ctx.fill(CGRect(x: midX - 1, y: by + bh - 2, width: 2, height: 1))   // waist joint
            }
            // Pauldrons on both shoulders.
            for sx in [bx - 3, bx + bw - 1] {
                ctx.setFillColor(outline)
                ctx.fill(CGRect(x: sx, y: by - 1, width: 4, height: 4))
                ctx.setFillColor(armour)
                ctx.fill(CGRect(x: sx + 1, y: by, width: 2, height: 2))
            }
        }

        // Head: an angular block with a dark visor band.
        let hw: CGFloat = 8, hh: CGFloat = 6
        let hx = midX - hw / 2 + (p.eyes == .closed && p.mouth == .none ? 1 : 0)  // powered down: slumped
        let hy = by - hh - 1
        ctx.setFillColor(outline)
        ctx.fill(CGRect(x: hx - 1, y: hy - 1, width: hw + 2, height: hh + 2))
        ctx.setFillColor(armour)
        ctx.fill(CGRect(x: hx, y: hy, width: hw, height: hh))
        ctx.setFillColor(outline)
        ctx.fill(CGRect(x: hx + 1, y: hy + 2, width: hw - 2, height: 2))          // visor band
        ctx.fill(CGRect(x: hx + 3, y: hy + 5, width: 2, height: 1))               // chin vent
        drawVisor(ctx, p.eyes, hx: hx, hy: hy, hw: hw)

        // Overheat vents on the cheeks stand in for a blush.
        if p.blush {
            ctx.setFillColor(red)
            ctx.fill(CGRect(x: hx, y: hy + 4, width: 1, height: 1))
            ctx.fill(CGRect(x: hx + hw - 1, y: hy + 4, width: 1, height: 1))
        }

        // Mouth: a tiny grille under the visor.
        ctx.setFillColor(outline)
        switch p.mouth {
        case .none, .small: break
        case .smile: ctx.fill(CGRect(x: hx + 2, y: hy + 5, width: 4, height: 1))
        case .open:  ctx.fill(CGRect(x: hx + 3, y: hy + 4, width: 2, height: 2))
        }

        // V-fin: two golden diagonals rising from the forehead.
        let finH: CGFloat = max(1, 3 + p.earLift)
        ctx.setFillColor(Palette.golden)
        for i in 0..<Int(finH) {
            let d = CGFloat(i)
            let y = hy - 1 - d
            guard y >= 0 else { break }
            ctx.fill(CGRect(x: midX - 2 - d, y: y, width: 1, height: 1))
            ctx.fill(CGRect(x: midX + 1 + d, y: y, width: 1, height: 1))
        }
        ctx.setFillColor(red)
        ctx.fill(CGRect(x: midX - 1, y: hy - 1, width: 2, height: 1))            // fin base jewel
        ctx.restoreGState()

        // Beam saber held out on the facing side, at chest height.
        if p.spanner {
            let sx = bx + bw + 1
            let sy = by + 2 + p.spannerTilt
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: sx, y: sy, width: 2, height: 4))                    // hilt
            ctx.setFillColor(plate)
            ctx.fill(CGRect(x: sx, y: sy + 1, width: 2, height: 2))
            ctx.setFillColor(visor)
            ctx.fill(CGRect(x: sx, y: sy - 8, width: 2, height: 8))                // blade
            ctx.setFillColor(Palette.cream)
            ctx.fill(CGRect(x: sx, y: sy - 8, width: 1, height: 8))                // hot core
        }

        // Thrusters: a horizontal burst behind a dash, vertical ones under
        // the feet on stretched (airborne) frames.
        if p.speedLines {
            PetSprites.drawSpeedLines(ctx, topY: by + 2)
            drawThrust(ctx, x: bx - 4, y: by + 3, horizontal: true)
        }
        if p.bodyDY > 0 && p.eyes != .up {
            // Stretched frames (jump apex, happy hop, surprise) are airborne.
            drawThrust(ctx, x: leftLeg.midX - 1, y: ground - 2, horizontal: false)
            drawThrust(ctx, x: rightLeg.midX - 1, y: ground - 2, horizontal: false)
        }

        if let lift = p.hat {
            PetSprites.drawHardHat(ctx, midX: midX, brimY: hy - 1 - lift)
        }
    }

    /// The glowing visor: two cyan slits whose shape carries the expression.
    private static func drawVisor(_ ctx: CGContext, _ eyes: PetSprites.Eyes, hx: CGFloat, hy: CGFloat, hw: CGFloat) {
        let y = hy + 2
        let left = hx + 1, right = hx + hw - 3
        ctx.setFillColor(visor)
        switch eyes {
        case .open:
            ctx.fill(CGRect(x: left, y: y + 1, width: 2, height: 1))
            ctx.fill(CGRect(x: right, y: y + 1, width: 2, height: 1))
        case .wide:
            ctx.fill(CGRect(x: left, y: y, width: 2, height: 2))
            ctx.fill(CGRect(x: right, y: y, width: 2, height: 2))
        case .closed:
            break                                                                // powered down
        case .squint:
            ctx.fill(CGRect(x: left + 1, y: y + 1, width: 1, height: 1))
            ctx.fill(CGRect(x: right, y: y + 1, width: 1, height: 1))
        case .happy:
            ctx.fill(CGRect(x: left, y: y + 1, width: 2, height: 1))
            ctx.fill(CGRect(x: right, y: y + 1, width: 2, height: 1))
            ctx.setFillColor(Palette.cream)
            ctx.fill(CGRect(x: left + 1, y: y, width: 1, height: 1))
            ctx.fill(CGRect(x: right + 1, y: y, width: 1, height: 1))
        case .up:
            ctx.fill(CGRect(x: left, y: y, width: 2, height: 1))
            ctx.fill(CGRect(x: right, y: y, width: 2, height: 1))
        case .side:
            ctx.fill(CGRect(x: left + 1, y: y + 1, width: 2, height: 1))
            ctx.fill(CGRect(x: right + 1, y: y + 1, width: 2, height: 1))
        }
    }

    /// A two-tone thruster flame, pointing down (vertical) or back (horizontal).
    private static func drawThrust(_ ctx: CGContext, x: CGFloat, y: CGFloat, horizontal: Bool) {
        if horizontal {
            ctx.setFillColor(Palette.golden)
            ctx.fill(CGRect(x: x, y: y, width: 3, height: 2))
            ctx.setFillColor(Palette.tangerine)
            ctx.fill(CGRect(x: x - 2, y: y, width: 2, height: 1))
        } else {
            ctx.setFillColor(Palette.golden)
            ctx.fill(CGRect(x: x, y: y, width: 2, height: 1))
            ctx.setFillColor(Palette.tangerine)
            ctx.fill(CGRect(x: x, y: y + 1, width: 2, height: 1))
        }
    }
}
