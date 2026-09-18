import CoreGraphics
import Foundation

/// The pet's runtime driver. Owns the scheduler + current PetState and updates
/// on each tick from the outside timer. Media snapshot is consulted only on
/// the playback page, where the pet is the playhead; **battery is not an
/// input at all**.
///
/// The pet travels with the camera between the three pages (`Mode`):
/// - `.roam` (world): free-roam walks and dashes toward seeded destinations;
///   taps on the pet play a reaction, one tap on the ground walks there and
///   a quick second tap sprints.
/// - `.playback`: the pet walks the trail as media progresses and can be
///   scrubbed along it to seek.
/// - `.workshop` (controls): the pet dashes beside the controls, puts on a
///   hard hat and tinkers until it leaves.
public final class PetController {
    public enum Mode: Equatable { case roam, playback, workshop }

    public private(set) var state: PetState
    public private(set) var mode: Mode = .roam
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
    private var lastMedia: MediaSnapshot = .unknown

    // Tap reactions
    private var reactionUntil: Date?
    private var preReactionAction: PetAction = .idle
    private var lastTapAt: Date?
    private var lastGroundTapAt: Date?

    // Playback
    private var isScrubbing = false
    private var seekHoldUntil: Date?
    /// A trail tap sends the pet dashing to the tapped fraction; the seek
    /// hold starts when it arrives so a slow readback cannot pull it back.
    private var isDashingToSeek = false

    // Mode transitions: the hat comes off before the pet leaves the workshop.
    private var queuedMode: Mode?
    private var transitionUntil: Date?

    /// Freeze free-roam progression, useful during app-frontmost pauses.
    public var isPaused: Bool = false

    /// Ground speed in points per second.
    public static let walkSpeed: CGFloat = 14
    public static let dashSpeed: CGFloat = 45
    /// How long a tap reaction plays before the previous action resumes.
    public static let reactionHold: TimeInterval = 1.8
    /// A second tap inside this window escalates `.happy` to `.surprised`.
    public static let tapChainWindow: TimeInterval = 2.0
    /// A second ground tap inside this window (and near the first target)
    /// upgrades the walk to a sprint.
    public static let sprintTapWindow: TimeInterval = 0.6
    public static let sprintTapDistance: CGFloat = 40
    /// Time spent inspecting the spot after a tap-to-walk arrives.
    public static let inspectHold: TimeInterval = 3.0
    /// Length of the hat on/off clips (4 frames at 10 fps).
    public static let suitDuration: TimeInterval = 0.4
    /// After a scrub or trail tap the pet holds the seek position this long
    /// so the source's readback can catch up before it steers the pet again.
    public static let seekHold: TimeInterval = 1.5
    /// Largest tick interval used for movement, so a stalled timer cannot
    /// teleport the pet.
    private static let maxTickInterval: TimeInterval = 1.0
    /// Gap between the workshop pet and the first control.
    public static let workshopGap: CGFloat = 20

    public init(
        seed: UInt64,
        layout: LayoutEngine,
        spriteHalfWidth: CGFloat = 12,
        initial: PetState? = nil
    ) {
        self.layout = layout
        self.spriteHalfWidth = spriteHalfWidth
        self.scheduler = PetActionScheduler(seed: seed)
        let middle = layout.with(page: .world).regions.middle
        let start = initial ?? PetState(
            action: .idle,
            facing: .right,
            position: CGPoint(x: middle.midX, y: middle.maxY - 4),
            frameIndex: 0
        )
        self.state = start
    }

    /// Where the hard-hat pet stands on the controls page: just left of the
    /// cluster, facing it.
    public var workshopX: CGFloat {
        let controls = layout.with(page: .controls).regions
        return max(controls.full.minX + spriteHalfWidth, controls.brightness.minX - Self.workshopGap)
    }

    private var groundY: CGFloat { layout.bounds.maxY - 4 }

    // MARK: - Modes

    /// The camera settled on a page; the pet follows. Leaving the workshop
    /// first plays `.suitDown`, then the new mode takes over.
    public func enter(_ newMode: Mode, now: Date) {
        guard newMode != mode || queuedMode != nil else { return }
        reactionUntil = nil
        isScrubbing = false
        if state.action.wearsHardHat && state.action != .suitDown {
            state.action = .suitDown
            state.frameIndex = 0
            targetX = nil
            queuedMode = newMode
            transitionUntil = now.addingTimeInterval(Self.suitDuration)
            return
        }
        queuedMode = nil
        transitionUntil = nil
        apply(newMode, now: now)
    }

