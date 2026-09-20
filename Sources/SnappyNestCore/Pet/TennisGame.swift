import CoreGraphics
import Foundation

/// Tennis against the pet on the court page. The user serves and returns
/// with a rightward swipe whose speed is the shot's strength; the pet runs
/// to the landing spot and hits back with an aim error that grows as the
/// rally goes on. A shot that falls short of the net or beyond the far
/// baseline loses the point, as does a return the user never swings at.
/// First to `pointsToWin` takes the match (best of three).
///
/// Pure state machine in strip coordinates: flights and bounces are
/// functions of the injected `now`, so a frame is `ballPosition(at:)`.
/// The pet's x is fed in on every tick; the game never moves the pet, it
/// only says where it should run (`petTarget(at:)`).
public struct TennisGame: Equatable {
    public enum Side: Equatable { case user, pet }
    public enum PointReason: Equatable { case net, out, missed }

    /// A shot in the air from `from` to `to`. `fault` marks a shot that is
    /// already lost (it ends in the net or lands out) so the point is
    /// awarded when it comes down.
    public struct Flight: Equatable {
        public let from: CGFloat
        public let to: CGFloat
        public let height: CGFloat
        public let start: Date
        public let duration: TimeInterval
        public let toward: Side
        public let fault: PointReason?

        public var end: Date { start.addingTimeInterval(duration) }
    }

    /// The ball after a return lands on the user's side: it hops once and
    /// rolls left toward the baseline until the user swings.
    public struct Bounce: Equatable {
        public let start: Date
        public let x0: CGFloat
        public let vx: CGFloat
        public let hop: CGFloat
    }

    public enum Phase: Equatable {
        /// Ball on the user's baseline, waiting for a swipe.
        case serve
        case flight(Flight)
        case bouncing(Bounce)
        /// A point was just decided; the scoreboard shows why until `until`.
        case point(winner: Side, reason: PointReason, until: Date)
        /// The match is decided; the next swing starts a new one.
        case matchOver(winner: Side, until: Date)
    }

    public enum Event: Equatable {
        case userHit
        case petHit
        case point(Side, PointReason)
        case matchOver(Side)
        case serveReady
    }

    public static let pointsToWin = 2
    /// A landing closer than this past the net is a net fault.
    public static let netMargin: CGFloat = 20
    /// Drawn net height above the ground line.
    public static let netHeight: CGFloat = 8
    /// Pan velocity (pt/s) that maps to full strength.
    public static let fullStrengthVelocity: CGFloat = 1400
    /// Shorter swipes are not a swing.
    public static let minSwipeDistance: CGFloat = 16
    public static let serveInset: CGFloat = 24
    public static let bounceSpeedFactor: CGFloat = 0.5
    public static let bounceHopDuration: TimeInterval = 0.5
    /// The ball is lost once it rolls this far past the user's baseline.
    public static let baselineSlack: CGFloat = 6
    public static let petSpeed: CGFloat = 90
    public static let petReaction: TimeInterval = 0.25
    public static let petReach: CGFloat = 12
    public static let pointHold: TimeInterval = 1.4
    public static let matchHold: TimeInterval = 3.0

    /// Horizontal speed of a shot, points per second.
    public static func flightSpeed(strength: Double) -> CGFloat {
        220 + 260 * CGFloat(min(1, max(0, strength)))
    }

    /// Visual apex of a shot of this range.
    public static func flightHeight(range: CGFloat) -> CGFloat {
        min(18, max(4, range / 12))
    }

    /// Standard deviation of the pet's landing error after `rally` hits.
    public static func petAimSigma(rally: Int) -> CGFloat {
        24 + 14 * CGFloat(rally)
    }

    public private(set) var phase: Phase = .serve
    public private(set) var userPoints = 0
    public private(set) var petPoints = 0
    /// Hits in the current point (both sides).
    public private(set) var rally = 0
    public let court: CGRect
    public let netX: CGFloat
    public let groundY: CGFloat
    private var rng: SeededRandom
    /// When the pet may start toward the current shot's landing spot.
    private var petRunsAt: Date?

    public init(court: CGRect, groundY: CGFloat, seed: UInt64) {
        self.court = court
        self.netX = court.midX
        self.groundY = groundY
        self.rng = SeededRandom(seed: seed)
    }

    public static func == (a: TennisGame, b: TennisGame) -> Bool {
        a.phase == b.phase && a.userPoints == b.userPoints && a.petPoints == b.petPoints
            && a.rally == b.rally && a.court == b.court && a.petRunsAt == b.petRunsAt
    }

    /// Strength 1.0 travels the whole court, so full power from the
    /// baseline is just out.
    public var maxRange: CGFloat { court.width }
    public var serveX: CGFloat { court.minX + Self.serveInset }
    /// Where the pet waits between shots.
    public var petHomeX: CGFloat { (netX + court.maxX) / 2 }

    public var isMatchOver: Bool {
        if case .matchOver = phase { return true }
        return false
    }

    // MARK: - Ball

    public func ballPosition(at now: Date) -> (x: CGFloat, height: CGFloat) {
        switch phase {
        case .serve:
            return (serveX, 0)
        case .flight(let f):
            let s = min(1, max(0, now.timeIntervalSince(f.start) / f.duration))
            let x = f.from + (f.to - f.from) * CGFloat(s)
            return (x, 4 * f.height * CGFloat(s * (1 - s)))
        case .bouncing(let b):
            let t = now.timeIntervalSince(b.start)
            let x = b.x0 + b.vx * CGFloat(t)
            let s = min(1, max(0, t / Self.bounceHopDuration))
            return (x, 4 * b.hop * CGFloat(s * (1 - s)))
        case .point(_, let reason, _):
            // The ball rests where the point ended.
            switch reason {
            case .net: return (netX, 0)
            case .out: return (court.maxX + 10, 0)
            case .missed: return (court.minX - Self.baselineSlack, 0)
            }
        case .matchOver:
            return (serveX, 0)
        }
    }

