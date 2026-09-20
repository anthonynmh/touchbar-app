import CoreGraphics
import XCTest
@testable import SnappyNestCore

final class KeepAwayGameTests: XCTestCase {
    private let arena = CGRect(x: 0, y: 0, width: 1004, height: 30)
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var nookX: CGFloat { SceneLayout.nookX(inside: arena) }

    /// A game that has just served, with the pet standing far left.
    private func servedGame() -> (KeepAwayGame, Date) {
        var g = KeepAwayGame(arena: arena, nookX: nookX, now: t0)
        let go = t0.addingTimeInterval(KeepAwayGame.readyDelay)
        XCTAssertEqual(g.tick(dt: 0.125, now: go, petX: 20), .go)
        return (g, go)
    }

    func testStartsReadyInTheNookThenServesAwayFromThePet() {
        var g = KeepAwayGame(arena: arena, nookX: nookX, now: t0)
        XCTAssertEqual(g.ballX, nookX)
        XCTAssertFalse(g.isPlaying)
        XCTAssertNil(g.tick(dt: 0.125, now: t0.addingTimeInterval(0.5), petX: 20))
        XCTAssertEqual(g.tick(dt: 0.125, now: t0.addingTimeInterval(1.0), petX: 20), .go)
        XCTAssertTrue(g.isPlaying)
        XCTAssertEqual(g.ballVX, KeepAwayGame.kickSpeed, "pet on the left: the ball rolls right")

        var h = KeepAwayGame(arena: arena, nookX: nookX, now: t0)
        _ = h.tick(dt: 0.125, now: t0.addingTimeInterval(1.0), petX: 900)
        XCTAssertEqual(h.ballVX, -KeepAwayGame.kickSpeed, "pet on the right: the ball rolls left")

        var onNook = KeepAwayGame(arena: arena, nookX: nookX, now: t0)
        _ = onNook.tick(dt: 0.125, now: t0.addingTimeInterval(1.0), petX: nookX)
        XCTAssertEqual(onNook.ballVX, KeepAwayGame.kickSpeed, "pet on the nook: toward the roomier side")
    }

    /// Tick a served game until the ball is slow enough to kick again.
    private func settle(_ g: inout KeepAwayGame, from start: Date) -> (Date, Int) {
        var now = start
        var ticks = 0
        while !g.isKickable {
            now = now.addingTimeInterval(0.125)
            _ = g.tick(dt: 0.125, now: now, petX: 20)
            ticks += 1
            XCTAssertLessThan(ticks, 100, "the ball never slowed down")
        }
        return (now, ticks)
    }

    func testKickRollsTheBallTowardTheTappedSide() {
        var (g, served) = servedGame()
        var (now, _) = settle(&g, from: served)
        XCTAssertTrue(g.kick(atX: 20, petX: 20, now: now), "a tap far left of the ball")
        XCTAssertEqual(g.ballVX, -KeepAwayGame.kickSpeed, "rolls left")
        XCTAssertEqual(g.petBlockedUntil, now.addingTimeInterval(KeepAwayGame.petReaction(round: 1)))
        (now, _) = settle(&g, from: now)
        XCTAssertTrue(g.kick(atX: 900, petX: 20, now: now), "a tap far right of the ball")
        XCTAssertEqual(g.ballVX, KeepAwayGame.kickSpeed, "rolls right")
        XCTAssertNil(g.petTargetX(at: now.addingTimeInterval(0.125)), "the pet is stunned after a kick")
        XCTAssertEqual(g.petTargetX(at: now.addingTimeInterval(1)), g.ballX)
    }

    func testTapOnTheBallRollsItAwayFromThePet() {
        var (g, served) = servedGame()
        let (now, _) = settle(&g, from: served)
        var left = g
        XCTAssertTrue(left.kick(atX: left.ballX, petX: left.ballX - 100, now: now))
        XCTAssertEqual(left.ballVX, KeepAwayGame.kickSpeed, "pet on the left: away to the right")
        var right = g
        XCTAssertTrue(right.kick(atX: right.ballX + 0.5, petX: right.ballX + 100, now: now))
        XCTAssertEqual(right.ballVX, -KeepAwayGame.kickSpeed, "pet on the right: away to the left")
    }

    func testRollingBallCannotBeKickedUntilItSlows() {
        var (g, served) = servedGame()
        XCTAssertFalse(g.isKickable, "just served")
        XCTAssertFalse(g.kick(atX: 900, petX: 20, now: served), "a dead tap")
        XCTAssertEqual(g.ballVX, KeepAwayGame.kickSpeed, "the serve was not redirected")
        XCTAssertNil(g.petBlockedUntil, "and the pet was not stunned for free")
        let (_, ticks) = settle(&g, from: served)
        XCTAssertEqual(ticks, 26, "kickable about 3.2 s after a full-speed kick")
        XCTAssertLessThan(abs(g.ballVX), KeepAwayGame.kickableSpeed)
        XCTAssertGreaterThan(abs(g.ballVX), 0, "still rolling, just slowly")
    }

    func testKickIsIgnoredOutsidePlay() {
        var g = KeepAwayGame(arena: arena, nookX: nookX, now: t0)
        XCTAssertFalse(g.kick(atX: g.ballX, petX: 20, now: t0), "still in the nook")
        XCTAssertEqual(g.ballVX, 0)
    }

