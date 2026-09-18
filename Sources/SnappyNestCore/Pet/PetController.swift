import CoreGraphics
import Foundation

/// The pet's runtime driver. Owns the scheduler + current PetState and updates
/// on each tick from the outside timer. Media snapshot is consulted only to
/// switch between free-roam and progress-follow modes; **battery is not an
/// input at all**.
///
/// Free-roam walks and dashes move the pet toward a seeded destination each
/// tick; taps on the pet play a short reaction and taps on the ground send the
/// pet there.
public final class PetController {
    public private(set) var state: PetState
    private let scheduler: PetActionScheduler
    private let layout: LayoutEngine
    private let spriteHalfWidth: CGFloat

    private var nextActionAt: Date?
    private var currentDecision: PetActionScheduler.Decision?

    // Movement
    private var targetX: CGFloat?
    private var arrivalAction: PetAction = .idle
    private var arrivalHold: TimeInterval = 0
    private var lastTickAt: Date?
    private var isFollowingProgress = false

    // Tap reactions
    private var reactionUntil: Date?
    private var preReactionAction: PetAction = .idle
    private var lastTapAt: Date?

    /// Freeze free-roam progression, useful during app-frontmost pauses.
    public var isPaused: Bool = false

    /// Ground speed in points per second.
    public static let walkSpeed: CGFloat = 14
    public static let dashSpeed: CGFloat = 45
    /// How long a tap reaction plays before the previous action resumes.
    public static let reactionHold: TimeInterval = 1.8
    /// A second tap inside this window escalates `.happy` to `.surprised`.
    public static let tapChainWindow: TimeInterval = 2.0
    /// Time spent inspecting the spot after a tap-to-walk arrives.
    public static let inspectHold: TimeInterval = 3.0
    /// Largest tick interval used for movement, so a stalled timer cannot
    /// teleport the pet.
    private static let maxTickInterval: TimeInterval = 1.0

    public init(
        seed: UInt64,
        layout: LayoutEngine,
        spriteHalfWidth: CGFloat = 12,
        initial: PetState? = nil
    ) {
        self.layout = layout
        self.spriteHalfWidth = spriteHalfWidth
        self.scheduler = PetActionScheduler(seed: seed)
        let middle = layout.regions.middle
        let start = initial ?? PetState(
            action: .idle,
            facing: .right,
            position: CGPoint(x: middle.midX, y: middle.maxY - 4),
            frameIndex: 0
        )
        self.state = start
    }

    /// One tick of the controller. Call from a timer roughly at each media
    /// sample cadence (~4 Hz is enough; the sprite frame timer is separate).
    public func tick(now: Date, media: MediaSnapshot) {
        guard !isPaused else { return }
        let dt = lastTickAt.map { max(0, min(Self.maxTickInterval, now.timeIntervalSince($0))) } ?? 0
        lastTickAt = now

        // A tap reaction freezes everything else until it expires.
        if let until = reactionUntil {
            if now < until { return }
            reactionUntil = nil
            state.action = preReactionAction
        }

        // Progress-follow mode preempts free-roam.
        if media.canFollowProgress, let fraction = media.progressFraction(at: now) {
            isFollowingProgress = true
            targetX = nil
            let targetX = layout.petGroundX(fraction: fraction, spriteHalfWidth: spriteHalfWidth)
            state.action = .progressFollow
            state.facing = fraction >= (Double(state.position.x - layout.regions.middle.minX) / Double(max(1, layout.regions.middle.width))) ? .right : .left
            state.position.x = targetX
            state.position.y = layout.regions.middle.maxY - 4
            return
        }
        if isFollowingProgress {
            // Leaving progress-follow: decide afresh instead of resuming a
            // stale action.
            isFollowingProgress = false
            nextActionAt = nil
        }

        // Free-roam mode.
        if nextActionAt == nil || (nextActionAt.map { now >= $0 } ?? false) {
            let time = WorldTime(from: now)
            let decision = scheduler.decideNext(at: time)
            currentDecision = decision
            nextActionAt = now.addingTimeInterval(decision.holdSeconds)
            state.action = decision.action
            targetX = nil
            if decision.action == .walk || decision.action == .dash {
                let destination = layout.petGroundX(
                    fraction: scheduler.nextTargetFraction(),
                    spriteHalfWidth: spriteHalfWidth
                )
                setTarget(destination, arrival: .idle, hold: 0)
            }
        }

        advanceTowardTarget(dt: dt, now: now)
    }

    /// The user tapped the pet. Plays `.happy`; a second tap inside
    /// `tapChainWindow` escalates to `.surprised`. Works in every mode.
    public func tapPet(now: Date) {
        let chained = lastTapAt.map { now.timeIntervalSince($0) < Self.tapChainWindow } ?? false
        if reactionUntil == nil {
            preReactionAction = state.action
        }
        state.action = (chained && state.action == .happy) ? .surprised : .happy
        state.frameIndex = 0
        reactionUntil = now.addingTimeInterval(Self.reactionHold)
        lastTapAt = now
    }

    /// The user tapped empty ground at scene `x`. Free-roam only: the pet
    /// walks (or dashes when far) there and inspects the spot on arrival.
    public func walkTo(x: CGFloat, now: Date) {
        guard !isFollowingProgress else { return }
        let middle = layout.regions.middle
        let inset = max(spriteHalfWidth, 2)
        let clamped = min(middle.maxX - inset, max(middle.minX + inset, x))
        let distance = abs(clamped - state.position.x)
        let action: PetAction = distance > middle.width * 0.4 ? .dash : .walk
        let speed = action == .dash ? Self.dashSpeed : Self.walkSpeed
        let travel = TimeInterval(distance / speed)

        state.action = action
        setTarget(clamped, arrival: .inspect, hold: Self.inspectHold)
        // Keep the scheduler from overriding the trip or the inspection.
        nextActionAt = now.addingTimeInterval(travel + Self.inspectHold)
        currentDecision = nil
    }

    /// Advance the sprite frame index. Called from a separate frame timer at
    /// the current action's suggested FPS (see PetAction.suggestedFPS).
    public func advanceFrame() {
        state.frameIndex &+= 1
    }

    // MARK: - Movement

    private func setTarget(_ x: CGFloat, arrival: PetAction, hold: TimeInterval) {
        targetX = x
        arrivalAction = arrival
        arrivalHold = hold
        if abs(x - state.position.x) > 0.5 {
            state.facing = x > state.position.x ? .right : .left
        }
    }

    private func advanceTowardTarget(dt: TimeInterval, now: Date) {
        guard let target = targetX else { return }
        state.position.y = layout.regions.middle.maxY - 4
        let speed = state.action == .dash ? Self.dashSpeed : Self.walkSpeed
        let step = speed * CGFloat(dt)
        let remaining = target - state.position.x
        if abs(remaining) <= max(step, 0.5) {
            state.position.x = target
            targetX = nil
            state.action = arrivalAction
            if arrivalHold > 0 {
                nextActionAt = now.addingTimeInterval(arrivalHold)
            }
        } else {
            state.position.x += remaining > 0 ? step : -step
        }
    }
}
