import CoreGraphics
import Foundation

/// Static layout for the Touch Bar strip.
///
/// Coordinate convention: **flipped view** (`isFlipped = true`), origin at
/// top-left. All widths and heights are in points; the renderer separately
/// applies `contentsScale = backingScaleFactor` for pixel alignment.
///
/// The strip is a camera over three *pages* laid side by side:
///
///     [ playback ]  [ world ]  [ controls ]
///
/// Dragging the scene horizontally pans between them. Each page uses the
/// full strip; regions that do not exist on the current page are
/// `CGRect.null`, which contains no point.
public struct LayoutEngine: Equatable {
    public enum Page: Equatable, CaseIterable {
        case playback
        case world
        case controls

        /// Position in the row of pages; the camera offset is `index × width`.
        public var index: Int {
            switch self {
            case .playback: return -1
            case .world:    return 0
            case .controls: return 1
            }
        }

        public init?(index: Int) {
            guard let page = Page.allCases.first(where: { $0.index == index }) else { return nil }
            self = page
        }
    }

    public struct Regions: Equatable {
        public let page: Page
        public let full: CGRect
        public let sky: CGRect          // full width; time-of-day sky
        public let middle: CGRect       // world page: pet-accessible ground
        public let right: CGRect        // controls page: the cluster
        public let brightness: CGRect
        public let volume: CGRect
        public let battery: CGRect      // rightmost control
        // Playback page.
        public let titleBanner: CGRect  // hanging sign with the track title, left third
        public let trail: CGRect        // the pet walks this as the playhead
        public let elapsedLabel: CGRect
        public let durationLabel: CGRect
        public let previous: CGRect     // signposts, left to right
        public let playPause: CGRect
        public let next: CGRect
    }

    /// The controls page is a compact cluster centered on the strip so the
    /// scenery stays visible around it.
    public static let maximumSliderWidth: CGFloat = 180
    public static let batteryWidth: CGFloat = 72
    public static let controlGap: CGFloat = 14
    /// Minimum touch-target width in points. Regions never shrink below this,
    /// even if the strip is measured smaller than expected.
    public static let minimumControlWidth: CGFloat = 30

    /// Playback page: the title sign takes the left third, then time labels
    /// flank the trail and signposts sit at the right.
    public static let titleBannerFraction: CGFloat = 1 / 3
    public static let timeLabelWidth: CGFloat = 40
    public static let signWidth: CGFloat = 34
    public static let signGap: CGFloat = 6
    public static let playbackInset: CGFloat = 8

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
                right: .null, brightness: .null, volume: .null, battery: .null,
                titleBanner: .null, trail: .null, elapsedLabel: .null, durationLabel: .null,
                previous: .null, playPause: .null, next: .null
            )
        case .controls:
            let gap = LayoutEngine.controlGap
            let fixed = LayoutEngine.batteryWidth + 2 * gap
            let sliderW = max(LayoutEngine.minimumControlWidth,
                              min(LayoutEngine.maximumSliderWidth, (w - fixed) / 2))
            let clusterW = 2 * sliderW + fixed
            let startX = x + max(0, (w - clusterW) / 2)
            let right = CGRect(x: startX, y: y, width: clusterW, height: h)
            let brightness = CGRect(x: startX, y: y, width: sliderW, height: h)
            let volume = CGRect(x: brightness.maxX + gap, y: y, width: sliderW, height: h)
            let battery = CGRect(x: volume.maxX + gap, y: y, width: LayoutEngine.batteryWidth, height: h)
            return Regions(
                page: .controls, full: bounds, sky: bounds, middle: .null,
                right: right, brightness: brightness, volume: volume, battery: battery,
                titleBanner: .null, trail: .null, elapsedLabel: .null, durationLabel: .null,
                previous: .null, playPause: .null, next: .null
            )
        case .playback:
            let inset = LayoutEngine.playbackInset
            let sign = LayoutEngine.signWidth
            let gap = LayoutEngine.signGap
            let label = LayoutEngine.timeLabelWidth
            let next = CGRect(x: x + w - inset - sign, y: y, width: sign, height: h)
            let playPause = CGRect(x: next.minX - gap - sign, y: y, width: sign, height: h)
            let previous = CGRect(x: playPause.minX - gap - sign, y: y, width: sign, height: h)
            let durationLabel = CGRect(x: previous.minX - gap - label, y: y, width: label, height: h)
            let bannerW = max(LayoutEngine.minimumControlWidth, (w * LayoutEngine.titleBannerFraction).rounded() - inset)
            let titleBanner = CGRect(x: x + inset, y: y, width: bannerW, height: h)
            let elapsedLabel = CGRect(x: titleBanner.maxX + gap, y: y, width: label, height: h)
            let trailStart = elapsedLabel.maxX + gap
            let trail = CGRect(x: trailStart, y: y,
                               width: max(LayoutEngine.minimumControlWidth, durationLabel.minX - gap - trailStart),
                               height: h)
            return Regions(
                page: .playback, full: bounds, sky: bounds, middle: .null,
                right: .null, brightness: .null, volume: .null, battery: .null,
                titleBanner: titleBanner, trail: trail, elapsedLabel: elapsedLabel, durationLabel: durationLabel,
                previous: previous, playPause: playPause, next: next
            )
        }
    }

    /// Given a fractional position `[0, 1]` along the middle-region ground,
    /// returns the x point where the pet's ground anchor should sit. The
    /// caller passes the pet sprite's half-width as `spriteHalfWidth` so we
    /// inset both ends and the sprite never clips the region edge.
    public func petGroundX(fraction: Double, spriteHalfWidth: CGFloat) -> CGFloat {
        Self.groundX(fraction: fraction, in: with(page: .world).regions.middle, spriteHalfWidth: spriteHalfWidth)
    }

    /// Playback page: the x on the trail for a media progress fraction.
    public func trailX(fraction: Double, spriteHalfWidth: CGFloat) -> CGFloat {
        Self.groundX(fraction: fraction, in: with(page: .playback).regions.trail, spriteHalfWidth: spriteHalfWidth)
    }

    /// Inverse of `trailX`: the progress fraction for an x on the trail.
    public func trailFraction(x: CGFloat, spriteHalfWidth: CGFloat) -> Double {
        let t = with(page: .playback).regions.trail
        let inset = max(spriteHalfWidth, 2)
        let usable = max(1, t.width - 2 * inset)
        return Double(min(1, max(0, (x - t.minX - inset) / usable)))
    }

    private static func groundX(fraction: Double, in region: CGRect, spriteHalfWidth: CGFloat) -> CGFloat {
        let inset = max(spriteHalfWidth, 2)
        let usable = max(0, region.width - 2 * inset)
        let clamped = min(1.0, max(0.0, fraction))
        return region.minX + inset + CGFloat(clamped) * usable
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
