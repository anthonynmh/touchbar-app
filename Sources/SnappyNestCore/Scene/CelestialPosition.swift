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

    public init(body: Body, point: CGPoint, sceneWidth: CGFloat, sceneHeight: CGFloat) {
        self.body = body
        self.point = point
        self.sceneWidth = sceneWidth
        self.sceneHeight = sceneHeight
    }
}

public enum CelestialSolver {
    /// Vertical inset from the top of the strip below which the sun/moon may not
    /// rise. Keeps the body's glow inside the sky region.
    public static let topInset: CGFloat = 4

    /// Height of the arc in points: the body sits this far below the peak at
    /// rise and set.
    public static let arcAmplitude: CGFloat = 15

    /// Half-width of the sprite in points — the composer insets the travel
    /// range by this so the body never overlaps the neighboring regions.
    public static let bodyHalfWidth: CGFloat = 8

    /// The sun rises at the left end of `horizontalRange` at 06:00, peaks at
    /// noon in the center, and sets at the right end at 18:00; the moon does
    /// the same over 18:00 → 06:00 with its peak at midnight.
    public static func position(
        for time: WorldTime,
        sceneSize: CGSize,
        horizontalRange: ClosedRange<CGFloat>? = nil
    ) -> CelestialPosition {
        let width = sceneSize.width
        let height = sceneSize.height
        let range = horizontalRange ?? 0...width
        let travelWidth = max(0, range.upperBound - range.lowerBound)

        let body: CelestialPosition.Body
        let progress: CGFloat
        if let p = time.dayProgress {
            body = .sun
            progress = CGFloat(p)
        } else {
            body = .moon
            progress = CGFloat(time.nightProgress ?? 0)
        }

        let x = range.lowerBound + travelWidth * progress
        // Arc: peak (smallest y in flipped coords) at progress 0.5.
        let y = topInset + arcAmplitude * (1 - CGFloat(sin(.pi * Double(progress))))

        return CelestialPosition(
            body: body,
            point: CGPoint(x: x, y: y),
            sceneWidth: width,
            sceneHeight: height
        )
    }
}
