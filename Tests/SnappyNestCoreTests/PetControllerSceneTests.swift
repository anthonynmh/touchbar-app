import CoreGraphics
import XCTest
@testable import SnappyNestCore

/// The pet follows the camera between pages and changes behaviour per page.
final class PetControllerSceneTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1004, height: 30)
    private func layout() -> LayoutEngine { LayoutEngine(bounds: bounds, backingScale: 2.0) }
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func run(_ c: PetController, from start: Date, seconds: TimeInterval,
                     media: MediaSnapshot = .unknown, each: ((Date) -> Void)? = nil) -> Date {
        var now = start
        let ticks = Int(seconds / 0.25)
        for _ in 0..<ticks {
            now = now.addingTimeInterval(0.25)
            c.tick(now: now, media: media)
            each?(now)
        }
        return now
    }

    func testEnteringTheWorkshopDashesInSuitsUpAndTinkers() {
        let c = PetController(seed: 7, layout: layout())
        c.tick(now: t0, media: .unknown)
        c.enter(.workshop, now: t0)
        XCTAssertEqual(c.mode, .workshop)
        XCTAssertEqual(c.state.action, .dash)

        var sawSuitUp = false
        let end = run(c, from: t0, seconds: 30) { _ in
            if c.state.action == .suitUp { sawSuitUp = true }
        }
        XCTAssertTrue(sawSuitUp)
        XCTAssertEqual(c.state.action, .tinker)
        XCTAssertEqual(c.state.position.x, c.workshopX, accuracy: 1e-6)
        XCTAssertEqual(c.state.facing, .right)
        XCTAssertLessThan(c.workshopX + 12, layout().with(page: .controls).regions.brightness.minX,
                          "the pet does not overlap the first control")

        // It keeps tinkering: the scheduler never takes over.
        _ = run(c, from: end, seconds: 120) { _ in
            XCTAssertEqual(c.state.action, .tinker)
        }
    }

    func testTapInTheWorkshopReactsThenGoesBackToTinkering() {
        let c = PetController(seed: 7, layout: layout())
        c.enter(.workshop, now: t0)
        let end = run(c, from: t0, seconds: 30)
        XCTAssertEqual(c.state.action, .tinker)
        c.tapPet(now: end)
        XCTAssertEqual(c.state.action, .happy)
        _ = run(c, from: end, seconds: PetController.reactionHold + 0.5)
        XCTAssertEqual(c.state.action, .tinker)
    }

    func testLeavingTheWorkshopTakesTheHatOffFirst() {
        let c = PetController(seed: 7, layout: layout())
        c.enter(.workshop, now: t0)
        let end = run(c, from: t0, seconds: 30)
        c.enter(.roam, now: end)
        XCTAssertEqual(c.state.action, .suitDown)
        XCTAssertEqual(c.mode, .workshop, "mode switches once the hat is off")
        c.tick(now: end.addingTimeInterval(0.25), media: .unknown)
        XCTAssertEqual(c.state.action, .suitDown)
        _ = run(c, from: end, seconds: PetController.suitDuration + 0.5)
        XCTAssertEqual(c.mode, .roam)
        XCTAssertFalse(c.state.action.wearsHardHat)
    }

    func testRoamResumesFreeRoamAfterPlayback() {
        let c = PetController(seed: 7, layout: layout())
        let media = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 30, duration: 120, elapsedAt: t0,
                                  rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        c.tick(now: t0, media: media)
        c.enter(.playback, now: t0)
        let end = run(c, from: t0, seconds: 30, media: media)
        XCTAssertEqual(c.state.action, .progressFollow)
        c.enter(.roam, now: end)
        XCTAssertEqual(c.mode, .roam)
        let middle = layout().regions.middle
        var positions = Set<CGFloat>()
        _ = run(c, from: end, seconds: 600, media: media) { _ in
            XCTAssertNotEqual(c.state.action, .progressFollow)
            positions.insert(c.state.position.x)
            XCTAssertGreaterThanOrEqual(c.state.position.x, middle.minX + 12 - 1e-6)
            XCTAssertLessThanOrEqual(c.state.position.x, middle.maxX - 12 + 1e-6)
        }
        XCTAssertGreaterThan(positions.count, 10)
    }

    func testEnteringTheSameModeTwiceIsANoOp() {
        let c = PetController(seed: 7, layout: layout())
        c.enter(.workshop, now: t0)
        let end = run(c, from: t0, seconds: 30)
        XCTAssertEqual(c.state.action, .tinker)
        c.enter(.workshop, now: end)
        XCTAssertEqual(c.state.action, .tinker)
    }

    func testHardHatActionsAreNeverScheduled() {
        let s = PetActionScheduler(seed: 5)
        for hour in 0..<24 {
            for _ in 0..<50 {
                XCTAssertFalse(s.decideNext(at: WorldTime(hour: hour, minute: 0, second: 0)).action.wearsHardHat)
            }
        }
    }
}
