import CoreGraphics
import Foundation

/// Keep-away: the world page's activity. A ball rests in a nook on the
/// ground; tapping the nook serves it and the pet dashes for it. The user
/// taps the ball to kick it away from the finger. Surviving a round timer
/// wins the round (the pet gets faster), the pet reaching the ball wins the
/// game.
///
/// Pure state machine in strip coordinates: the controller feeds it `dt`,
/// `now` and the pet's x, and maps the returned `Event` to pet actions. No
/// AppKit, no battery, no wall clock of its own.
public struct KeepAwayGame: Equatable {
    public enum Phase: Equatable {
        /// The ball sits in the nook; the pet waits. Serves at `until`.
        case ready(until: Date)
        case playing
        /// The timer ran out; the pet sulks until `until`, then the next
        /// round is served.
        case roundWon(until: Date)
        /// The pet reached the ball; it celebrates until `until`, then the
        /// game is over.
        case lost(until: Date)
    }

    public enum Event: Equatable {
        /// The ball left the nook; chase it.
        case go
        /// The pet reached the ball.
        case caught
        /// The round timer expired with the ball free.
        case roundWon
        /// The next, faster round is waiting in the nook.
        case nextRound
        /// The loss hold expired; leave the game.
        case finished
    }

    public static let roundDuration: TimeInterval = 10
    public static let readyDelay: TimeInterval = 1.0
    public static let roundWonHold: TimeInterval = 2.0
    public static let lostHold: TimeInterval = 3.0
    /// Impulse from a kick (and from the serve), points per second.
    public static let kickSpeed: CGFloat = 120
    /// Velocity kept per quarter second while rolling.
    public static let ballFriction: Double = 0.85
    /// Velocity kept after bouncing off an arena edge: kicking into a wall
    /// hands the ball back to the pet.
    public static let wallBounce: CGFloat = 0.5
    public static let catchDistance: CGFloat = 6
    public static let ballSize = CGSize(width: 6, height: 6)
    /// The ball is tiny; the hit rect is inflated so a finger can find it.
    public static let ballTapSlop: CGFloat = 8
    /// Edge inset the ball bounces off, so it never leaves the terrain.
    public static let wallInset: CGFloat = 3
    /// Below this speed the ball is considered stopped.
    private static let restSpeed: CGFloat = 1

    /// Ground speed of the chasing pet: round 1 ≈ 28 pt/s, capped at the dash.
    public static func petSpeed(round: Int) -> CGFloat {
        min(PetController.dashSpeed, 22 + 6 * CGFloat(round))
    }

    /// Pause after each kick before the pet re-targets the ball.
    public static func petReaction(round: Int) -> TimeInterval {
        max(0.15, 0.6 - 0.08 * Double(round))
    }

    public private(set) var phase: Phase
    /// 1-based; `roundsSurvived` is the score.
    public private(set) var round: Int = 1
    public private(set) var roundEndsAt: Date
    public private(set) var ballX: CGFloat
    public private(set) var ballVX: CGFloat = 0
    public private(set) var petBlockedUntil: Date?
    public let arena: CGRect
    public let nookX: CGFloat
    public let groundY: CGFloat

    public init(arena: CGRect, nookX: CGFloat, now: Date) {
        self.arena = arena
        self.nookX = nookX
        self.groundY = arena.maxY - 4
        self.ballX = nookX
        self.phase = .ready(until: now.addingTimeInterval(Self.readyDelay))
        self.roundEndsAt = .distantFuture
    }

    public var isPlaying: Bool {
        if case .playing = phase { return true }
        return false
    }

    public var isOver: Bool {
        if case .lost = phase { return true }
        return false
    }

    /// Completed rounds — the score. The round just won counts as soon as
    /// its timer expires.
    public var roundsSurvived: Int {
        if case .roundWon = phase { return round }
        return round - 1
    }

    public var petSpeed: CGFloat { Self.petSpeed(round: round) }

    public func timeRemaining(at now: Date) -> TimeInterval {
        guard isPlaying else { return Self.roundDuration }
        return max(0, roundEndsAt.timeIntervalSince(now))
    }

    /// Where the pet should run: the ball, while playing and not stunned
    /// by a kick.
    public func petTargetX(at now: Date) -> CGFloat? {
        guard isPlaying else { return nil }
        if let until = petBlockedUntil, now < until { return nil }
        return ballX
    }

    public func ballRect() -> CGRect {
        CGRect(x: ballX - Self.ballSize.width / 2, y: groundY - Self.ballSize.height,
               width: Self.ballSize.width, height: Self.ballSize.height)
    }

    public func ballHitRect(slop: CGFloat = KeepAwayGame.ballTapSlop) -> CGRect {
        ballRect().insetBy(dx: -slop, dy: -slop)
    }

    /// Kick the ball away from the tapped side (a tap left of centre sends it
    /// right). Only lands during play and on the inflated ball rect.
    @discardableResult
    public mutating func kick(atX x: CGFloat, now: Date) -> Bool {
        guard isPlaying else { return false }
        let hit = ballHitRect()
        guard x >= hit.minX && x <= hit.maxX else { return false }
        ballVX = x <= ballX ? Self.kickSpeed : -Self.kickSpeed
        petBlockedUntil = now.addingTimeInterval(Self.petReaction(round: round))
        return true
    }

    /// Advance the game. `petX` is the pet's ground anchor before it moves
    /// this tick, so a catch is decided on where the pet actually stood.
    public mutating func tick(dt: TimeInterval, now: Date, petX: CGFloat) -> Event? {
        switch phase {
        case .ready(let until):
            guard now >= until else { return nil }
            phase = .playing
            roundEndsAt = now.addingTimeInterval(Self.roundDuration)
            petBlockedUntil = nil
            serve(awayFrom: petX)
            return .go

        case .playing:
            roll(dt: dt)
            if abs(petX - ballX) <= Self.catchDistance {
                ballVX = 0
                phase = .lost(until: now.addingTimeInterval(Self.lostHold))
                return .caught
            }
            if now >= roundEndsAt {
                ballVX = 0
                phase = .roundWon(until: now.addingTimeInterval(Self.roundWonHold))
                return .roundWon
            }
            return nil

        case .roundWon(let until):
            guard now >= until else { return nil }
            round += 1
            ballX = nookX
            ballVX = 0
            phase = .ready(until: now.addingTimeInterval(Self.readyDelay))
            return .nextRound

        case .lost(let until):
            return now >= until ? .finished : nil
        }
    }

    /// The ball leaves the nook rolling away from the pet; with the pet on
    /// the nook it rolls toward the roomier side.
    private mutating func serve(awayFrom petX: CGFloat) {
        let away: CGFloat
        if abs(petX - nookX) > 0.5 {
            away = petX < nookX ? 1 : -1
        } else {
            away = (arena.maxX - nookX) >= (nookX - arena.minX) ? 1 : -1
        }
        ballVX = Self.kickSpeed * away
    }

    private mutating func roll(dt: TimeInterval) {
        guard ballVX != 0 else { return }
        ballX += ballVX * CGFloat(dt)
        let minX = arena.minX + Self.wallInset
        let maxX = arena.maxX - Self.wallInset
        if ballX < minX {
            ballX = minX
            ballVX = -ballVX * Self.wallBounce
        } else if ballX > maxX {
            ballX = maxX
            ballVX = -ballVX * Self.wallBounce
        }
        ballVX *= CGFloat(pow(Self.ballFriction, dt / 0.25))
        if abs(ballVX) < Self.restSpeed { ballVX = 0 }
    }
}
