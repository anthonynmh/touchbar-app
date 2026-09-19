import CoreGraphics
import XCTest
@testable import SnappyNestCore

final class PetControllerInteractionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1004, height: 30)
    private func layout() -> LayoutEngine { LayoutEngine(bounds: bounds, backingScale: 2.0) }
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testTapPlaysHappyThenResumesPreviousAction() {
        let c = PetController(seed: 3, layout: layout())
        c.tick(now: t0, media: .unknown)
        let before = c.state.action

        c.tapPet(now: t0)
        XCTAssertEqual(c.state.action, .happy)
        c.tick(now: t0.addingTimeInterval(1), media: .unknown)
        XCTAssertEqual(c.state.action, .happy, "reaction holds for \(PetController.reactionHold)s")

        c.tick(now: t0.addingTimeInterval(PetController.reactionHold + 0.1), media: .unknown)
        XCTAssertEqual(c.state.action, before)
    }

    func testSecondTapEscalatesToSurprised() {
        let c = PetController(seed: 3, layout: layout())
        c.tick(now: t0, media: .unknown)
        c.tapPet(now: t0)
        c.tapPet(now: t0.addingTimeInterval(0.5))
        XCTAssertEqual(c.state.action, .surprised)
        // A tap long after the chain window starts over at happy.
        c.tick(now: t0.addingTimeInterval(10), media: .unknown)
        c.tapPet(now: t0.addingTimeInterval(10))
        XCTAssertEqual(c.state.action, .happy)
    }

    func testTapDuringProgressFollowDoesNotDisturbPosition() {
        let c = PetController(seed: 3, layout: layout())
        let media = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 30, duration: 120, elapsedAt: t0, rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        c.tick(now: t0, media: media)
        c.enter(.playback, now: t0)
        var now = t0
        for _ in 0..<80 { now = now.addingTimeInterval(0.25); c.tick(now: now, media: media) }
        XCTAssertEqual(c.state.action, .progressFollow)
        c.tapPet(now: now)
        XCTAssertEqual(c.state.action, .happy)
        now = now.addingTimeInterval(3)
        c.tick(now: now, media: media)
        XCTAssertEqual(c.state.action, .progressFollow)
        let expected = layout().trailX(fraction: 53.0 / 120.0, spriteHalfWidth: 12)
        XCTAssertEqual(c.state.position.x, expected, accuracy: 1e-6)
    }

    func testWalkToMovesTowardTargetAndInspectsOnArrival() {
        let c = PetController(seed: 3, layout: layout())
        c.tick(now: t0, media: .unknown)
        let startX = c.state.position.x
        let targetX = startX + 30
        c.walkTo(x: targetX, now: t0)
        XCTAssertEqual(c.state.action, .walk)
        XCTAssertEqual(c.state.facing, .right)

        c.tick(now: t0.addingTimeInterval(0.25), media: .unknown)
        XCTAssertGreaterThan(c.state.position.x, startX)
        XCTAssertLessThan(c.state.position.x, targetX)

        // 30 pt at walkSpeed takes ~2.1 s; the inspect hold lasts 3 s after that.
        var now = t0
        for _ in 0..<12 {
            now = now.addingTimeInterval(0.25)
            c.tick(now: now, media: .unknown)
        }
        XCTAssertEqual(c.state.position.x, targetX, accuracy: 1e-6)
        XCTAssertEqual(c.state.action, .inspect)
    }

    func testWalkToClampsInsideMiddleAndAlwaysWalksOnOneTap() {
        let c = PetController(seed: 3, layout: layout())
        c.tick(now: t0, media: .unknown)
        let middle = layout().regions.middle
        c.walkTo(x: middle.maxX + 500, now: t0)
        XCTAssertEqual(c.state.action, .walk, "distance alone never sprints")
        // ~490 pt at walkSpeed is ~35 s; check inside the 3 s inspect hold after that.
        let travel = TimeInterval((middle.maxX - 12 - c.state.position.x) / PetController.walkSpeed)
        var now = t0
        while now < t0.addingTimeInterval(travel + 1) {
            now = now.addingTimeInterval(0.25)
            c.tick(now: now, media: .unknown)
        }
        XCTAssertEqual(c.state.position.x, middle.maxX - 12, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(c.state.hitRect(spriteSize: CGSize(width: 24, height: 24)).maxX, middle.maxX + 1e-6)
    }

    func testQuickSecondGroundTapUpgradesTheWalkToASprint() {
        let c = PetController(seed: 3, layout: layout())
        c.tick(now: t0, media: .unknown)
        let target = c.state.position.x + 200
        c.walkTo(x: target, now: t0)
        XCTAssertEqual(c.state.action, .walk)
        c.walkTo(x: target + 10, now: t0.addingTimeInterval(0.3))
        XCTAssertEqual(c.state.action, .dash)
        var now = t0.addingTimeInterval(0.3)
        for _ in 0..<24 { // 6 s: a 210 pt dash takes < 5 s
            now = now.addingTimeInterval(0.25)
            c.tick(now: now, media: .unknown)
        }
        XCTAssertEqual(c.state.position.x, target + 10, accuracy: 1e-6)
        XCTAssertEqual(c.state.action, .inspect)
    }

    func testSlowOrFarSecondTapStaysAWalk() {
        let c = PetController(seed: 3, layout: layout())
        c.tick(now: t0, media: .unknown)
        let target = c.state.position.x + 200
        c.walkTo(x: target, now: t0)
        c.walkTo(x: target, now: t0.addingTimeInterval(PetController.sprintTapWindow + 0.1))
        XCTAssertEqual(c.state.action, .walk, "too slow")
        c.walkTo(x: target - 150, now: t0.addingTimeInterval(PetController.sprintTapWindow + 0.2))
        XCTAssertEqual(c.state.action, .walk, "a different spot restarts the walk")
    }

    func testFreeRoamWalksActuallyMoveAndStayInsideMiddle() {
        let c = PetController(seed: 99, layout: layout())
        let middle = layout().regions.middle
        var positions = Set<CGFloat>()
        var now = t0
        for _ in 0..<(4 * 60 * 30) { // 30 minutes at 4 Hz
            now = now.addingTimeInterval(0.25)
            c.tick(now: now, media: .unknown)
            positions.insert(c.state.position.x)
            XCTAssertGreaterThanOrEqual(c.state.position.x, middle.minX + 12 - 1e-6)
            XCTAssertLessThanOrEqual(c.state.position.x, middle.maxX - 12 + 1e-6)
        }
        XCTAssertGreaterThan(positions.count, 10, "pet should roam, not stand still")
    }

    func testHitRectAnchorsAtFeet() {
        let s = PetState(action: .idle, facing: .right, position: CGPoint(x: 100, y: 26), frameIndex: 0)
        let r = s.hitRect(spriteSize: CGSize(width: 24, height: 24))
        XCTAssertEqual(r, CGRect(x: 88, y: 2, width: 24, height: 24))
    }

    func testReactionsAreNeverScheduled() {
        let s = PetActionScheduler(seed: 5)
        for hour in 0..<24 {
            for _ in 0..<50 {
                let d = s.decideNext(at: WorldTime(hour: hour, minute: 0, second: 0))
                XCTAssertFalse(d.action.isReaction)
            }
        }
    }
}
