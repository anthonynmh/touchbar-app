import CoreGraphics
import Foundation

/// Static layout for the Touch Bar strip.
///
/// Coordinate convention: **flipped view** (`isFlipped = true`), origin at
/// top-left. All widths and heights are in points; the renderer separately
/// applies `contentsScale = backingScaleFactor` for pixel alignment.
///
/// The strip is a camera over two *pages* laid side by side: the world and,
/// to its right, the controls (sliders, play/pause, battery). Dragging the
/// scene horizontally pans between them. Each page uses the full strip;
/// regions that do not exist on the current page are `CGRect.null`, which
/// contains no point.
public struct LayoutEngine: Equatable {
    public enum Page: Equatable, CaseIterable {
        case world
        case controls
    }

    public struct Regions: Equatable {
        public let page: Page
        public let full: CGRect
        public let sky: CGRect          // full width; time-of-day sky
        public let middle: CGRect       // world page: pet-accessible ground
        public let right: CGRect        // controls page: the whole strip
        public let brightness: CGRect
        public let volume: CGRect
        public let playPause: CGRect
        public let battery: CGRect      // rightmost control
    }

    /// The controls page is a compact cluster centered on the strip so the
    /// scenery stays visible around it.
    public static let maximumSliderWidth: CGFloat = 180
    public static let playPauseWidth: CGFloat = 44
    public static let batteryWidth: CGFloat = 72
    public static let controlGap: CGFloat = 14
    /// Minimum touch-target width in points. Regions never shrink below this,
    /// even if the strip is measured smaller than expected.
    public static let minimumControlWidth: CGFloat = 30

    public let bounds: CGRect
    public let backingScale: CGFloat
    public let page: Page

    public init(bounds: CGRect, backingScale: CGFloat, page: Page = .world) {
        precondition(bounds.width > 0 && bounds.height > 0, "bounds must be positive")
        precondition(backingScale > 0, "backingScale must be positive")
        self.bounds = bounds
        self.backingScale = backingScale
        self.page = page
    }

    /// The same geometry on another page.
    public func with(page: Page) -> LayoutEngine {
        LayoutEngine(bounds: bounds, backingScale: backingScale, page: page)
    }

    public var regions: Regions {
        let w = bounds.width
        let h = bounds.height
        let x = bounds.minX
        let y = bounds.minY
        switch page {
        case .world:
            return Regions(
                page: .world, full: bounds, sky: bounds, middle: bounds,
                right: .null, brightness: .null, volume: .null, playPause: .null, battery: .null
            )
        case .controls:
            let gap = LayoutEngine.controlGap
            let fixed = LayoutEngine.playPauseWidth + LayoutEngine.batteryWidth + 3 * gap
            let sliderW = max(LayoutEngine.minimumControlWidth,
                              min(LayoutEngine.maximumSliderWidth, (w - fixed) / 2))
            let clusterW = 2 * sliderW + fixed
            let startX = x + max(0, (w - clusterW) / 2)
            let right = CGRect(x: startX, y: y, width: clusterW, height: h)
            let brightness = CGRect(x: startX, y: y, width: sliderW, height: h)
            let volume = CGRect(x: brightness.maxX + gap, y: y, width: sliderW, height: h)
            let playPause = CGRect(x: volume.maxX + gap, y: y, width: LayoutEngine.playPauseWidth, height: h)
            let battery = CGRect(x: playPause.maxX + gap, y: y, width: LayoutEngine.batteryWidth, height: h)
            return Regions(
                page: .controls, full: bounds, sky: bounds, middle: .null,
                right: right, brightness: brightness, volume: volume, playPause: playPause, battery: battery
            )
        }
    }

    /// Given a fractional position `[0, 1]` along the middle-region ground,
    /// returns the x point where the pet's ground anchor should sit. The
    /// caller passes the pet sprite's half-width as `spriteHalfWidth` so we
    /// inset both ends and the sprite never clips the region edge.
    public func petGroundX(fraction: Double, spriteHalfWidth: CGFloat) -> CGFloat {
        let m = with(page: .world).regions.middle
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
