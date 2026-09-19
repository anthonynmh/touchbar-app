import AppKit
import CoreGraphics
import SnappyNestCore

/// The hanging wooden sign on the playback page that carries the track
/// title: a beam across the top on two posts, two short chains, and a plank
/// that fills the region width. Same timber palette as `SignpostGlyphs` so
/// it reads as the same scenery; the renderer lays a `CATextLayer` over the
/// plank (`plankRect`).
public enum TitleBannerGlyph {
    public static let height: CGFloat = 30
    /// The plank's inset from the glyph's edges and its vertical extent.
    public static let plankInsetX: CGFloat = 2
    public static let plankTop: CGFloat = 8
    public static let plankHeight: CGFloat = 14

    private static var cache: [String: CGImage] = [:]

    /// The plank, in the glyph's own coordinates, for a glyph `width` wide.
    public static func plankRect(width: CGFloat) -> CGRect {
        CGRect(x: plankInsetX, y: plankTop, width: max(0, width - 2 * plankInsetX), height: plankHeight)
    }

    /// `available` is whether a title is shown; an empty sign uses the same
    /// darker plank as an unavailable signpost.
    public static func image(width: CGFloat, available: Bool, scale: CGFloat) -> CGImage {
        let w = max(4, width.rounded())
        let key = "\(w):\(available)@\(scale)"
        if let hit = cache[key] { return hit }
        let img = PetSprites.render(size: CGSize(width: w, height: height), scale: scale) { ctx in
            draw(ctx, width: w, available: available)
        }
        cache[key] = img
        return img
    }

    // Cell is `width`×30, y grows downward; the posts' feet are on the bottom edge.
    private static func draw(_ ctx: CGContext, width w: CGFloat, available: Bool) {
        let timber = Palette.brown
        let plankFill = available ? Palette.terrain : Palette.ground
        let plank = plankRect(width: w)

        // Posts at both ends, from the ground up to the beam.
        ctx.setFillColor(timber)
        ctx.fill(CGRect(x: 1, y: 3, width: 2, height: height - 3))
        ctx.fill(CGRect(x: w - 3, y: 3, width: 2, height: height - 3))
        // Beam across the top.
        ctx.fill(CGRect(x: 0, y: 2, width: w, height: 2))
        // Chains from the beam to the plank, one pixel-dotted line each.
        for x in [plank.minX + 6, plank.maxX - 7] {
            for y in stride(from: 4, to: plank.minY, by: 2) {
                ctx.fill(CGRect(x: x, y: CGFloat(y), width: 1, height: 1))
            }
        }
        // Plank with outline, nail heads at the chain anchors.
        ctx.fill(plank)
        ctx.setFillColor(plankFill)
        ctx.fill(plank.insetBy(dx: 1, dy: 1))
        ctx.setFillColor(timber)
        ctx.fill(CGRect(x: plank.minX + 6, y: plank.minY + 2, width: 1, height: 1))
        ctx.fill(CGRect(x: plank.maxX - 7, y: plank.minY + 2, width: 1, height: 1))
        // A lighter grain line along the plank.
        ctx.setFillColor(Palette.cream.copy(alpha: available ? 0.12 : 0.06) ?? Palette.cream)
        ctx.fill(CGRect(x: plank.minX + 3, y: plank.maxY - 4, width: plank.width - 6, height: 1))
    }
}
