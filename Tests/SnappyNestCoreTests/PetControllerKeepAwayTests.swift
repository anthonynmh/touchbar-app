import CoreGraphics
import XCTest
@testable import SnappyNestCore

final class PetControllerKeepAwayTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1004, height: 30)
    private func layout() -> LayoutEngine { LayoutEngine(bounds: bounds, backingScale: 2.0) }
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var nookX: CGFloat { SceneLayout.nookX(inside: bounds) }

    /// A controller on the world page with a game that has just been served.
    private func servedController() -> (PetController, Date) {
        let c = PetController(seed: 3, layout: layout())
        c.tick(now: t0, media: .unknown)
        c.toggleKeepAway(now: t0)
        var now = t0
        while c.game?.isPlaying != true {
            now = now.addingTimeInterval(0.125)
            c.tick(now: now, media: .unknown)
            XCTAssertLessThan(now.timeIntervalSince(t0), 3, "the serve never came")
        }
        return (c, now)
    }

    private func run(_ c: PetController, from start: Date, seconds: TimeInterval, step: TimeInterval = 0.125) -> Date {
        var now = start
        let ticks = Int((seconds / step).rounded(.up))
        for _ in 0..<ticks {
            now = now.addingTimeInterval(step)
            c.tick(now: now, media: .unknown)
        }
        return now
    }

    func testNookTapStartsTheGameFacingTheNookAndEndsItAgain() {
        let c = PetController(seed: 3, layout: layout())
        c.tick(now: t0, media: .unknown)
        XCTAssertFalse(c.isPlayingGame)

        c.toggleKeepAway(now: t0)
        XCTAssertTrue(c.isPlayingGame)
        XCTAssertEqual(c.state.action, .inspect)
        XCTAssertEqual(c.state.facing, nookX > c.state.position.x ? .right : .left)
        XCTAssertEqual(c.game?.ballX, nookX)

        c.toggleKeepAway(now: t0.addingTimeInterval(0.3))
        XCTAssertFalse(c.isPlayingGame, "a second nook tap is the exit")
        XCTAssertEqual(c.state.action, .idle)
        // The scheduler picks the roam back up on the next tick.
        c.tick(now: t0.addingTimeInterval(0.5), media: .unknown)
        XCTAssertNotEqual(c.state.action, .inspect)
    }

    func testGameOnlyStartsOnTheWorldPage() {
        let c = PetController(seed: 3, layout: layout())
        c.tick(now: t0, media: .unknown)
        c.enter(.workshop, now: t0)
        let settled = run(c, from: t0, seconds: 3)
        XCTAssertEqual(c.mode, .workshop)
        c.toggleKeepAway(now: settled)
        XCTAssertFalse(c.isPlayingGame)
    }

    func testPetChasesTheBallAtTheRoundSpeed() {
        let (c, served) = servedController()
        XCTAssertEqual(c.state.action, .dash)
        let ballX = c.game!.ballX
        let start = c.state.position.x
        let now = served.addingTimeInterval(0.5)
        c.tick(now: now, media: .unknown)
        let moved = c.state.position.x - start
        XCTAssertEqual(abs(moved), KeepAwayGame.petSpeed(round: 1) * 0.5, accuracy: 0.01,
                       "round 1 chase speed, not the dash speed")
        XCTAssertEqual(moved > 0, ballX > start)
    }

    func testKickStunsThePetThenItResumesTheChase() {
        let (c, served) = servedController()
        var now = served
        XCTAssertFalse(c.kickBall(atX: 20, now: now), "a dead tap on the freshly served ball")
        XCTAssertEqual(c.state.action, .dash, "no stun for free")
        while c.game?.isKickable != true {
            now = now.addingTimeInterval(0.125)
            c.tick(now: now, media: .unknown)
            XCTAssertLessThan(now.timeIntervalSince(served), 6)
        }
        let ballX = c.game!.ballX
        XCTAssertTrue(c.kickBall(atX: ballX - 100, now: now))
        XCTAssertEqual(c.game?.ballVX, -KeepAwayGame.kickSpeed, "toward the tap")
        XCTAssertEqual(c.state.action, .surprised)
        let stunnedAt = c.state.position.x
        now = now.addingTimeInterval(0.125)
        c.tick(now: now, media: .unknown)
        XCTAssertEqual(c.state.position.x, stunnedAt, "no movement while stunned")
        XCTAssertEqual(c.state.action, .surprised)

        now = now.addingTimeInterval(KeepAwayGame.petReaction(round: 1))
        c.tick(now: now, media: .unknown)
        XCTAssertEqual(c.state.action, .dash)
        XCTAssertNotEqual(c.state.position.x, stunnedAt)
    }

    func testPetAndGroundTapsAreIgnoredDuringTheGameAndWorkAfter() {
        let (c, served) = servedController()
        let before = c.state.action
        c.tapPet(now: served)
        XCTAssertEqual(c.state.action, before, "a pet tap would stun the chaser")
        c.walkTo(x: 900, now: served)
        XCTAssertEqual(c.state.action, before)

        c.toggleKeepAway(now: served)
        c.tapPet(now: served)
        XCTAssertEqual(c.state.action, .happy)
        c.tick(now: served.addingTimeInterval(PetController.reactionHold + 0.1), media: .unknown)
        c.walkTo(x: 900, now: served.addingTimeInterval(3))
        XCTAssertEqual(c.state.action, .walk)
    }

    func testCatchCelebratesReportsTheScoreAndAutoExits() {
        let (c, served) = servedController()
        var lost: Int?
        c.onGameLost = { lost = $0 }
        // Never kick: the pet eventually reaches a resting ball.
        var now = served
        var ticks = 0
        while c.game?.isOver != true {
            now = now.addingTimeInterval(0.125)
            c.tick(now: now, media: .unknown)
            ticks += 1
            XCTAssertLessThan(ticks, 8 * 60, "the pet should catch a still ball well inside a minute")
        }
        XCTAssertEqual(c.state.action, .celebrate)
        XCTAssertEqual(lost, c.game?.roundsSurvived)
        XCTAssertEqual(c.bestRounds, lost)
        let caughtAt = c.state.position.x
        _ = run(c, from: now, seconds: 1)
        XCTAssertEqual(c.state.action, .celebrate)
        XCTAssertEqual(c.state.position.x, caughtAt)
        _ = run(c, from: now, seconds: KeepAwayGame.lostHold + 0.5)
        XCTAssertFalse(c.isPlayingGame, "the loss hold expired: back to roaming")
    }

    func testSurvivingARoundSulksThenServesAFasterRound() {
        let (c, served) = servedController()
        // Keep the ball away by kicking it whenever the pet closes in.
        var now = served
        while c.game?.round == 1, c.game?.isPlaying == true {
            now = now.addingTimeInterval(0.125)
            c.tick(now: now, media: .unknown)
            if let g = c.game, g.isKickable, abs(c.state.position.x - g.ballX) < 80 {
                // Tap on the far side of the ball from the pet.
                let side: CGFloat = c.state.position.x < g.ballX ? 50 : -50
                c.kickBall(atX: g.ballX + side, now: now)
            }
            XCTAssertLessThan(now.timeIntervalSince(served), 12)
        }
        XCTAssertEqual(c.state.action, .surprised, "round lost by the pet")
        XCTAssertEqual(c.game?.roundsSurvived, 1)
        now = run(c, from: now, seconds: KeepAwayGame.roundWonHold + 0.125)
        XCTAssertEqual(c.game?.round, 2)
        XCTAssertEqual(c.state.action, .inspect)
        now = run(c, from: now, seconds: KeepAwayGame.readyDelay + 0.125)
        XCTAssertEqual(c.state.action, .dash)
        XCTAssertEqual(c.game?.petSpeed, KeepAwayGame.petSpeed(round: 2))
    }

    func testBestRoundsOnlyGrows() {
        let c = PetController(seed: 3, layout: layout())
        c.bestRounds = 4
        c.tick(now: t0, media: .unknown)
        c.toggleKeepAway(now: t0)
        var now = t0
        while c.game?.isOver != true {
            now = now.addingTimeInterval(0.125)
            c.tick(now: now, media: .unknown)
            XCTAssertLessThan(now.timeIntervalSince(t0), 60)
        }
        XCTAssertEqual(c.bestRounds, 4)
    }

    func testPageChangeEndsTheGameBeforeThePoof() {
        let (c, served) = servedController()
        c.enter(.playback, now: served)
        XCTAssertFalse(c.isPlayingGame)
        XCTAssertEqual(c.state.action, .teleportOut)
        let now = run(c, from: served, seconds: 2)
        XCTAssertEqual(c.mode, .playback)
        XCTAssertFalse(c.isPlayingGame)
        _ = now
    }

    func testSpeciesChangeEndsTheGame() {
        let (c, served) = servedController()
        c.setSpecies(.mecha, now: served)
        XCTAssertFalse(c.isPlayingGame)
        _ = run(c, from: served, seconds: 2)
        XCTAssertEqual(c.state.species, .mecha)
        XCTAssertEqual(c.mode, .roam)
    }

    func testNookTapExitsFromEveryPhase() {
        // ready
        let a = PetController(seed: 3, layout: layout())
        a.tick(now: t0, media: .unknown)
        a.toggleKeepAway(now: t0)
        a.toggleKeepAway(now: t0.addingTimeInterval(0.2))
        XCTAssertFalse(a.isPlayingGame)

        // playing
        let (b, served) = servedController()
        b.toggleKeepAway(now: served)
        XCTAssertFalse(b.isPlayingGame)
        XCTAssertEqual(b.state.action, .idle)

        // lost (celebrating)
        let (d, s2) = servedController()
        var now = s2
        while d.game?.isOver != true {
            now = now.addingTimeInterval(0.125)
            d.tick(now: now, media: .unknown)
            XCTAssertLessThan(now.timeIntervalSince(s2), 60)
        }
        d.toggleKeepAway(now: now)
        XCTAssertFalse(d.isPlayingGame)
        XCTAssertEqual(d.state.action, .idle)
        // And the scheduler is back in charge: the pet's speed is its own again.
        d.walkTo(x: d.state.position.x + 100, now: now)
        let x0 = d.state.position.x
        d.tick(now: now.addingTimeInterval(1), media: .unknown)
        XCTAssertEqual(d.state.position.x - x0, PetController.walkSpeed, accuracy: 0.01)
    }
}
