import CoreGraphics
import Foundation

/// The pet's runtime driver. Owns the scheduler + current PetState and updates
/// on each tick from the outside timer. Media snapshot is consulted only to
/// switch between free-roam and progress-follow modes; **battery is not an
/// input at all**.
public final class PetController {
    public private(set) var state: PetState
    private let scheduler: PetActionScheduler
    private let layout: LayoutEngine
    private let spriteHalfWidth: CGFloat

    private var nextActionAt: Date?
    private var currentDecision: PetActionScheduler.Decision?

    /// Freeze free-roam progression, useful during app-frontmost pauses.
    public var isPaused: Bool = false

    public init(
        seed: UInt64,
        layout: LayoutEngine,
        spriteHalfWidth: CGFloat = 8,
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

        // Progress-follow mode preempts free-roam.
        if media.canFollowProgress, let fraction = media.progressFraction(at: now) {
            let targetX = layout.petGroundX(fraction: fraction, spriteHalfWidth: spriteHalfWidth)
            state.action = .progressFollow
            state.facing = fraction >= (Double(state.position.x - layout.regions.middle.minX) / Double(max(1, layout.regions.middle.width))) ? .right : .left
            state.position.x = targetX
            state.position.y = layout.regions.middle.maxY - 4
            return
        }

        // Free-roam mode.
        if nextActionAt == nil || (nextActionAt.map { now >= $0 } ?? false) {
            let time = WorldTime(from: now)
            let decision = scheduler.decideNext(at: time)
            currentDecision = decision
            nextActionAt = now.addingTimeInterval(decision.holdSeconds)
            state.action = decision.action
        }
    }

    /// Advance the sprite frame index. Called from a separate frame timer at
    /// the current action's suggested FPS (see PetAction.suggestedFPS).
    public func advanceFrame() {
        state.frameIndex &+= 1
    }
}
