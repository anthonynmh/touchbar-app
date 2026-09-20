import AppKit
import CoreGraphics
import SnappyNestCore

/// Wooden signposts for the playback page: a post in the ground with a plank
/// carrying the previous / play-pause / next symbol.
public enum SignpostGlyphs {
    public static let size = CGSize(width: 22, height: 20)

    public enum Kind: String { case previous, playPause, next }

    private static var cache: [String: CGImage] = [:]

    public static func image(_ kind: Kind, isPlaying: Bool = false, available: Bool, scale: CGFloat) -> CGImage {
        let key = "\(kind.rawValue):\(isPlaying):\(available)@\(scale)"
        if let hit = cache[key] { return hit }
        let img = PetSprites.render(size: size, scale: scale) { ctx in
            draw(ctx, kind: kind, isPlaying: isPlaying, available: available)
        }
        cache[key] = img
        return img
    }

    /// The court's EXIT sign: a wider plank (34×20) on a post; the renderer
    /// sets the word in a text layer over it.
    public static let exitSize = CGSize(width: 34, height: 20)

    public static func exitImage(scale: CGFloat) -> CGImage {
        let key = "exit@\(scale)"
        if let hit = cache[key] { return hit }
        let img = PetSprites.render(size: exitSize, scale: scale) { ctx in
            ctx.setFillColor(Palette.brown)
            ctx.fill(CGRect(x: 16, y: 8, width: 2, height: 12))
            ctx.fill(CGRect(x: 1, y: 1, width: 32, height: 12))
            ctx.setFillColor(Palette.terrain)
            ctx.fill(CGRect(x: 2, y: 2, width: 30, height: 10))
            ctx.setFillColor(Palette.brown)
            ctx.fill(CGRect(x: 3, y: 3, width: 1, height: 1))
            ctx.fill(CGRect(x: 30, y: 3, width: 1, height: 1))
        }
        cache[key] = img
        return img
    }

    // Cell is 22×20, y grows downward; the post's foot is on the bottom edge.
    private static func draw(_ ctx: CGContext, kind: Kind, isPlaying: Bool, available: Bool) {
        let post = Palette.brown
        let plank = available ? Palette.terrain : Palette.ground
        let symbol = available ? Palette.cream : Palette.unavailableTint

        // Post
        ctx.setFillColor(post)
        ctx.fill(CGRect(x: 10, y: 8, width: 2, height: 12))
        // Plank with outline
        ctx.fill(CGRect(x: 2, y: 2, width: 18, height: 10))
        ctx.setFillColor(plank)
        ctx.fill(CGRect(x: 3, y: 3, width: 16, height: 8))
        // Nail heads
        ctx.setFillColor(post)
        ctx.fill(CGRect(x: 4, y: 4, width: 1, height: 1))
        ctx.fill(CGRect(x: 17, y: 4, width: 1, height: 1))

        ctx.setFillColor(symbol)
        switch kind {
        case .previous:
            bar(ctx, x: 5, y: 4, w: 2, h: 6)
            triangle(ctx, tipX: 8, baseX: 14, midY: 7, height: 6)
        case .next:
            triangle(ctx, tipX: 14, baseX: 8, midY: 7, height: 6)
            bar(ctx, x: 15, y: 4, w: 2, h: 6)
        case .playPause:
            if isPlaying {
                bar(ctx, x: 8, y: 4, w: 2, h: 6)
                bar(ctx, x: 12, y: 4, w: 2, h: 6)
            } else {
                triangle(ctx, tipX: 14, baseX: 8, midY: 7, height: 6)
            }
        }
    }

    private static func bar(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    /// A pixel-stepped triangle: 1-px columns from `baseX` shrink toward `tipX`.
    private static func triangle(_ ctx: CGContext, tipX: CGFloat, baseX: CGFloat, midY: CGFloat, height: CGFloat) {
        let width = abs(tipX - baseX)
        let dir: CGFloat = tipX > baseX ? 1 : -1
        for i in 0..<Int(width) {
            let rowH = max(2, (height * (1 - CGFloat(i) / width)).rounded(.up))
            let x = dir > 0 ? baseX + CGFloat(i) : baseX - 1 - CGFloat(i)
            ctx.fill(CGRect(x: x, y: (midY - rowH / 2).rounded(), width: 1, height: rowH))
        }
    }
}
