import CoreGraphics
import Foundation

public enum PetAction: String, CaseIterable, Equatable, Hashable {
    case idle
    case blink
    case walk
    case dash
    case jump
    case inspect
    case splash
    case stargaze
    case celebrate
    case sleep
    case wake
    case progressFollow

    public var suggestedFPS: Int {
        switch self {
        case .idle, .blink, .sleep:              return 4
        case .inspect, .splash, .stargaze:        return 6
        case .walk, .progressFollow:              return 8
        case .jump, .celebrate, .wake:            return 10
        case .dash:                               return 12
        }
    }

    public var isRestful: Bool {
        switch self {
        case .idle, .blink, .sleep, .stargaze: return true
        default:                                return false
        }
    }
}

public enum PetFacing: Equatable { case left, right }

public struct PetState: Equatable {
    public var action: PetAction
    public var facing: PetFacing
    public var position: CGPoint       // scene coords (flipped: y=0 at top)
    public var frameIndex: Int         // current clip frame

    public init(action: PetAction, facing: PetFacing, position: CGPoint, frameIndex: Int) {
        self.action = action
        self.facing = facing
        self.position = position
        self.frameIndex = frameIndex
    }

    public static let placeholder = PetState(
        action: .idle,
        facing: .right,
        position: .zero,
        frameIndex: 0
    )
}
