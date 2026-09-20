import AppKit
import CoreGraphics
import SnappyNestCore

/// A potted saguaro with a face. It has no legs: it hops its terracotta
/// pot, tilting it on walking frames. The arms take the ears' role, a
/// flower blooms on top when it is happy and the spanner is held in the
/// front arm.
///
/// Pose mapping: `earLift` raises/droops the arms, `legs` tilts the pot,
/// `bodyDX/DY` flex the plant, `blush` also blooms the flower.
enum CactusSprite: PetSpeciesDrawer {
    private static var cellSize: CGSize { PetSprites.cellSize }
    private static let outline = Palette.cactusDark
    private static let green = Palette.cactusGreen
    private static let greenLight = Palette.cactusLight
    private static let potOutline = Palette.clayDark
    private static let pot = Palette.clay

    static func lift(action: PetAction, frame: Int) -> CGFloat {
        let f = frame % action.frameCount
        switch action {
        case .walk, .progressFollow: return f == 1 ? 2 : 0      // hop instead of step
        case .dash:                  return f == 1 ? 2 : 1
        default:                     return PetSprites.defaultLift(action: action, frame: frame)
        }
    }

    static func draw(ctx: CGContext, pose p: PetSprites.Pose, frame: Int) {
        let W = cellSize.width
        let ground = cellSize.height

        if p.bodyHidden {
            PetSprites.drawPoof(ctx, step: p.poof, centerX: W / 2, ground: ground)
            return
        }
        defer { if p.poof > 0 { PetSprites.drawPoof(ctx, step: p.poof, centerX: W / 2, ground: ground) } }

        let midX = W / 2
        // Pot: 12 wide, 5 tall, tapering down; the tilt rocks it while hopping.
        let potH: CGFloat = 5
        let tilt: CGFloat = p.legs == 1 ? -1 : (p.legs == 2 ? 1 : 0)
        ctx.saveGState()
        if tilt != 0 {
            ctx.translateBy(x: midX, y: ground)
            ctx.rotate(by: tilt * 0.12)
            ctx.translateBy(x: -midX, y: -ground)
        }
        ctx.setFillColor(potOutline)
        ctx.fill(CGRect(x: midX - 7, y: ground - potH, width: 14, height: 2))       // rim
        ctx.fill(CGRect(x: midX - 6, y: ground - potH + 2, width: 12, height: potH - 2))
        ctx.setFillColor(pot)
        ctx.fill(CGRect(x: midX - 6, y: ground - potH + 1, width: 12, height: 1))
        ctx.fill(CGRect(x: midX - 5, y: ground - potH + 3, width: 10, height: potH - 4))
        ctx.setFillColor(Palette.ground)
        ctx.fill(CGRect(x: midX - 5, y: ground - potH + 1, width: 10, height: 1))  // soil peeking over the rim

        // Plant: a rounded column rising from the soil.
        let bw = max(4, 8 + p.bodyDX)
        let bh = max(0, 15 + p.bodyDY)
        let bx = (midX - bw / 2).rounded()
        let by = ground - potH - bh
        let body = CGRect(x: bx, y: by, width: bw, height: bh)

        if p.lean != 0 {
            let t = CGAffineTransform(a: 1, b: 0, c: p.lean / max(1, bh + potH), d: 1, tx: -p.lean, ty: 0)
            ctx.concatenate(t)
        }

        // Arms: saguaro branches that leave the trunk sideways and turn up.
        // The mood raises (earLift > 0) or droops (< 0) them.
        if bh >= 8 {
            let armH: CGFloat = 5 + p.earLift * 2                 // upward reach
            let joinY = by + 6                                    // where the arm meets the trunk
            for side: CGFloat in [-1, 1] {
                let ax = side < 0 ? bx - 4 : bx + bw + 1          // arm column x
                let top = p.earLift < 0 ? joinY : joinY - armH
                let colH = p.earLift < 0 ? 3 : armH + 2
                ctx.setFillColor(outline)
                ctx.fill(CGRect(x: ax - 1, y: top - 1, width: 5, height: colH + 2))
                ctx.fill(CGRect(x: side < 0 ? ax : bx + bw - 1, y: joinY - 1, width: 5, height: 4))
                ctx.setFillColor(green)
                ctx.fill(CGRect(x: ax, y: top, width: 3, height: colH))
                ctx.fill(CGRect(x: side < 0 ? ax : bx + bw - 1, y: joinY, width: 5, height: 2))
                ctx.setFillColor(Palette.cream)
                ctx.fill(CGRect(x: ax + 1, y: top + 1, width: 1, height: 1))
            }
        }

        // Body with a light column down the front and spine dots.
        if bh > 0 {
            ctx.setFillColor(outline)
            ctx.fillEllipse(in: CGRect(x: body.minX - 1, y: body.minY - 1, width: body.width + 2, height: 8))
            ctx.fill(CGRect(x: body.minX - 1, y: body.minY + 3, width: body.width + 2, height: max(0, bh - 3) + 1))
            ctx.setFillColor(green)
            ctx.fillEllipse(in: CGRect(x: body.minX, y: body.minY, width: body.width, height: 6))
            ctx.fill(CGRect(x: body.minX, y: body.minY + 3, width: body.width, height: max(0, bh - 3)))
            ctx.setFillColor(greenLight)
            ctx.fill(CGRect(x: body.minX + 1, y: body.minY + 2, width: 2, height: max(0, bh - 3)))
            // Spines only below the face so the eyes stay readable.
            ctx.setFillColor(Palette.cream)
            for row in stride(from: body.minY + 10, to: body.maxY - 1, by: 3) {
                ctx.fill(CGRect(x: body.minX + 1, y: row, width: 1, height: 1))
                ctx.fill(CGRect(x: body.maxX - 2, y: row + 1, width: 1, height: 1))
            }
        }

        // Face on the upper half of the trunk: small eyes, a deadpan mouth.
        if bh >= 8 {
            let eyeY = by + 3
            let leftEyeX = body.midX - 3
            let rightEyeX = body.midX + 1
            drawEyes(ctx, p.eyes, leftX: leftEyeX, rightX: rightEyeX, y: eyeY)
            if p.blush {
                ctx.setFillColor(PetSprites.blushPink)
                ctx.fill(CGRect(x: leftEyeX - 1, y: eyeY + 3, width: 1, height: 1))
                ctx.fill(CGRect(x: rightEyeX + 2, y: eyeY + 3, width: 1, height: 1))
            }
            ctx.setFillColor(outline)
            let mouthY = eyeY + 5
            switch p.mouth {
            case .none: break
            case .small: ctx.fill(CGRect(x: body.midX - 1, y: mouthY, width: 2, height: 1))
            case .smile:
                ctx.fill(CGRect(x: body.midX - 2, y: mouthY, width: 4, height: 1))
                ctx.fill(CGRect(x: body.midX - 3, y: mouthY - 1, width: 1, height: 1))
                ctx.fill(CGRect(x: body.midX + 2, y: mouthY - 1, width: 1, height: 1))
            case .open: ctx.fillEllipse(in: CGRect(x: body.midX - 1.5, y: mouthY - 0.5, width: 3, height: 3))
            }
        }

        // A pink flower blooms on the crown when the cactus is pleased.
        if p.blush && p.hat == nil {
            let fy = by - 2
            ctx.setFillColor(PetSprites.blushPink)
            ctx.fill(CGRect(x: midX - 2, y: fy, width: 4, height: 1))
            ctx.fill(CGRect(x: midX - 3, y: fy - 1, width: 6, height: 1))
            ctx.fill(CGRect(x: midX - 2, y: fy - 2, width: 4, height: 1))
            ctx.setFillColor(Palette.golden)
            ctx.fill(CGRect(x: midX - 1, y: fy - 1, width: 2, height: 1))
        }
        ctx.restoreGState()

        // Spanner in the front arm, held out at shoulder height.
        if p.spanner {
            let sx = bx + bw + 2
            let sy = by + 4 + p.spannerTilt
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: sx - 1, y: sy - 1, width: 8, height: 4))
            ctx.setFillColor(Palette.cream)
            ctx.fill(CGRect(x: sx, y: sy, width: 5, height: 2))
            ctx.fill(CGRect(x: sx + 5, y: sy - 1, width: 2, height: 4))
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: sx + 6, y: sy, width: 1, height: 2))
        }
        // Racket in the front arm for the court swing.
        if let step = p.racket {
            PetSprites.drawRacket(ctx, hand: CGPoint(x: bx + bw - 2, y: by + 5), step: step)
        }

        if p.speedLines {
            PetSprites.drawSpeedLines(ctx, topY: by + 4)
        }
        if let lift = p.hat {
            PetSprites.drawHardHat(ctx, midX: midX, brimY: by - 1 - lift)
        }
    }

    /// Two-pixel eyes: a cream socket with a dark pupil that moves with the
    /// mood; closed and squinting eyes are a single dark line.
    private static func drawEyes(_ ctx: CGContext, _ eyes: PetSprites.Eyes, leftX: CGFloat, rightX: CGFloat, y: CGFloat) {
        for x in [leftX, rightX] {
            switch eyes {
            case .open, .side, .up, .wide:
                ctx.setFillColor(Palette.cream)
                ctx.fill(CGRect(x: x - 1, y: y - 1, width: 3, height: eyes == .wide ? 5 : 4))
                ctx.setFillColor(outline)
                let px: CGFloat = eyes == .side ? x + 1 : x
                let py: CGFloat = eyes == .up ? y - 1 : y + 1
                ctx.fill(CGRect(x: px, y: py, width: 1, height: 2))
            case .closed:
                ctx.setFillColor(outline)
                ctx.fill(CGRect(x: x, y: y + 1, width: 2, height: 1))
            case .squint:
                ctx.setFillColor(outline)
                ctx.fill(CGRect(x: x, y: y + 1, width: 2, height: 1))
                ctx.setFillColor(Palette.cream)
                ctx.fill(CGRect(x: x, y: y, width: 2, height: 1))
            case .happy:
                ctx.setFillColor(outline)
                ctx.fill(CGRect(x: x, y: y + 1, width: 1, height: 1))
                ctx.fill(CGRect(x: x + 1, y: y, width: 1, height: 1))
            }
        }
    }
}
