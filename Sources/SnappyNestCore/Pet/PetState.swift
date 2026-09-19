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
    /// Reaction to a tap. Never scheduled: no entry in the scheduler weights.
    case happy
    /// Reaction to a second tap in quick succession. Never scheduled.
    case surprised
    /// Controls page: the hard hat drops onto the pet's head. Never scheduled.
    case suitUp
    /// Controls page: hard hat on, spanner in paw, idling. Never scheduled.
    case tinker
    /// Leaving the controls page: the hat pops back off. Never scheduled.
    case suitDown
    /// Page change: the pet poofs out of its old spot. Never scheduled.
    case teleportOut
    /// Page change: the pet poofs back in at its spot on the new page. Never
    /// scheduled.
    case teleportIn

    public var suggestedFPS: Int {
        switch self {
        case .idle, .blink, .sleep:              return 4
        case .inspect, .splash, .stargaze:        return 6
        case .walk, .progressFollow:              return 8
        case .jump, .celebrate, .wake:            return 10
        case .happy, .surprised:                  return 10
        case .suitUp, .suitDown:                  return 10
        case .teleportOut, .teleportIn:           return 10
        case .tinker:                             return 4
        case .dash:                               return 12
        }
    }

    public var isRestful: Bool {
        switch self {
        case .idle, .blink, .sleep, .stargaze, .tinker: return true
        default:                                return false
        }
    }

    /// Number of distinct sprite frames in this action's clip. Sprites and
    /// tests index frames with `frameIndex % frameCount`.
    public var frameCount: Int {
        switch self {
        case .idle, .sleep, .stargaze, .inspect:  return 2
        case .blink:                              return 4
        case .walk, .progressFollow, .dash:       return 2
        case .jump, .happy:                       return 4
        case .celebrate, .splash, .wake:          return 2
        case .surprised:                          return 3
        case .suitUp, .tinker, .suitDown:         return 4
        case .teleportOut, .teleportIn:           return 4
        }
    }

    /// True for the two tap reactions; they override the schedule briefly.
    public var isReaction: Bool {
        self == .happy || self == .surprised
    }

    /// True while the pet wears the hard hat (controls page).
    public var wearsHardHat: Bool {
        self == .suitUp || self == .tinker || self == .suitDown
    }

    /// True during the page-change poof clips.
    public var isTeleporting: Bool {
        self == .teleportOut || self == .teleportIn
    }
}

public enum PetFacing: Equatable { case left, right }

public struct PetState: Equatable {
    public var action: PetAction
    public var facing: PetFacing
    public var position: CGPoint       // scene coords (flipped: y=0 at top)
    public var frameIndex: Int         // current clip frame
    public var species: PetSpecies     // which body the renderer draws

    public init(action: PetAction, facing: PetFacing, position: CGPoint, frameIndex: Int,
                species: PetSpecies = .cat) {
        self.action = action
        self.facing = facing
        self.position = position
        self.frameIndex = frameIndex
        self.species = species
    }

    /// The sprite cell rect for hit-testing: `position` is the bottom-center
    /// ground anchor, so the cell extends upward and half a width each side.
    public func hitRect(spriteSize: CGSize) -> CGRect {
        CGRect(
            x: position.x - spriteSize.width / 2,
            y: position.y - spriteSize.height,
            width: spriteSize.width,
            height: spriteSize.height
        )
    }

    public static let placeholder = PetState(
        action: .idle,
        facing: .right,
        position: .zero,
        frameIndex: 0
    )
}
