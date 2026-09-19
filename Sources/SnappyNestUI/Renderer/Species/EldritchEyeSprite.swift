import AppKit
import CoreGraphics
import SnappyNestCore

/// One huge bloodshot eyeball on a nest of writhing tentacles. The whole
/// body is the eye, so the pose's `eyes` drives the lid and pupil rather
/// than a face; the tentacles crawl to walk and lie flat to sleep.
///
/// Pose mapping: `earLift` raises the outer tentacles, `legs` alternates
/// the crawl, `tailUp = false` flattens the tentacles, `bodyDX/DY` squash
/// the eyeball, `blush` flushes the veins, `mouth` is ignored.
enum EldritchEyeSprite: PetSpeciesDrawer {
    private static var cellSize: CGSize { PetSprites.cellSize }
    private static let outline = Palette.ichorDark
    private static let flesh = Palette.ichor
    private static let sclera = Palette.cream
    private static let vein = Palette.vein

    static func lift(action: PetAction, frame: Int) -> CGFloat {
        let f = frame % action.frameCount
        switch action {
        case .walk, .progressFollow: return 0                    // it crawls, it does not hop
        case .jump:                  return [0, 3, 5, 2][f]
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
        let tentacleH: CGFloat = p.tailUp ? 5 : 2
        let bw = max(4, 15 + p.bodyDX)
        let bh = max(2, 14 + p.bodyDY)
        let bx = (midX - bw / 2).rounded()
        let by = ground - tentacleH - bh
        let ball = CGRect(x: bx, y: by, width: bw, height: bh)

        // Tentacles: five stubs along the bottom, curling alternately while
        // crawling; the outer pair rises with the mood. Drawn first so the
        // eyeball overlaps their roots.
        let roots: [CGFloat] = [-6, -3, 0, 3, 6]
        for (i, dx) in roots.enumerated() {
            let outer = i == 0 || i == roots.count - 1
            var h = tentacleH
            if outer { h += p.earLift * 2 }
            if p.tailUp && p.legs != 0 { h += (i % 2 == (p.legs - 1)) ? 1 : -1 }
            h = max(1, h)
            let x = midX + dx - 1
            let curl: CGFloat = p.tailUp ? (i % 2 == 0 ? 1 : -1) : (dx < 0 ? -1 : 1)
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: x - 1, y: ground - h - 1, width: 4, height: h + 1))
            ctx.fill(CGRect(x: x + curl - 1, y: ground - 2, width: 4, height: 2))       // curled tip
            ctx.setFillColor(flesh)
            ctx.fill(CGRect(x: x, y: ground - h, width: 2, height: h))
            ctx.fill(CGRect(x: x + curl, y: ground - 1, width: 2, height: 1))
        }

        ctx.saveGState()
        if p.lean != 0 {
            let t = CGAffineTransform(a: 1, b: 0, c: p.lean / max(1, bh + tentacleH), d: 1, tx: -p.lean, ty: 0)
            ctx.concatenate(t)
        }

        // Eyeball: outlined sclera with three veins, iris and pupil.
        ctx.setFillColor(outline)
        ctx.fillEllipse(in: ball.insetBy(dx: -1, dy: -1))
        ctx.setFillColor(sclera)
        ctx.fillEllipse(in: ball)
        if bh >= 8 {
            ctx.setFillColor(p.blush ? vein : vein.copy(alpha: 0.7) ?? vein)
            ctx.fill(CGRect(x: ball.minX + 2, y: ball.midY - 2, width: 3, height: 1))
            ctx.fill(CGRect(x: ball.minX + 1, y: ball.midY + 1, width: 2, height: 1))
            ctx.fill(CGRect(x: ball.maxX - 5, y: ball.midY + 2, width: 3, height: 1))
            if p.blush {
                ctx.fill(CGRect(x: ball.minX + 3, y: ball.midY + 3, width: 2, height: 1))
                ctx.fill(CGRect(x: ball.maxX - 4, y: ball.midY - 3, width: 2, height: 1))
            }
        }

        // Iris and pupil, sized and placed by the mood.
        let irisW: CGFloat = min(6, bw - 4), irisH: CGFloat = min(6, bh - 4)
        var irisX = ball.midX - irisW / 2, irisY = ball.midY - irisH / 2
        switch p.eyes {
        case .side: irisX += 2
        case .up:   irisY -= 2
        default:    break
        }
        if irisW >= 2 && irisH >= 2 {
            let iris = CGRect(x: irisX.rounded(), y: irisY.rounded(), width: irisW, height: irisH)
            ctx.setFillColor(flesh)
            ctx.fillEllipse(in: iris)
            let pupilSize: CGFloat
            switch p.eyes {
            case .wide:  pupilSize = 1          // shrunk in fear
            case .happy: pupilSize = 4          // dilated with delight
            default:     pupilSize = 2
            }
            let pupil = CGRect(x: (iris.midX - pupilSize / 2).rounded(), y: (iris.midY - pupilSize / 2).rounded(),
                               width: pupilSize, height: pupilSize)
            ctx.setFillColor(outline)
            ctx.fill(pupil)
            ctx.setFillColor(sclera)
            ctx.fill(CGRect(x: pupil.maxX - 1, y: pupil.minY, width: 1, height: 1))    // glint
        }

        // Eyelid: a flesh-coloured shutter from the top, fully down when
        // closed, halfway for a squint; a lower lid rises for a happy squint.
        let lidDrop: CGFloat
        switch p.eyes {
        case .closed: lidDrop = bh
        case .squint: lidDrop = bh / 2
        case .happy:  lidDrop = 0
        default:      lidDrop = 0
        }
        if lidDrop > 0 {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: ball.minX - 1, y: ball.minY - 1, width: ball.width + 2, height: lidDrop + 1))
            ctx.setFillColor(flesh)
            ctx.fillEllipse(in: ball)
            ctx.restoreGState()
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: ball.minX + 1, y: ball.minY + lidDrop - 1, width: ball.width - 2, height: 1))
        }
        if p.eyes == .happy {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: ball.minX - 1, y: ball.maxY - 3, width: ball.width + 2, height: 4))
            ctx.setFillColor(flesh)
            ctx.fillEllipse(in: ball)
            ctx.restoreGState()
        }
        ctx.restoreGState()

        // Spanner gripped by a front tentacle, raised to the eye's side.
        if p.spanner {
            let sx = ball.maxX + 1
            let sy = ball.midY + 3 + p.spannerTilt
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: sx - 3, y: sy - 1, width: 3, height: 5))                // the holding tentacle
            ctx.fill(CGRect(x: sx - 1, y: sy - 1, width: 8, height: 4))
            ctx.setFillColor(flesh)
            ctx.fill(CGRect(x: sx - 2, y: sy, width: 1, height: 3))
            ctx.setFillColor(Palette.cream)
            ctx.fill(CGRect(x: sx, y: sy, width: 5, height: 2))
            ctx.fill(CGRect(x: sx + 5, y: sy - 1, width: 2, height: 4))
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: sx + 6, y: sy, width: 1, height: 2))
        }

        if p.speedLines {
            PetSprites.drawSpeedLines(ctx, topY: by + 4)
        }
        if let lift = p.hat {
            PetSprites.drawHardHat(ctx, midX: midX, brimY: by - 1 - lift)
        }
    }
}
