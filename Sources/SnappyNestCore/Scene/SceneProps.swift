import CoreGraphics
import Foundation

public enum SceneProp: String, CaseIterable {
    case crystal
    case sprout
    case cloud
    case puddle
    case lantern
    case stargazingSpot
    /// The court gate: a racket leaning on a post with a ball at its foot.
    /// Tapping it opens the tennis court page.
    case courtGate
}

public struct SceneObject: Equatable {
    public let prop: SceneProp
    public let position: CGPoint   // scene coords
    public init(prop: SceneProp, position: CGPoint) {
        self.prop = prop
        self.position = position
    }
}

public enum SceneLayout {
    /// Where the court gate sits along the ground, as a fraction of the
    /// middle region. Between the sprout and the crystal.
    public static let courtGateFraction: CGFloat = 0.31
    /// Extra points around the gate prop that still count as the zone.
    public static let activityZoneSlop: CGFloat = 6
    /// Prop cell size, mirrored from the renderer so the zone rect can be
    /// computed without AppKit.
    public static let propSize = CGSize(width: 14, height: 14)

    public static func courtGateX(inside middle: CGRect) -> CGFloat {
        middle.minX + middle.width * courtGateFraction
    }

    /// The tappable activity zone: the gate prop's cell plus slop.
    public static func activityZone(inside middle: CGRect) -> CGRect {
        let x = courtGateX(inside: middle)
        let baselineY = middle.maxY - 4
        return CGRect(x: x - propSize.width / 2, y: baselineY - propSize.height,
                      width: propSize.width, height: propSize.height)
            .insetBy(dx: -activityZoneSlop, dy: -activityZoneSlop)
    }

    /// Distribute props inside the middle region. Positions are proportional
    /// to the region width so re-measuring the Touch Bar just re-scales them.
    public static func defaultObjects(inside middle: CGRect) -> [SceneObject] {
        let baselineY = middle.maxY - 4  // ground line, flipped coords: max is bottom
        let skyY = middle.minY + 11       // clouds float above the hills
        func at(_ frac: CGFloat, _ prop: SceneProp) -> SceneObject {
            SceneObject(
                prop: prop,
                position: CGPoint(x: middle.minX + middle.width * frac, y: prop == .cloud ? skyY : baselineY)
            )
        }
        return [
            at(0.08, .puddle),
            at(0.22, .sprout),
            at(courtGateFraction, .courtGate),
            at(0.40, .crystal),
            at(0.58, .lantern),
            at(0.70, .cloud),
            at(0.92, .stargazingSpot)
        ]
    }
}
