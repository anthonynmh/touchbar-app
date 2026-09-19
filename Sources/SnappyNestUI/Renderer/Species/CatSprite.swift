import AppKit
import CoreGraphics
import SnappyNestCore

/// The original pet: a round cat-like blob. Body drawing only; the pose
/// model and the shared parts (eyes, poof, accents) live in `PetSprites`.
enum CatSprite: PetSpeciesDrawer {
    private static var cellSize: CGSize { PetSprites.cellSize }
    private static let outline = PetSprites.outline
    private static let fur = Palette.tangerine
    private static let furLight = CGColor(red: 0xFF/255, green: 0xA4/255, blue: 0x4A/255, alpha: 1)
    private static let belly = Palette.cream
    private static let blushPink = PetSprites.blushPink

    static func lift(action: PetAction, frame: Int) -> CGFloat {
        PetSprites.defaultLift(action: action, frame: frame)
    }

    static func draw(ctx: CGContext, pose p: PetSprites.Pose, frame: Int) {
        let W = cellSize.width
        let ground = cellSize.height           // feet touch the bottom edge

        if p.bodyHidden {
            PetSprites.drawPoof(ctx, step: p.poof, centerX: W / 2, ground: ground)
            return
        }
        defer { if p.poof > 0 { PetSprites.drawPoof(ctx, step: p.poof, centerX: W / 2, ground: ground) } }

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
            PetSprites.drawTriangle(ctx, CGPoint(x: earX, y: earBaseY),
                         CGPoint(x: earX + 6, y: earBaseY),
                         CGPoint(x: earX + 3 + tilt, y: earBaseY - earH), fill: outline)
            PetSprites.drawTriangle(ctx, CGPoint(x: earX + 1, y: earBaseY),
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
        PetSprites.drawEyes(ctx, p.eyes, leftX: leftEyeX, rightX: rightEyeX, y: eyeY)

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

        // Spanner held out on the facing side, at belly height.
        if p.spanner {
            let sx = body.maxX - 2
            let sy = body.midY + 1 + p.spannerTilt
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: sx - 1, y: sy - 1, width: 8, height: 4))
            ctx.setFillColor(Palette.cream)
            ctx.fill(CGRect(x: sx, y: sy, width: 5, height: 2))
            ctx.fill(CGRect(x: sx + 5, y: sy - 1, width: 2, height: 4))
            ctx.setFillColor(outline)
            ctx.fill(CGRect(x: sx + 6, y: sy, width: 1, height: 2))   // open jaw
        }

        // Hard hat: a golden dome with a brim, sitting on the head between the
        // ears. `lift` raises it for the drop-on / pop-off clips.
        if let lift = p.hat {
            PetSprites.drawHardHat(ctx, midX: body.midX, brimY: by - 1 - lift)
        }

        if p.speedLines {
            PetSprites.drawSpeedLines(ctx, topY: by + 4)
        }

    }
}