    /// Where the pet should be heading, or nil to stay put.
    public func petTarget(at now: Date) -> CGFloat? {
        switch phase {
        case .flight(let f) where f.toward == .pet && f.fault == nil:
            guard let at = petRunsAt, now >= at else { return nil }
            return f.to
        default:
            return petHomeX
        }
    }

    // MARK: - Swing

    /// The user can hit while serving, while a return is on their side
    /// (a volley) or bouncing, and after a match to start the next one.
    public func canSwing(at now: Date) -> Bool {
        switch phase {
        case .serve, .bouncing, .matchOver:
            return true
        case .flight(let f):
            return f.toward == .user && f.fault == nil && ballPosition(at: now).x < netX
        case .point:
            return false
        }
    }

    /// Hit the ball from where it is. `strength` is 0…1 (from the swipe
    /// speed). Returns false when a swing is not allowed right now.
    @discardableResult
    public mutating func swing(strength: Double, now: Date) -> Bool {
        guard canSwing(at: now) else { return false }
        if case .matchOver = phase {
            userPoints = 0
            petPoints = 0
            rally = 0
            phase = .serve
        }
        let s = min(1, max(0, strength))
        let x = ballPosition(at: now).x
        launch(from: x, range: CGFloat(s) * maxRange, speed: Self.flightSpeed(strength: s), toward: .pet, now: now)
        rally += 1
        petRunsAt = now.addingTimeInterval(Self.petReaction)
        return true
    }

    /// Start a flight from `from` that would land `range` points along.
    /// Landing short of the net or beyond the receiving baseline is a fault
    /// that is scored when the ball comes down.
    private mutating func launch(from: CGFloat, range: CGFloat, speed: CGFloat, toward: Side, now: Date) {
        let direction: CGFloat = toward == .pet ? 1 : -1
        let landing = from + direction * range
        let farBaseline = toward == .pet ? court.maxX : court.minX
        let fault: PointReason?
        let to: CGFloat
        let height: CGFloat
        if direction * (landing - netX) < Self.netMargin {
            fault = .net
            to = netX
            height = 4
        } else if direction * (landing - farBaseline) > 0 {
            fault = .out
            to = farBaseline + direction * 10
            height = Self.flightHeight(range: range)
        } else {
            fault = nil
            to = landing
            height = Self.flightHeight(range: range)
        }
        let duration = max(0.05, TimeInterval(abs(to - from) / speed))
        phase = .flight(Flight(from: from, to: to, height: height, start: now,
                               duration: duration, toward: toward, fault: fault))
    }

    // MARK: - Tick

    /// Advance the rally. `petX` is where the pet stands now; it decides
    /// whether a shot is returned.
    public mutating func tick(now: Date, petX: CGFloat) -> Event? {
        switch phase {
        case .serve, .matchOver:
            return nil

        case .flight(let f):
            guard now >= f.end else { return nil }
            if let fault = f.fault {
                // The hitter loses the point.
                return award(f.toward == .pet ? .pet : .user, reason: fault, now: now)
            }
            switch f.toward {
            case .pet:
                guard abs(petX - f.to) <= Self.petReach else {
                    return award(.user, reason: .missed, now: now)
                }
                petReturn(from: f.to, now: now)
                return .petHit
            case .user:
                let speed = abs(f.to - f.from) / CGFloat(f.duration)
                phase = .bouncing(Bounce(start: now, x0: f.to, vx: -speed * Self.bounceSpeedFactor,
                                         hop: f.height / 3))
                return nil
            }

        case .bouncing:
            guard ballPosition(at: now).x < court.minX - Self.baselineSlack else { return nil }
            return award(.pet, reason: .missed, now: now)

        case .point(let winner, _, let until):
            guard now >= until else { return nil }
            if userPoints >= Self.pointsToWin || petPoints >= Self.pointsToWin {
                phase = .matchOver(winner: winner, until: now.addingTimeInterval(Self.matchHold))
                return .matchOver(winner)
            }
            rally = 0
            petRunsAt = nil
            phase = .serve
            return .serveReady
        }
    }

    private mutating func award(_ winner: Side, reason: PointReason, now: Date) -> Event {
        if winner == .user { userPoints += 1 } else { petPoints += 1 }
        petRunsAt = nil
        phase = .point(winner: winner, reason: reason, until: now.addingTimeInterval(Self.pointHold))
        return .point(winner, reason)
    }

    /// The pet aims somewhere in the user's half; the longer the rally, the
    /// wilder the aim, so it eventually nets or overhits.
    private mutating func petReturn(from: CGFloat, now: Date) {
        let lo = court.minX + 40
        let hi = netX - 40
        let aim = lo + CGFloat(rng.nextDouble()) * (hi - lo) + gaussian() * Self.petAimSigma(rally: rally)
        let range = from - aim
        let strength = Double(min(1, max(0, range / maxRange)))
        launch(from: from, range: range, speed: Self.flightSpeed(strength: strength), toward: .user, now: now)
        rally += 1
    }

    private mutating func gaussian() -> CGFloat {
        let u1 = max(1e-12, rng.nextDouble())
        let u2 = rng.nextDouble()
        return CGFloat((-2 * log(u1)).squareRoot() * cos(2 * .pi * u2))
    }
}
