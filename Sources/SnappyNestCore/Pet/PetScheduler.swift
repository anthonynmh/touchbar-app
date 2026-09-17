import CoreGraphics
import Foundation

/// Schedules the pet's next action while free-roaming.
///
/// The scheduler is fed:
///   • the current wall-clock time (for hour-of-day action weighting only)
///   • the middle-region rect it is allowed to roam in
///   • the current media snapshot (only to decide whether progress-follow
///     mode is active — no other media data influences behavior)
///
/// It is **deliberately not fed** the battery snapshot. `PetActionScheduler`
/// has no way to receive one, so an entire class of "does battery affect
/// behavior?" bugs is impossible by construction.
public final class PetActionScheduler {
    public struct Config: Equatable {
        public var minActionSeconds: Double
        public var maxActionSeconds: Double
        public init(minActionSeconds: Double = 20, maxActionSeconds: Double = 90) {
            self.minActionSeconds = minActionSeconds
            self.maxActionSeconds = maxActionSeconds
        }
    }

    private static let baseWeights: [PetAction: Double] = [
        .idle:      4.0,
        .blink:     3.0,
        .walk:      6.0,
        .dash:      1.5,
        .jump:      2.0,
        .inspect:   3.0,
        .splash:    1.5,
        .stargaze:  2.0,
        .celebrate: 1.0,
        .sleep:     0.8
    ]

    /// Hour-of-day multipliers. Each entry maps an action to a table of
    /// (startHour, endHour, multiplier). Missing hours default to 1.0.
    private static let hourMultipliers: [PetAction: [(range: ClosedRange<Int>, factor: Double)]] = [
        .stargaze:  [(20...23, 3.0), (0...4, 3.0)],
        .sleep:     [(1...5, 2.5)],
        .splash:    [(11...15, 1.6)],
        .dash:      [(9...11, 1.4), (16...18, 1.4)],
        .celebrate: [(17...19, 1.3)]
    ]

    public private(set) var lastAction: PetAction?
    public private(set) var nextActionAt: Date?

    private let config: Config
    private var rng: SeededRandom

    public init(seed: UInt64, config: Config = .init(), startAt: Date? = nil) {
        self.config = config
        self.rng = SeededRandom(seed: seed)
        self.nextActionAt = startAt
    }

    public struct Decision: Equatable {
        public let action: PetAction
        public let holdSeconds: Double
    }

    /// Decide the next action given the current time. The caller applies
    /// the decision by moving the pet toward a target and running the
    /// clip; when the hold expires (or a media event pre-empts), it calls
    /// `decideNext` again.
    public func decideNext(at time: WorldTime) -> Decision {
        let weights = weightedTable(hour: time.hour)
        let action = pickWeighted(weights)
        lastAction = action

        let range = config.maxActionSeconds - config.minActionSeconds
        let hold = config.minActionSeconds + rng.nextDouble() * range
        return Decision(action: action, holdSeconds: hold)
    }

    /// Yield an action explicitly (used when progress-follow mode ends and
    /// we need to fall back to free-roam without a stale nextAction). Does
    /// not consume RNG state.
    public func peek(at time: WorldTime) -> PetAction {
        weightedTable(hour: time.hour).map { $0.action }.first ?? .idle
    }

    private func weightedTable(hour: Int) -> [(action: PetAction, weight: Double)] {
        return PetAction.allCases.compactMap { action -> (PetAction, Double)? in
            guard let base = Self.baseWeights[action] else { return nil }
            var w = base
            if let mults = Self.hourMultipliers[action] {
                for m in mults where m.range.contains(hour) {
                    w *= m.factor
                }
            }
            // Avoid consecutive repeats: hard-zero the last action's weight.
            // The remaining actions still cover the full behavior space so
            // this doesn't shrink variety, and the invariant is testable.
            if let last = lastAction, action == last {
                w = 0
            }
            return (action, w)
        }
    }

    private func pickWeighted(_ table: [(action: PetAction, weight: Double)]) -> PetAction {
        let total = table.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return .idle }
        var pick = rng.nextDouble() * total
        for entry in table {
            if pick < entry.weight { return entry.action }
            pick -= entry.weight
        }
        return table.last?.action ?? .idle
    }
}