    private func apply(_ newMode: Mode, now: Date) {
        mode = newMode
        seekHoldUntil = nil
        isDashingToSeek = false
        targetX = nil
        currentDecision = nil
        state.frameIndex = 0
        switch newMode {
        case .roam:
            state.action = .idle
            nextActionAt = nil
        case .playback:
            if let fraction = lastMedia.progressFraction(at: now) {
                state.action = .dash
                setTarget(layout.trailX(fraction: fraction, spriteHalfWidth: spriteHalfWidth),
                          arrival: .progressFollow, hold: 0)
            } else {
                state.action = .walk
                setTarget(layout.trailX(fraction: 0, spriteHalfWidth: spriteHalfWidth),
                          arrival: .inspect, hold: Self.inspectHold)
            }
            nextActionAt = nil
        case .workshop:
            state.action = .dash
            setTarget(workshopX, arrival: .suitUp, hold: Self.suitDuration)
            nextActionAt = nil
        }
    }

    /// One tick of the controller. Call from a timer roughly at each media
    /// sample cadence (~4 Hz is enough; the sprite frame timer is separate).
    public func tick(now: Date, media: MediaSnapshot) {
        guard !isPaused else { return }
        lastMedia = media
        let dt = lastTickAt.map { max(0, min(Self.maxTickInterval, now.timeIntervalSince($0))) } ?? 0
        lastTickAt = now

        // Finishing a hat-off clip applies the mode that was waiting on it.
        if let until = transitionUntil {
            if now < until { return }
            transitionUntil = nil
            if let queued = queuedMode {
                queuedMode = nil
                apply(queued, now: now)
            }
        }

        // A tap reaction freezes everything else until it expires.
        if let until = reactionUntil {
            if now < until { return }
            reactionUntil = nil
            state.action = preReactionAction
        }

        switch mode {
        case .roam:     tickRoam(now: now, dt: dt)
        case .playback: tickPlayback(now: now, dt: dt, media: media)
        case .workshop: tickWorkshop(now: now, dt: dt)
        }
    }

