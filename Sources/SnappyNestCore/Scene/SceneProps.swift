import CoreGraphics
import Foundation

public enum SceneProp: String, CaseIterable {
    case crystal
    case sprout
    case cloud
    case puddle
    case lantern
    case stargazingSpot
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
    /// Distribute props inside the middle region. Positions are proportional
    /// to the region width so re-measuring the Touch Bar just re-scales them.
    public static func defaultObjects(inside middle: CGRect) -> [SceneObject] {
        let baselineY = middle.maxY - 4  // ground line, flipped coords: max is bottom
        func at(_ frac: CGFloat, _ prop: SceneProp) -> SceneObject {
            SceneObject(
                prop: prop,
                position: CGPoint(x: middle.minX + middle.width * frac, y: baselineY)
            )
        }
        return [
            at(0.08, .puddle),
            at(0.22, .sprout),
            at(0.40, .crystal),
            at(0.58, .lantern),
            at(0.76, .cloud),
            at(0.92, .stargazingSpot)
        ]
    }
}
