import CoreGraphics
import XCTest
@testable import SnappyNestCore

final class PetControllerTennisTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1004, height: 30)
    private func layout() -> LayoutEngine { LayoutEngine(bounds: bounds, backingScale: 2.0) }
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func run(_ c: PetController, from start: Date, seconds: TimeInterval) -> Date {
        var now = start
        for _ in 0..<Int((seconds / 0.125).rounded(.up)) {
            now = now.addingTimeInterval(0.125)
            c.tick(now: now, media: .unknown)
        }
        return now
    }

    /// A controller that has landed on the court and is waiting for a serve.
    private func onCourt() -> (PetController, Date) {
        let c = PetController(seed: 3, layout: layout())
        c.tick(now: t0, media: .unknown)
        c.enter(.tennis, now: t0)
        let now = run(c, from: t0, seconds: 2 * PetController.teleportDuration + 0.25)
        XCTAssertEqual(c.mode, .tennis)
        XCTAssertNotNil(c.tennis)
        return (c, now)
    }

    func testEnteringTheCourtTeleportsToThePetHalfAndStartsAMatch() {
        let c = PetController(seed: 3, layout: layout())
        c.tick(now: t0, media: .unknown)
        XCTAssertFalse(c.swing(strength: 0.5, now: t0), "no swing off the court")
        c.enter(.tennis, now: t0)
        XCTAssertEqual(c.state.action, .teleportOut)
        XCTAssertNil(c.tennis, "the match starts once the pet has landed")
        _ = run(c, from: t0, seconds: 2 * PetController.teleportDuration + 0.25)
        let game = try! XCTUnwrap(c.tennis)
        XCTAssertEqual(c.state.position.x, game.petHomeX, accuracy: 1e-9)
        XCTAssertEqual(c.state.facing, .left)
        XCTAssertEqual(game.phase, .serve)
        XCTAssertEqual(c.state.action, .idle)
    }

    func testPetRunsToTheLandingSpotAtCourtSpeedAndSwings() {
        let (c, served) = onCourt()
        XCTAssertTrue(c.swing(strength: 0.85, now: served))
        guard case .flight(let f) = c.tennis!.phase else { return XCTFail() }
        // After the reaction delay the pet dashes toward the landing spot.
        var now = run(c, from: served, seconds: TennisGame.petReaction + 0.125)
        XCTAssertEqual(c.state.action, .dash)
        let x0 = c.state.position.x
        now = run(c, from: now, seconds: 0.5)
        XCTAssertEqual(abs(c.state.position.x - x0), TennisGame.petSpeed * 0.5, accuracy: 0.6)
        XCTAssertEqual(c.state.facing, f.to > x0 ? .right : .left)
        // It gets there before the ball and swings.
        var sawJump = false
        while now.timeIntervalSince(served) < 6 {
            now = now.addingTimeInterval(0.125)
            c.tick(now: now, media: .unknown)
            if c.state.action == .swing { sawJump = true; break }
        }
        XCTAssertTrue(sawJump, "the pet swung at the ball")
        XCTAssertEqual(c.tennis?.rally, 2)
    }

    func testPointsPlayTheRightClipsAndTheMatchEndsWithATally() {
        let (c, served) = onCourt()
        var results: [TennisGame.Side] = []
        c.onMatchOver = { results.append($0) }
        c.tennisWins = 1
        c.tennisLosses = 4

        // A net fault: the pet celebrates.
        XCTAssertTrue(c.swing(strength: 0.05, now: served))
        var now = served
        while c.tennis?.petPoints == 0 {
            now = now.addingTimeInterval(0.125)
            c.tick(now: now, media: .unknown)
            XCTAssertLessThan(now.timeIntervalSince(served), 10)
        }
        XCTAssertEqual(c.state.action, .celebrate)
        now = run(c, from: now, seconds: TennisGame.pointHold + 0.25)
        XCTAssertEqual(c.tennis?.phase, .serve)
        XCTAssertEqual(c.state.action, .idle)

        // Out: second pet point, match over, tally bumps.
        XCTAssertTrue(c.swing(strength: 1, now: now))
        while c.tennis?.isMatchOver != true {
            now = now.addingTimeInterval(0.125)
            c.tick(now: now, media: .unknown)
            XCTAssertLessThan(now.timeIntervalSince(served), 30)
        }
        XCTAssertEqual(results, [.pet])
        XCTAssertEqual(c.tennisLosses, 5)
        XCTAssertEqual(c.tennisWins, 1)
        XCTAssertEqual(c.state.action, .celebrate)
        now = run(c, from: now, seconds: TennisGame.matchHold + 0.25)
        XCTAssertEqual(c.state.action, .idle)
        // The next swing starts a new match.
        XCTAssertTrue(c.swing(strength: 0.6, now: now))
        XCTAssertEqual(c.tennis?.petPoints, 0)
    }

    func testUserPointMakesThePetSulk() {
        let (c, served) = onCourt()
        // Deep to the baseline while the pet waits mid-court: it cannot get there.
        let game = c.tennis!
        let deep = Double((game.court.maxX - 2 - game.serveX) / game.maxRange)
        XCTAssertTrue(c.swing(strength: deep, now: served))
        var now = served
        while c.tennis?.userPoints == 0 {
            now = now.addingTimeInterval(0.125)
            c.tick(now: now, media: .unknown)
            XCTAssertLessThan(now.timeIntervalSince(served), 10)
        }
        XCTAssertEqual(c.state.action, .surprised)
        _ = now
    }

    func testLeavingTheCourtDropsTheMatch() {
        let (c, served) = onCourt()
        c.swing(strength: 0.7, now: served)
        c.enter(.roam, now: served.addingTimeInterval(0.5))
        XCTAssertNil(c.tennis)
        XCTAssertEqual(c.state.action, .teleportOut)
        let now = run(c, from: served.addingTimeInterval(0.5), seconds: 2)
        XCTAssertEqual(c.mode, .roam)
        XCTAssertFalse(c.swing(strength: 0.5, now: now))
        // Roaming again at the walk speed, not the court speed.
        c.walkTo(x: c.state.position.x + 100, now: now)
        let x0 = c.state.position.x
        c.tick(now: now.addingTimeInterval(1), media: .unknown)
        XCTAssertEqual(c.state.position.x - x0, PetController.walkSpeed, accuracy: 0.01)
    }

    func testTapOnThePetStillReactsOnTheCourt() {
        let (c, served) = onCourt()
        c.tapPet(now: served)
        XCTAssertEqual(c.state.action, .happy)
        _ = run(c, from: served, seconds: PetController.reactionHold + 0.2)
        XCTAssertEqual(c.state.action, .idle)
        XCTAssertNotNil(c.tennis)
    }
}
