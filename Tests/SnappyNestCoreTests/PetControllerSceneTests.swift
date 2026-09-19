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

    func testEnteringTheWorkshopTeleportsInSuitsUpAndTinkers() {
        let c = PetController(seed: 7, layout: layout())
        c.tick(now: t0, media: .unknown)
        let startX = c.state.position.x
        c.enter(.workshop, now: t0)
        XCTAssertEqual(c.mode, .roam, "the mode flips once the pet has poofed out")
        XCTAssertEqual(c.state.action, .teleportOut)
        XCTAssertEqual(c.state.position.x, startX)

        // Poof out: frozen in place until the clip ends.
        c.tick(now: t0.addingTimeInterval(0.25), media: .unknown)
        XCTAssertEqual(c.state.action, .teleportOut)
        XCTAssertEqual(c.state.position.x, startX)

        // Poof in at the workshop spot.
        c.tick(now: t0.addingTimeInterval(PetController.teleportDuration), media: .unknown)
        XCTAssertEqual(c.mode, .workshop)
        XCTAssertEqual(c.state.action, .teleportIn)
        XCTAssertEqual(c.state.position.x, c.workshopX, accuracy: 1e-6)
        XCTAssertEqual(c.state.facing, .right)

        // Then the hat drops and it tinkers.
        c.tick(now: t0.addingTimeInterval(2 * PetController.teleportDuration), media: .unknown)
        XCTAssertEqual(c.state.action, .suitUp)
        var sawSuitUp = false
        let end = run(c, from: t0.addingTimeInterval(2 * PetController.teleportDuration), seconds: 5) { _ in
            if c.state.action == .suitUp { sawSuitUp = true }
        }
        XCTAssertTrue(sawSuitUp)
        XCTAssertEqual(c.state.action, .tinker)
        XCTAssertEqual(c.state.position.x, c.workshopX, accuracy: 1e-6)
        XCTAssertLessThan(c.workshopX + 12, layout().with(page: .controls).regions.brightness.minX,
                          "the pet does not overlap the first control")

        // It keeps tinkering: the scheduler never takes over.
        _ = run(c, from: end, seconds: 120) { _ in
            XCTAssertEqual(c.state.action, .tinker)
        }
    }

    func testEnteringPlaybackTeleportsOntoThePlayhead() {
        let c = PetController(seed: 7, layout: layout())
        let media = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 30, duration: 120, elapsedAt: t0,
                                  rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        c.tick(now: t0, media: media)
        c.enter(.playback, now: t0)
        XCTAssertEqual(c.state.action, .teleportOut)
        let landed = t0.addingTimeInterval(PetController.teleportDuration)
        c.tick(now: landed, media: media)
        XCTAssertEqual(c.state.action, .teleportIn)
        XCTAssertEqual(c.state.position.x,
                       layout().trailX(fraction: 30.5 / 120, spriteHalfWidth: 12), accuracy: 1e-6)
        c.tick(now: landed.addingTimeInterval(PetController.teleportDuration), media: media)
        XCTAssertEqual(c.state.action, .progressFollow)
    }

    func testEnteringPlaybackWithNothingPlayingLandsAtTheTrailStart() {
        let c = PetController(seed: 7, layout: layout())
        c.tick(now: t0, media: .unknown)
        c.enter(.playback, now: t0)
        _ = run(c, from: t0, seconds: 2 * PetController.teleportDuration)
        XCTAssertEqual(c.mode, .playback)
        XCTAssertEqual(c.state.action, .inspect)
        XCTAssertEqual(c.state.position.x, layout().trailX(fraction: 0, spriteHalfWidth: 12), accuracy: 1e-6)
    }

    func testTapsAndScrubsAreIgnoredWhileTeleporting() {
        let c = PetController(seed: 7, layout: layout())
        c.tick(now: t0, media: .unknown)
        c.enter(.playback, now: t0)
        c.tapPet(now: t0.addingTimeInterval(0.1))
        XCTAssertEqual(c.state.action, .teleportOut)
        c.walkTo(x: 300, now: t0.addingTimeInterval(0.1))
        XCTAssertEqual(c.state.action, .teleportOut)
        c.beginScrub(now: t0.addingTimeInterval(0.1))
        c.scrub(x: 300, now: t0.addingTimeInterval(0.1))
        XCTAssertNil(c.endScrub(now: t0.addingTimeInterval(0.1)))
        XCTAssertEqual(c.state.action, .teleportOut)
    }

    func testSwipingBackMidTeleportLandsOnTheLatestPage() {
        let c = PetController(seed: 7, layout: layout())
        c.tick(now: t0, media: .unknown)
        c.enter(.workshop, now: t0)
        c.enter(.playback, now: t0.addingTimeInterval(0.2))
        _ = run(c, from: t0, seconds: 2 * PetController.teleportDuration + 0.25)
        XCTAssertEqual(c.mode, .playback)
        XCTAssertFalse(c.state.action.isTeleporting)
        XCTAssertEqual(c.state.position.x, layout().trailX(fraction: 0, spriteHalfWidth: 12), accuracy: 1e-6)
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

    func testLeavingTheWorkshopTakesTheHatOffThenTeleports() {
        let c = PetController(seed: 7, layout: layout())
        c.enter(.workshop, now: t0)
        let end = run(c, from: t0, seconds: 30)
        c.enter(.roam, now: end)
        XCTAssertEqual(c.state.action, .suitDown)
        XCTAssertEqual(c.mode, .workshop, "mode switches once the pet has poofed out")
        c.tick(now: end.addingTimeInterval(0.25), media: .unknown)
        XCTAssertEqual(c.state.action, .suitDown)
        c.tick(now: end.addingTimeInterval(PetController.suitDuration), media: .unknown)
        XCTAssertEqual(c.state.action, .teleportOut)
        XCTAssertEqual(c.state.position.x, c.workshopX, accuracy: 1e-6)
        c.tick(now: end.addingTimeInterval(PetController.suitDuration + PetController.teleportDuration), media: .unknown)
        XCTAssertEqual(c.state.action, .teleportIn)
        XCTAssertEqual(c.mode, .roam)
        let middle = layout().regions.middle
        XCTAssertGreaterThanOrEqual(c.state.position.x, middle.minX + 12 - 1e-6)
        XCTAssertLessThanOrEqual(c.state.position.x, middle.maxX - 12 + 1e-6)
        _ = run(c, from: end, seconds: PetController.suitDuration + 2 * PetController.teleportDuration + 0.5)
        XCTAssertFalse(c.state.action.wearsHardHat)
        XCTAssertFalse(c.state.action.isTeleporting)
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
        let settled = run(c, from: end, seconds: 2 * PetController.teleportDuration + 0.25, media: media)
        XCTAssertEqual(c.mode, .roam)
        let middle = layout().regions.middle
        var positions = Set<CGFloat>()
        _ = run(c, from: settled, seconds: 600, media: media) { _ in
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

    func testHardHatAndTeleportActionsAreNeverScheduled() {
        let s = PetActionScheduler(seed: 5)
        for hour in 0..<24 {
            for _ in 0..<50 {
                let action = s.decideNext(at: WorldTime(hour: hour, minute: 0, second: 0)).action
                XCTAssertFalse(action.wearsHardHat)
                XCTAssertFalse(action.isTeleporting)
            }
        }
    }
}
