import CoreGraphics
import Foundation

/// The pet's runtime driver. Owns the scheduler + current PetState and updates
/// on each tick from the outside timer. Media snapshot is consulted only on
/// the playback page, where the pet is the playhead; **battery is not an
/// input at all**.
///
/// The pet travels with the camera between the three pages (`Mode`). A page
/// change is a teleport: the pet poofs out where it stands (`.teleportOut`),
/// reappears at its spot on the new page (`.teleportIn`), then the page's
/// behaviour takes over:
/// - `.roam` (world): free-roam walks and dashes toward seeded destinations;
///   taps on the pet play a reaction, one tap on the ground walks there and
///   a quick second tap sprints. Tapping the nook starts keep-away
///   (`KeepAwayGame`): the pet chases the ball instead of roaming, and pet
///   and ground taps are ignored until the game ends.
/// - `.playback`: the pet lands on the playhead, walks the trail as media
///   progresses and can be scrubbed along it to seek.
/// - `.workshop` (controls): the pet lands beside the controls, puts on a
///   hard hat and tinkers until it leaves (hat off first, then the poof).
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

    // Keep-away (world page). While set, `tickRoam` drives the chase instead
    // of the scheduler and the pet ignores pet/ground taps.
    public private(set) var game: KeepAwayGame?
    /// Best rounds survived across games; the owner seeds and persists it.
    public var bestRounds: Int = 0
    /// Called when the pet catches the ball, with the rounds survived.
    public var onGameLost: ((Int) -> Void)?
    /// Ground speed used instead of the action's default (the chase ramps).
    private var speedOverride: CGFloat?

    // Playback
    private var isScrubbing = false
    private var seekHoldUntil: Date?
    /// A trail tap sends the pet dashing to the tapped fraction; the seek
    /// hold starts when it arrives so a slow readback cannot pull it back.
    private var isDashingToSeek = false

    // Mode transitions: optional hat-off, poof out, poof in at the new spot.
    // `transitionUntil` doubles as the "busy" flag the tap/scrub guards use.
    private enum Transition { case suitDown, teleportOut, teleportIn }
    private var transition: Transition?
    private var queuedMode: Mode?
    /// A species change applied at the teleport's position jump, so the old
    /// body poofs out and the new one poofs in.
    private var pendingSpecies: PetSpecies?
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
    /// Length of each poof clip (4 frames at the 8 Hz sprite timer).
    public static let teleportDuration: TimeInterval = 0.5
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

    /// The camera settled on a page; the pet follows by teleporting. Leaving
    /// the workshop first plays `.suitDown`. Calling this again mid-transition
    /// only retargets the destination page.
    public func enter(_ newMode: Mode, now: Date) {
        if transition != nil {
            queuedMode = newMode
            return
        }
        guard newMode != mode else { return }
        beginTransition(to: newMode, now: now)
    }

    /// Change the pet's body. The current one poofs out (hat off first) and
    /// the new one poofs in at its spot for the current page. A change during
    /// a transition only replaces the pending species.
    public func setSpecies(_ species: PetSpecies, now: Date) {
        guard species != state.species else {
            pendingSpecies = nil
            return
        }
        pendingSpecies = species
        if transition == nil {
            beginTransition(to: mode, now: now)
        }
    }

    /// Set the body without a poof — for the persisted choice at launch.
    public func setSpeciesImmediately(_ species: PetSpecies) {
        pendingSpecies = nil
        state.species = species
    }

    private func beginTransition(to newMode: Mode, now: Date) {
        if game != nil { endGame(now: now) }
        reactionUntil = nil
        isScrubbing = false
        targetX = nil
        queuedMode = newMode
        if state.action.wearsHardHat {
            begin(.suitDown, action: .suitDown, duration: Self.suitDuration, now: now)
        } else {
            begin(.teleportOut, action: .teleportOut, duration: Self.teleportDuration, now: now)
        }
    }

    private func begin(_ phase: Transition, action: PetAction, duration: TimeInterval, now: Date) {
        transition = phase
        state.action = action
        state.frameIndex = 0
        transitionUntil = now.addingTimeInterval(duration)
    }

    /// The current transition clip finished: move to the next phase.
    private func advanceTransition(now: Date) {
        guard let phase = transition, let queued = queuedMode else {
            transition = nil
            queuedMode = nil
            return
        }
        switch phase {
        case .suitDown:
            begin(.teleportOut, action: .teleportOut, duration: Self.teleportDuration, now: now)
        case .teleportOut:
            mode = queued
            let x = destinationX(for: queued, now: now)
            if abs(x - state.position.x) > 0.5 {
                state.facing = x > state.position.x ? .right : .left
            }
            if queued == .workshop { state.facing = .right }
            state.position = CGPoint(x: x, y: groundY)
            if let species = pendingSpecies {
                state.species = species
                pendingSpecies = nil
            }
            begin(.teleportIn, action: .teleportIn, duration: Self.teleportDuration, now: now)
        case .teleportIn:
            transition = nil
            queuedMode = nil
            transitionUntil = nil
            arrive(in: queued, now: now)
        }
    }

    /// Where the pet materialises on the page it is entering.
    private func destinationX(for newMode: Mode, now: Date) -> CGFloat {
        switch newMode {
        case .roam:
            return layout.petGroundX(fraction: scheduler.nextTargetFraction(), spriteHalfWidth: spriteHalfWidth)
        case .playback:
            return layout.trailX(fraction: lastMedia.progressFraction(at: now) ?? 0, spriteHalfWidth: spriteHalfWidth)
        case .workshop:
            return workshopX
        }
    }

    /// The poof-in finished: start the page's behaviour from the landing spot.
    private func arrive(in newMode: Mode, now: Date) {
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
            if lastMedia.progressFraction(at: now) != nil {
                state.action = .progressFollow
                nextActionAt = nil
            } else {
                state.action = .inspect
                nextActionAt = now.addingTimeInterval(Self.inspectHold)
            }
        case .workshop:
            state.action = .suitUp
            nextActionAt = now.addingTimeInterval(Self.suitDuration)
        }
    }

    /// One tick of the controller. Call from a timer roughly at each media
    /// sample cadence (~4 Hz is enough; the sprite frame timer is separate).
    public func tick(now: Date, media: MediaSnapshot) {
        guard !isPaused else { return }
        lastMedia = media
        let dt = lastTickAt.map { max(0, min(Self.maxTickInterval, now.timeIntervalSince($0))) } ?? 0
        lastTickAt = now

        // A page transition (hat off / poof out / poof in) freezes the pet;
        // each finished clip starts the next phase.
        if let until = transitionUntil {
            if now < until { return }
            advanceTransition(now: now)
            if transitionUntil != nil { return }
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
        if game != nil {
            tickGame(now: now, dt: dt)
            return
        }
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

    // MARK: - Keep-away

    public var isPlayingGame: Bool { game != nil }

    /// The user tapped the nook: start keep-away on the world page, or end
    /// the running game whatever phase it is in.
    public func toggleKeepAway(now: Date) {
        if game != nil {
            endGame(now: now)
            return
        }
        guard mode == .roam, transitionUntil == nil else { return }
        let middle = layout.with(page: .world).regions.middle
        let nookX = SceneLayout.nookX(inside: middle)
        game = KeepAwayGame(arena: middle, nookX: nookX, now: now)
        reactionUntil = nil
        targetX = nil
        currentDecision = nil
        nextActionAt = nil
        face(nookX)
        state.action = .inspect
        state.frameIndex = 0
    }

    /// The user tapped the ground at strip `x` during a game: the ball is
    /// kicked toward that side if it is slow enough. A landed kick stuns the
    /// pet for the round's reaction time (it plays `.surprised`).
    @discardableResult
    public func kickBall(atX x: CGFloat, now: Date) -> Bool {
        guard var g = game, g.kick(atX: x, petX: state.position.x, now: now) else { return false }
        game = g
        targetX = nil
        state.action = .surprised
        state.frameIndex = 0
        return true
    }

    /// Leave the game: the ball goes back to the nook (the composer draws it
    /// there once `game` is nil) and the scheduler resumes on the next tick.
    public func endGame(now: Date) {
        guard game != nil else { return }
        game = nil
        speedOverride = nil
        targetX = nil
        reactionUntil = nil
        currentDecision = nil
        nextActionAt = nil
        state.action = .idle
        state.frameIndex = 0
    }

    private func tickGame(now: Date, dt: TimeInterval) {
        guard var g = game else { return }
        let event = g.tick(dt: dt, now: now, petX: state.position.x)
        game = g
        switch event {
        case .go:
            speedOverride = g.petSpeed
            state.action = .dash
            state.frameIndex = 0
        case .caught:
            targetX = nil
            state.action = .celebrate
            state.frameIndex = 0
            bestRounds = max(bestRounds, g.roundsSurvived)
            onGameLost?(g.roundsSurvived)
        case .roundWon:
            targetX = nil
            state.action = .surprised
            state.frameIndex = 0
        case .nextRound:
            face(g.nookX)
            state.action = .inspect
            state.frameIndex = 0
        case .finished:
            endGame(now: now)
            return
        case nil:
            break
        }
        guard g.isPlaying else { return }
        guard let ballX = g.petTargetX(at: now) else {
            // Stunned by a kick: stand still, keep the surprised face.
            targetX = nil
            return
        }
        if state.action != .dash {
            state.action = .dash
            state.frameIndex = 0
        }
        setTarget(ballX, arrival: .dash, hold: 0)
        advanceTowardTarget(dt: dt, now: now)
    }

    private func face(_ x: CGFloat) {
        if abs(x - state.position.x) > 0.5 {
            state.facing = x > state.position.x ? .right : .left
        }
    }

    // MARK: - Taps

    /// The user tapped the pet. Plays `.happy`; a second tap inside
    /// `tapChainWindow` escalates to `.surprised`. Works in every mode
    /// except during keep-away, where a stun would be an exploit.
    public func tapPet(now: Date) {
        guard transitionUntil == nil, game == nil else { return }
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
        guard mode == .roam, transitionUntil == nil, game == nil else { return }
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
        let speed = speedOverride ?? (state.action == .dash ? Self.dashSpeed : Self.walkSpeed)
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
