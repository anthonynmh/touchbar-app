import AppKit
import CoreGraphics

/// Small icons for the slider controls and the play/pause button.
public enum ControlGlyphs {
    public static let size = CGSize(width: 12, height: 12)
    public static let playPauseSize = CGSize(width: 20, height: 20)

    private static var cache: [String: CGImage] = [:]

    /// Sun disc with eight short rays.
    public static func brightness(available: Bool, scale: CGFloat) -> CGImage {
        cached("brightness:\(available)@\(scale)") {
            PetSprites.render(size: size, scale: scale) { ctx in
                ctx.setShouldAntialias(true)
                let color = available ? Palette.golden : Palette.unavailableTint
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(x: 3.5, y: 3.5, width: 5, height: 5))
                ctx.setStrokeColor(color)
                ctx.setLineWidth(1)
                ctx.setLineCap(.round)
                let c = CGPoint(x: 6, y: 6)
                for i in 0..<8 {
                    let a = CGFloat(i) * .pi / 4
                    ctx.move(to: CGPoint(x: c.x + cos(a) * 4, y: c.y + sin(a) * 4))
                    ctx.addLine(to: CGPoint(x: c.x + cos(a) * 5.5, y: c.y + sin(a) * 5.5))
                }
                ctx.strokePath()
            }
        }
    }

    /// Speaker wedge with 0–2 arcs depending on `level`, or a slash when muted.
    public static func volume(level: Double, muted: Bool, available: Bool, scale: CGFloat) -> CGImage {
        let arcs = muted || level <= 0.001 ? 0 : (level < 0.5 ? 1 : 2)
        return cached("volume:\(arcs):\(muted):\(available)@\(scale)") {
            PetSprites.render(size: size, scale: scale) { ctx in
                ctx.setShouldAntialias(true)
                let color = available ? (muted ? Palette.unavailableTint : Palette.cyan) : Palette.unavailableTint
                ctx.setFillColor(color)
                ctx.fill(CGRect(x: 1, y: 4, width: 2.5, height: 4))
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 3, y: 4))
                ctx.addLine(to: CGPoint(x: 6.5, y: 1))
                ctx.addLine(to: CGPoint(x: 6.5, y: 11))
                ctx.addLine(to: CGPoint(x: 3, y: 8))
                ctx.closePath()
                ctx.fillPath()
                ctx.setStrokeColor(color)
                ctx.setLineWidth(1)
                ctx.setLineCap(.round)
                for i in 0..<arcs {
                    let r: CGFloat = 3 + CGFloat(i) * 2.2
                    ctx.beginPath()
                    ctx.addArc(center: CGPoint(x: 6, y: 6), radius: r, startAngle: -.pi / 4, endAngle: .pi / 4, clockwise: false)
                    ctx.strokePath()
                }
                if muted {
                    ctx.setStrokeColor(Palette.batteryLow)
                    ctx.setLineWidth(1.5)
                    ctx.move(to: CGPoint(x: 8, y: 3))
                    ctx.addLine(to: CGPoint(x: 11.5, y: 9))
                    ctx.strokePath()
                }
            }
        }
    }

    /// Play triangle or pause bars inside a circle outline.
    public static func playPause(isPlaying: Bool, scale: CGFloat) -> CGImage {
        cached("playpause:\(isPlaying)@\(scale)") {
            PetSprites.render(size: playPauseSize, scale: scale) { ctx in
                ctx.setShouldAntialias(true)
                ctx.setStrokeColor(Palette.cream.copy(alpha: 0.7) ?? Palette.cream)
                ctx.setLineWidth(1)
                ctx.strokeEllipse(in: CGRect(x: 0.5, y: 0.5, width: 19, height: 19))
                ctx.setFillColor(Palette.cream)
                if isPlaying {
                    ctx.fill(CGRect(x: 6.5, y: 6, width: 2.5, height: 8))
                    ctx.fill(CGRect(x: 11, y: 6, width: 2.5, height: 8))
                } else {
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: 7.5, y: 5.5))
                    ctx.addLine(to: CGPoint(x: 7.5, y: 14.5))
                    ctx.addLine(to: CGPoint(x: 14.5, y: 10))
                    ctx.closePath()
                    ctx.fillPath()
                }
            }
        }
    }

    private static func cached(_ key: String, _ make: () -> CGImage) -> CGImage {
        if let hit = cache[key] { return hit }
        let img = make()
        cache[key] = img
        return img
    }
}
