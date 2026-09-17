import CoreGraphics
import Foundation

/// Coordinates for the sun/moon sprite in the SCENE coordinate space.
///
/// Scene coordinates are **flipped**: `y = 0` is the top of the Touch Bar strip,
/// increasing downward. Callers convert to their view's native coordinate
/// system if they aren't using `isFlipped = true`.
public struct CelestialPosition: Equatable {
    public enum Body { case sun, moon }
    public let body: Body
    public let point: CGPoint
    public let sceneWidth: CGFloat
    public let sceneHeight: CGFloat

    /// If the body straddles the midnight seam, this is the mirrored copy so
    /// the render can draw both instead of animating a backward jump.
    public let seamMirror: CGPoint?

    public init(body: Body, point: CGPoint, sceneWidth: CGFloat, sceneHeight: CGFloat, seamMirror: CGPoint? = nil) {
        self.body = body
        self.point = point
        self.sceneWidth = sceneWidth
        self.sceneHeight = sceneHeight
        self.seamMirror = seamMirror
    }
}

public enum CelestialSolver {
    /// Vertical inset from the top of the strip below which the sun/moon may not
    /// rise. Prevents overlap with any top decoration and keeps the body inside
    /// the sky region.
    public static let topInset: CGFloat = 3

    /// Fraction of the strip height reserved as the arc's amplitude.
    public static let arcAmplitude: CGFloat = 14

    /// Half-width of the sprite in points — used for seam-mirror detection.
    public static let bodyHalfWidth: CGFloat = 6

    public static func position(
        for time: WorldTime,
        sceneSize: CGSize,
        horizontalRange: ClosedRange<CGFloat>? = nil
    ) -> CelestialPosition {
        let width = sceneSize.width
        let height = sceneSize.height
        let range = horizontalRange ?? 0...width
        let travelWidth = max(0, range.upperBound - range.lowerBound)

        // The composer can constrain the body to its unobstructed world region;
        // standalone callers retain the full-panorama mapping by default.
        let x = range.lowerBound + travelWidth * CGFloat(time.fraction)

        // Vertical arc computed independently of horizontal mapping.
        // In flipped coordinates (y=0 at top), the peak is at low y and horizon
        // is at higher y.
        let arcProgress: CGFloat
        let body: CelestialPosition.Body
        switch time.dayProgress {
        case .some(let p):
            body = .sun
            arcProgress = CGFloat(p)
        case .none:
            body = .moon
            arcProgress = CGFloat(time.nightProgress ?? 0)
        }
        // Parabola: peaks at progress = 0.5 (noon or midnight).
        // y = topInset + arcAmplitude * (1 - sin(π * progress))
        let y = topInset + arcAmplitude * (1 - CGFloat(sin(.pi * Double(arcProgress))))

        // Moon seam: if the moon is near x=0 or x=width, render a mirrored
        // copy at the other side so it doesn't visually vanish at midnight.
        var seamMirror: CGPoint?
        if body == .moon {
            if x < range.lowerBound + bodyHalfWidth {
                seamMirror = CGPoint(x: x + travelWidth, y: y)
            } else if x > range.upperBound - bodyHalfWidth {
                seamMirror = CGPoint(x: x - travelWidth, y: y)
            }
        }

        return CelestialPosition(
            body: body,
            point: CGPoint(x: x, y: y),
            sceneWidth: width,
            sceneHeight: height,
            seamMirror: seamMirror
        )
    }
}