    private func tickRoam(now: Date, dt: TimeInterval) {
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

    private func tickPlayback(now: Date, dt: TimeInterval, media: MediaSnapshot) {
        if isScrubbing { return }
        let holdingSeek = seekHoldUntil.map { now < $0 } ?? false
        if !holdingSeek { seekHoldUntil = nil }
        let fraction = media.progressFraction(at: now)

        if targetX != nil {
            // Arriving on page entry: steer to the live playhead. A trail-tap
            // dash keeps its target; the hold starts on arrival.
            if !isDashingToSeek, let f = fraction, arrivalAction == .progressFollow {
                targetX = layout.trailX(fraction: f, spriteHalfWidth: spriteHalfWidth)
            }
            advanceTowardTarget(dt: dt, now: now)
            if targetX == nil && isDashingToSeek {
                isDashingToSeek = false
                seekHoldUntil = now.addingTimeInterval(Self.seekHold)
            }
            return
        }

        if let f = fraction {
            if holdingSeek { return }
            let x = layout.trailX(fraction: f, spriteHalfWidth: spriteHalfWidth)
            if state.action != .progressFollow { state.frameIndex = 0 }
            state.action = .progressFollow
            if abs(x - state.position.x) > 0.5 { state.facing = x > state.position.x ? .right : .left }
            state.position.x = x
            state.position.y = groundY
            return
        }

        // Nothing to follow: rest on the trail. Only restful actions cycle.
        if state.action == .progressFollow { state.action = .idle; nextActionAt = nil }
        if nextActionAt == nil || (nextActionAt.map { now >= $0 } ?? false) {
            let decision = scheduler.decideNext(at: WorldTime(from: now))
            state.action = decision.action.isRestful ? decision.action : .idle
            nextActionAt = now.addingTimeInterval(decision.holdSeconds)
        }
    }

    private func tickWorkshop(now: Date, dt: TimeInterval) {
        if targetX != nil {
            advanceTowardTarget(dt: dt, now: now)
            return
        }
        if state.action == .suitUp, let at = nextActionAt, now >= at {
            state.action = .tinker
            state.frameIndex = 0
            nextActionAt = nil
        } else if !state.action.wearsHardHat {
            // e.g. a reaction restored an older action: get back to work.
            state.action = .suitUp
            state.frameIndex = 0
            nextActionAt = now.addingTimeInterval(Self.suitDuration)
        }
    }

    // MARK: - Taps

    /// The user tapped the pet. Plays `.happy`; a second tap inside
    /// `tapChainWindow` escalates to `.surprised`. Works in every mode.
    public func tapPet(now: Date) {
        guard transitionUntil == nil else { return }
        let chained = lastTapAt.map { now.timeIntervalSince($0) < Self.tapChainWindow } ?? false
        if reactionUntil == nil {
            preReactionAction = state.action
        }
        state.action = (chained && state.action == .happy) ? .surprised : .happy
        state.frameIndex = 0
        reactionUntil = now.addingTimeInterval(Self.reactionHold)
        lastTapAt = now
    }

    /// The user tapped empty ground at scene `x` (world page only): the pet
    /// walks there and inspects the spot. A second tap within
    /// `sprintTapWindow` near the same spot upgrades the trip to a sprint.
    public func walkTo(x: CGFloat, now: Date) {
        guard mode == .roam, transitionUntil == nil else { return }
        let middle = layout.with(page: .world).regions.middle
        let inset = max(spriteHalfWidth, 2)
        let clamped = min(middle.maxX - inset, max(middle.minX + inset, x))

        let quickSecondTap = lastGroundTapAt.map { now.timeIntervalSince($0) < Self.sprintTapWindow } ?? false
        let nearCurrentTrip = targetX.map { abs($0 - clamped) < Self.sprintTapDistance } ?? false
        let action: PetAction = (quickSecondTap && nearCurrentTrip && state.action == .walk) ? .dash : .walk
        lastGroundTapAt = now

        let distance = abs(clamped - state.position.x)
        let speed = action == .dash ? Self.dashSpeed : Self.walkSpeed
        let travel = TimeInterval(distance / speed)

        reactionUntil = nil
        state.action = action
        setTarget(clamped, arrival: .inspect, hold: Self.inspectHold)
        // Keep the scheduler from overriding the trip or the inspection.
        nextActionAt = now.addingTimeInterval(travel + Self.inspectHold)
        currentDecision = nil
    }

    // MARK: - Playback scrubbing

    /// The user put a finger on the pet on the playback page. The pet is
    /// carried along the trail until `endScrub`.
    public func beginScrub(now: Date) {
        guard mode == .playback, transitionUntil == nil else { return }
        isScrubbing = true
        reactionUntil = nil
        targetX = nil
        isDashingToSeek = false
        state.action = .dash
        state.frameIndex = 0
    }

    public func scrub(x: CGFloat, now: Date) {
        guard isScrubbing else { return }
        let fraction = layout.trailFraction(x: x, spriteHalfWidth: spriteHalfWidth)
        let clamped = layout.trailX(fraction: fraction, spriteHalfWidth: spriteHalfWidth)
        if abs(clamped - state.position.x) > 0.5 {
            state.facing = clamped > state.position.x ? .right : .left
        }
        state.position.x = clamped
        state.position.y = groundY
    }

    /// Ends the scrub. Returns the trail fraction the owner should seek to,
    /// or nil when the current media cannot be seeked.
    @discardableResult
    public func endScrub(now: Date) -> Double? {
        guard isScrubbing else { return nil }
        isScrubbing = false
        let fraction = layout.trailFraction(x: state.position.x, spriteHalfWidth: spriteHalfWidth)
        guard lastMedia.canFollowProgress else {
            state.action = .idle
            nextActionAt = nil
            return nil
        }
        seekHoldUntil = now.addingTimeInterval(Self.seekHold)
        state.action = .progressFollow
        state.frameIndex = 0
        return fraction
    }

    /// The user tapped the trail: the pet dashes to that fraction (the owner
    /// seeks there at the same time).
    public func seekTo(fraction: Double, now: Date) {
        guard mode == .playback, transitionUntil == nil, !isScrubbing else { return }
        guard lastMedia.canFollowProgress else { return }
        reactionUntil = nil
        seekHoldUntil = nil
        isDashingToSeek = true
        state.action = .dash
        setTarget(layout.trailX(fraction: fraction, spriteHalfWidth: spriteHalfWidth),
                  arrival: .progressFollow, hold: 0)
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
        state.position.y = groundY
        let speed = state.action == .dash ? Self.dashSpeed : Self.walkSpeed
        let step = speed * CGFloat(dt)
        let remaining = target - state.position.x
        if abs(remaining) <= max(step, 0.5) {
            state.position.x = target
            targetX = nil
            state.action = arrivalAction
            state.frameIndex = 0
            if arrivalAction == .suitUp { state.facing = .right }
            if arrivalHold > 0 {
                nextActionAt = now.addingTimeInterval(arrivalHold)
            }
        } else {
            if abs(remaining) > 0.5 { state.facing = remaining > 0 ? .right : .left }
            state.position.x += remaining > 0 ? step : -step
        }
    }
}
