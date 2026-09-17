import CoreGraphics
import Foundation

/// Static layout for the Touch Bar strip.
///
/// Coordinate convention: **flipped view** (`isFlipped = true`), origin at
/// top-left. All widths and heights are in points; the renderer separately
/// applies `contentsScale = backingScaleFactor` for pixel alignment.
///
/// Region shares are the initial allocation from the plan; percentages are
/// resolved at runtime against the measured bounds so they scale with any
/// future Touch Bar geometry.
public struct LayoutEngine: Equatable {
    public struct Regions: Equatable {
        public let full: CGRect
        public let sky: CGRect          // full width; time-of-day panorama
        public let battery: CGRect      // left 9 %
        public let middle: CGRect       // 9 % .. 67 % — pet accessible ground
        public let right: CGRect        // 67 % .. 100 % — controls
        public let brightness: CGRect
        public let volume: CGRect
        public let playPause: CGRect
    }

    public static let batteryShare: CGFloat    = 0.09
    public static let middleShare: CGFloat     = 0.58
    /// Right region split: brightness 40 % / volume 40 % / play-pause 20 %.
    public static let brightnessShareOfRight: CGFloat = 0.40
    public static let volumeShareOfRight: CGFloat     = 0.40
    public static let playPauseShareOfRight: CGFloat  = 0.20

    /// Minimum touch-target width in points. Regions never shrink below this,
    /// even if the strip is measured smaller than expected.
    public static let minimumControlWidth: CGFloat = 30

    public let bounds: CGRect
    public let backingScale: CGFloat

    public init(bounds: CGRect, backingScale: CGFloat) {
        precondition(bounds.width > 0 && bounds.height > 0, "bounds must be positive")
        precondition(backingScale > 0, "backingScale must be positive")
        self.bounds = bounds
        self.backingScale = backingScale
    }

    public var regions: Regions {
        let w = bounds.width
        let h = bounds.height
        let x = bounds.minX
        let y = bounds.minY

        let batteryW = max(LayoutEngine.minimumControlWidth, w * LayoutEngine.batteryShare)
        let rightW   = max(3 * LayoutEngine.minimumControlWidth,
                           w * (1 - LayoutEngine.batteryShare - LayoutEngine.middleShare))
        let middleW  = max(0, w - batteryW - rightW)

        let battery = CGRect(x: x, y: y, width: batteryW, height: h)
        let middle  = CGRect(x: x + batteryW, y: y, width: middleW, height: h)
        let right   = CGRect(x: x + batteryW + middleW, y: y, width: rightW, height: h)

        let brightnessW = right.width * LayoutEngine.brightnessShareOfRight
        let volumeW     = right.width * LayoutEngine.volumeShareOfRight
        let playW       = right.width - brightnessW - volumeW

        let brightness = CGRect(x: right.minX,                       y: y, width: brightnessW, height: h)
        let volume     = CGRect(x: right.minX + brightnessW,         y: y, width: volumeW,     height: h)
        let playPause  = CGRect(x: right.minX + brightnessW + volumeW, y: y, width: playW,     height: h)

        return Regions(
            full: bounds,
            sky: bounds,
            battery: battery,
            middle: middle,
            right: right,
            brightness: brightness,
            volume: volume,
            playPause: playPause
        )
    }

    /// Given a fractional position `[0, 1]` along the middle-region ground,
    /// returns the x point where the pet's ground anchor should sit. The
    /// caller passes the pet sprite's half-width as `spriteHalfWidth` so we
    /// inset both ends and the sprite never clips the region edge.
    public func petGroundX(fraction: Double, spriteHalfWidth: CGFloat) -> CGFloat {
        let m = regions.middle
        let inset = max(spriteHalfWidth, 2)
        let usable = max(0, m.width - 2 * inset)
        let clamped = min(1.0, max(0.0, fraction))
        return m.minX + inset + CGFloat(clamped) * usable
    }

    /// Snap a point to physical-pixel-aligned coordinates. Prevents subpixel
    /// smearing of pixel-art assets.
    public func snap(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x * backingScale).rounded() / backingScale,
            y: (point.y * backingScale).rounded() / backingScale
        )
    }
}
