import CoreGraphics
import XCTest
@testable import SnappyNestCore

final class TennisGameTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1004, height: 30)
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func court() -> CGRect {
        LayoutEngine(bounds: bounds, backingScale: 2, page: .court).regions.court
    }

    private func game(seed: UInt64 = 7) -> TennisGame {
        TennisGame(court: court(), groundY: bounds.maxY - 4, seed: seed)
    }

    private var home: CGFloat { game().petHomeX }

    /// Run the clock forward in 1/8 s steps until `stop` says so.
    @discardableResult
    private func run(_ g: inout TennisGame, from start: Date, petX: CGFloat,
                     limit: TimeInterval = 30, until stop: (TennisGame.Event?, TennisGame, Date) -> Bool) -> Date {
        var now = start
        while now.timeIntervalSince(start) < limit {
            now = now.addingTimeInterval(0.125)
            let e = g.tick(now: now, petX: petX)
            if stop(e, g, now) { return now }
        }
        XCTFail("condition never met")
        return now
    }

    func testServeWaitsForASwing() {
        var g = game()
        XCTAssertEqual(g.phase, .serve)
        XCTAssertEqual(g.ballPosition(at: t0).x, g.serveX)
        XCTAssertNil(g.tick(now: t0.addingTimeInterval(5), petX: home))
        XCTAssertEqual(g.phase, .serve)
        XCTAssertEqual(g.petTarget(at: t0), g.petHomeX, "the pet waits at home")
        XCTAssertTrue(g.canSwing(at: t0))
        XCTAssertTrue(g.swing(strength: 0.5, now: t0))
        guard case .flight(let f) = g.phase else { return XCTFail("not in flight") }
        XCTAssertEqual(f.from, g.serveX)
        XCTAssertEqual(f.toward, .pet)
        XCTAssertNil(f.fault)
        XCTAssertEqual(g.rally, 1)
    }

    func testStrengthSetsRangeAndSpeed() {
        var g = game()
        g.swing(strength: 0.6, now: t0)
        guard case .flight(let f) = g.phase else { return XCTFail() }
        XCTAssertEqual(f.to, g.serveX + 0.6 * g.maxRange, accuracy: 1e-9)
        XCTAssertEqual(f.duration, TimeInterval((f.to - f.from) / TennisGame.flightSpeed(strength: 0.6)), accuracy: 1e-9)
        XCTAssertEqual(f.height, TennisGame.flightHeight(range: 0.6 * g.maxRange))
        // Parabola: on the ground at both ends, apex at mid-flight.
        XCTAssertEqual(g.ballPosition(at: f.start).height, 0)
        XCTAssertEqual(g.ballPosition(at: f.start.addingTimeInterval(f.duration / 2)).height, f.height, accuracy: 1e-9)
        XCTAssertEqual(g.ballPosition(at: f.end).height, 0, accuracy: 1e-3)
        XCTAssertEqual(g.ballPosition(at: f.end).x, f.to, accuracy: 1e-3)
        XCTAssertGreaterThan(TennisGame.flightSpeed(strength: 1), TennisGame.flightSpeed(strength: 0))
    }

    func testWeakShotIsANetFault() {
        var g = game()
        // Range just under half the court lands before netX + netMargin.
        let short = Double((g.netX + TennisGame.netMargin - 1 - g.serveX) / g.maxRange)
        g.swing(strength: short, now: t0)
        guard case .flight(let f) = g.phase else { return XCTFail() }
        XCTAssertEqual(f.fault, .net)
        XCTAssertEqual(f.to, g.netX, "the ball stops at the net")
        let now = run(&g, from: t0, petX: home) { e, _, _ in e == .point(.pet, .net) }
        XCTAssertEqual(g.petPoints, 1)
        XCTAssertEqual(g.userPoints, 0)
        XCTAssertFalse(g.canSwing(at: now))
    }

    func testFullPowerFromTheBaselineIsOut() {
        var g = game()
        g.swing(strength: 1, now: t0)
        guard case .flight(let f) = g.phase else { return XCTFail() }
        XCTAssertEqual(f.fault, .out)
        XCTAssertGreaterThan(f.to, g.court.maxX)
        XCTAssertEqual(g.petTarget(at: t0.addingTimeInterval(1)), g.petHomeX, "the pet does not chase a shot going out")
        run(&g, from: t0, petX: home) { e, _, _ in e == .point(.pet, .out) }
        XCTAssertEqual(g.petPoints, 1)
    }

    func testPetInReachReturnsOutOfReachLosesThePoint() {
        // In reach: the pet stands on the landing spot.
        var a = game()
        a.swing(strength: 0.7, now: t0)
        guard case .flight(let fa) = a.phase else { return XCTFail() }
        XCTAssertNil(a.petTarget(at: t0.addingTimeInterval(0.1)), "reaction delay first")
        XCTAssertEqual(a.petTarget(at: t0.addingTimeInterval(TennisGame.petReaction)), fa.to)
        run(&a, from: t0, petX: fa.to + TennisGame.petReach - 1) { e, _, _ in e == .petHit }
        guard case .flight(let ret) = a.phase else { return XCTFail("no return flight") }
        XCTAssertEqual(ret.toward, .user)
        XCTAssertEqual(ret.from, fa.to)
        XCTAssertEqual(a.rally, 2)
        XCTAssertEqual(a.petTarget(at: ret.start), a.petHomeX, "the pet recovers to the middle")

        // Out of reach: the pet never left home.
        var b = game()
        b.swing(strength: 0.7, now: t0)
        run(&b, from: t0, petX: home + 200) { e, _, _ in e == .point(.user, .missed) }
        XCTAssertEqual(b.userPoints, 1)
    }

    func testReturnBouncesOnTheUserSideAndAMissedSwingLosesThePoint() {
        var g = game()
        g.swing(strength: 0.7, now: t0)
        guard case .flight(let f) = g.phase else { return XCTFail() }
        run(&g, from: t0, petX: f.to) { e, _, _ in e == .petHit }
        // Wait out the return without swinging.
        var sawBounce = false
        run(&g, from: t0, petX: home) { e, g, _ in
            if case .bouncing = g.phase { sawBounce = true }
            return e == .point(.pet, .missed)
        }
        XCTAssertTrue(sawBounce)
        XCTAssertEqual(g.petPoints, 1)
    }

    func testVolleyAndBounceCanBeSwungAt() {
        var g = game()
        g.swing(strength: 0.7, now: t0)
        guard case .flight(let f) = g.phase else { return XCTFail() }
        var now = run(&g, from: t0, petX: f.to) { e, _, _ in e == .petHit }
        guard case .flight(let ret) = g.phase, ret.fault == nil else {
            return  // a seeded net/out by the pet: nothing to volley
        }
        // Before the return crosses the net: no swing.
        XCTAssertFalse(g.canSwing(at: now))
        // Once it is on the user's side: a volley is allowed.
        now = run(&g, from: now, petX: home) { _, g, t in g.ballPosition(at: t).x < g.netX }
        XCTAssertTrue(g.canSwing(at: now))
        XCTAssertTrue(g.swing(strength: 0.6, now: now))
        guard case .flight(let volley) = g.phase else { return XCTFail() }
        XCTAssertEqual(volley.toward, .pet)
        XCTAssertLessThan(volley.from, g.netX)
    }

    func testMatchEndsAtTwoPointsAndTheNextSwingStartsANewOne() {
        var g = game()
        var now = t0
        for _ in 0..<2 {
            g.swing(strength: 1, now: now)   // out, twice
            now = run(&g, from: now, petX: home) { e, _, _ in
                if case .point = e ?? .serveReady { return true }
                return false
            }
            now = run(&g, from: now, petX: home) { e, _, _ in e == .serveReady || e == .matchOver(.pet) }
        }
        XCTAssertEqual(g.petPoints, 2)
        XCTAssertTrue(g.isMatchOver)
        XCTAssertEqual(g.ballPosition(at: now).x, g.serveX)
        XCTAssertTrue(g.canSwing(at: now))
        XCTAssertTrue(g.swing(strength: 0.5, now: now))
        XCTAssertEqual(g.userPoints, 0)
        XCTAssertEqual(g.petPoints, 0)
        guard case .flight = g.phase else { return XCTFail("the swing served the new match") }
    }

    func testPetAimErrorGrowsWithTheRallyAndEndsIt() {
        XCTAssertGreaterThan(TennisGame.petAimSigma(rally: 6), TennisGame.petAimSigma(rally: 1))
        // Return everything perfectly: eventually the pet nets or overhits.
        var g = game(seed: 11)
        var now = t0
        g.swing(strength: 0.7, now: now)
        var winner: TennisGame.Side?
        var hits = 1
        while winner == nil && hits < 40 {
            guard case .flight(let f) = g.phase else { return XCTFail("unexpected phase \(g.phase)") }
            // The pet always reaches our shot.
            now = run(&g, from: now, petX: f.to, limit: 10) { e, _, _ in e != nil }
            if case .point(let w, _, _) = g.phase { winner = w; break }
            // Its return: hit it back as soon as it is on our side.
            now = run(&g, from: now, petX: home) { e, g, t in e != nil || g.canSwing(at: t) }
            if case .point(let w, _, _) = g.phase { winner = w; break }
            let x = g.ballPosition(at: now).x
            let target = g.netX + (g.court.maxX - g.netX) / 2
            XCTAssertTrue(g.swing(strength: Double((target - x) / g.maxRange), now: now))
            hits += 1
        }
        XCTAssertEqual(winner, .user, "a long rally ends with a pet error")
        XCTAssertGreaterThan(hits, 1)
    }

    func testDeterministicForAFixedSeed() {
        func trace(seed: UInt64) -> [CGFloat] {
            var g = game(seed: seed)
            var xs: [CGFloat] = []
            var now = t0
            g.swing(strength: 0.7, now: now)
            for _ in 0..<80 {
                now = now.addingTimeInterval(0.125)
                guard case .flight(let f) = g.phase else { _ = g.tick(now: now, petX: home); continue }
                _ = g.tick(now: now, petX: f.to)
                xs.append(g.ballPosition(at: now).x)
            }
            return xs
        }
        XCTAssertEqual(trace(seed: 3), trace(seed: 3))
        XCTAssertNotEqual(trace(seed: 3), trace(seed: 4), "the pet's aim depends on the seed")
    }
}