    func testFrictionBringsTheBallToRest() {
        var (g, now) = servedGame()
        var last = abs(g.ballVX)
        for _ in 0..<64 {
            now = now.addingTimeInterval(0.125)
            _ = g.tick(dt: 0.125, now: now, petX: 20)
            XCTAssertLessThanOrEqual(abs(g.ballVX), last)
            last = abs(g.ballVX)
        }
        XCTAssertEqual(g.ballVX, 0, "an 8 s roll comes to rest")
        XCTAssertGreaterThan(g.ballX, nookX)
    }

    func testWallBounceHalvesSpeedAndKeepsTheBallInside() {
        // A nook right beside the left wall: the serve away from a pet on
        // the right hits the wall within the first tick.
        var g = KeepAwayGame(arena: arena, nookX: arena.minX + 10, now: t0)
        let go = t0.addingTimeInterval(KeepAwayGame.readyDelay)
        XCTAssertEqual(g.tick(dt: 0.125, now: go, petX: 900), .go)
        XCTAssertEqual(g.ballVX, -KeepAwayGame.kickSpeed)
        _ = g.tick(dt: 0.125, now: go.addingTimeInterval(0.125), petX: 900)
        XCTAssertEqual(g.ballX, arena.minX + KeepAwayGame.wallInset, "clamped to the wall inset")
        XCTAssertGreaterThan(g.ballVX, 0, "bounced back to the right")
        XCTAssertLessThanOrEqual(g.ballVX, KeepAwayGame.kickSpeed * KeepAwayGame.wallBounce)
    }

    func testPetReachingTheBallLosesTheGame() {
        var (g, now) = servedGame()
        now = now.addingTimeInterval(0.125)
        XCTAssertEqual(g.tick(dt: 0.125, now: now, petX: g.ballX + KeepAwayGame.catchDistance + 20), nil)
        let x = g.ballX + g.ballVX * 0.125  // where the ball will be after this tick
        XCTAssertEqual(g.tick(dt: 0.125, now: now.addingTimeInterval(0.125), petX: x + KeepAwayGame.catchDistance - 0.5), .caught)
        XCTAssertTrue(g.isOver)
        XCTAssertEqual(g.ballVX, 0)
        XCTAssertEqual(g.roundsSurvived, 0)
        XCTAssertFalse(g.kick(atX: 900, petX: 0, now: now), "no kicks once caught")
        XCTAssertNil(g.tick(dt: 0.125, now: now.addingTimeInterval(1), petX: 0))
        XCTAssertEqual(g.tick(dt: 0.125, now: now.addingTimeInterval(KeepAwayGame.lostHold + 0.5), petX: 0), .finished)
    }

    func testSurvivingTheTimerWinsTheRoundAndRampsTheNextOne() {
        var (g, now) = servedGame()
        let end = g.roundEndsAt
        XCTAssertEqual(end, now.addingTimeInterval(KeepAwayGame.roundDuration))
        XCTAssertEqual(g.timeRemaining(at: now.addingTimeInterval(4)), 6, accuracy: 1e-9)
        XCTAssertEqual(g.tick(dt: 0.125, now: end, petX: 20), .roundWon)
        XCTAssertEqual(g.ballVX, 0)
        XCTAssertEqual(g.roundsSurvived, 1, "the won round counts at once")
        XCTAssertNil(g.tick(dt: 0.125, now: end.addingTimeInterval(1), petX: 20))
        let next = end.addingTimeInterval(KeepAwayGame.roundWonHold)
        XCTAssertEqual(g.tick(dt: 0.125, now: next, petX: 20), .nextRound)
        XCTAssertEqual(g.round, 2)
        XCTAssertEqual(g.roundsSurvived, 1)
        XCTAssertEqual(g.ballX, nookX, "the ball is back in the nook")
        XCTAssertEqual(g.petSpeed, KeepAwayGame.petSpeed(round: 2))
        XCTAssertGreaterThan(KeepAwayGame.petSpeed(round: 2), KeepAwayGame.petSpeed(round: 1))
        XCTAssertLessThan(KeepAwayGame.petReaction(round: 2), KeepAwayGame.petReaction(round: 1))
        XCTAssertEqual(g.tick(dt: 0.125, now: next.addingTimeInterval(KeepAwayGame.readyDelay), petX: 20), .go)
    }

    func testDifficultyRampIsBounded() {
        XCTAssertEqual(KeepAwayGame.petSpeed(round: 1), 28)
        XCTAssertEqual(KeepAwayGame.petSpeed(round: 50), PetController.dashSpeed)
        XCTAssertEqual(KeepAwayGame.petReaction(round: 1), 0.52, accuracy: 1e-9)
        XCTAssertEqual(KeepAwayGame.petReaction(round: 50), 0.15, accuracy: 1e-9)
    }

    func testCatchIsCheckedBeforeTheTimer() {
        var (g, _) = servedGame()
        let now = g.roundEndsAt
        let x = g.ballX + g.ballVX * 0.125
        XCTAssertEqual(g.tick(dt: 0.125, now: now, petX: x), .caught,
                       "the pet standing on the ball as the timer expires still wins")
    }
}
