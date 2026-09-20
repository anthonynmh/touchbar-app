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

    func testKickSendsTheBallAwayFromTheTappedSide() {
        var (g, now) = servedGame()
        let x = g.ballX
        XCTAssertTrue(g.kick(atX: x - 3, now: now))
        XCTAssertEqual(g.ballVX, KeepAwayGame.kickSpeed, "tap left of centre kicks right")
        XCTAssertTrue(g.kick(atX: x + 3, now: now))
        XCTAssertEqual(g.ballVX, -KeepAwayGame.kickSpeed, "tap right of centre kicks left")
        XCTAssertEqual(g.petBlockedUntil, now.addingTimeInterval(KeepAwayGame.petReaction(round: 1)))
        now = now.addingTimeInterval(0.125)
        XCTAssertNil(g.petTargetX(at: now), "the pet is stunned after a kick")
        XCTAssertEqual(g.petTargetX(at: now.addingTimeInterval(1)), g.ballX)
    }

    func testKickMissesOutsideTheInflatedBallRect() {
        let (g0, now) = servedGame()
        var g = g0
        let hit = g.ballHitRect()
        XCTAssertEqual(hit.width, KeepAwayGame.ballSize.width + 2 * KeepAwayGame.ballTapSlop)
        XCTAssertFalse(g.kick(atX: hit.maxX + 1, now: now))
        XCTAssertFalse(g.kick(atX: hit.minX - 1, now: now))
        XCTAssertTrue(g.kick(atX: hit.maxX - 0.5, now: now))
    }

    func testKickIsIgnoredOutsidePlay() {
        var g = KeepAwayGame(arena: arena, nookX: nookX, now: t0)
        XCTAssertFalse(g.kick(atX: g.ballX, now: t0), "still in the nook")
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
        XCTAssertFalse(g.kick(atX: g.ballX, now: now), "no kicks once caught")
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
