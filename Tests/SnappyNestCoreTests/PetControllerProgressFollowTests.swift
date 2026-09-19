import CoreGraphics
import XCTest
@testable import SnappyNestCore

/// Progress-follow happens only on the playback page: the pet is the playhead
/// on the trail. On the world page media is ignored entirely.
final class PetControllerProgressFollowTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 685, height: 30)

    private func layout() -> LayoutEngine {
        LayoutEngine(bounds: bounds, backingScale: 2.0)
    }

    private func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

    private func playing(elapsed: Double, duration: Double, at date: Date) -> MediaSnapshot {
        MediaSnapshot(identity: "spotify", state: .playing, elapsed: elapsed, duration: duration, elapsedAt: date,
                      rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
    }

    /// A controller on the playback page that has already dashed to the playhead.
    private func settledOnTrail(media: MediaSnapshot) -> PetController {
        let controller = PetController(seed: 1, layout: layout())
        controller.tick(now: now(), media: media)
        controller.enter(.playback, now: now())
        var t = now()
        for _ in 0..<80 { // 20 s at 4 Hz: plenty for a dash across the strip
            t = t.addingTimeInterval(0.25)
            controller.tick(now: t, media: media)
        }
        return controller
    }

    func testWorldPageIgnoresPlayingMedia() {
        let controller = PetController(seed: 1, layout: layout())
        let media = playing(elapsed: 30, duration: 120, at: now())
        var t = now()
        for _ in 0..<40 {
            t = t.addingTimeInterval(0.25)
            controller.tick(now: t, media: media)
            XCTAssertNotEqual(controller.state.action, .progressFollow)
        }
    }

    func testFollowsProgressOnThePlaybackPage() {
        let media = playing(elapsed: 30, duration: 120, at: now())
        let controller = settledOnTrail(media: media)
        XCTAssertEqual(controller.mode, .playback)
        XCTAssertEqual(controller.state.action, .progressFollow)

        let t = now().addingTimeInterval(20)
        let expectedX = layout().trailX(fraction: 50.0 / 120.0, spriteHalfWidth: 12)
        XCTAssertEqual(controller.state.position.x, expectedX, accuracy: 1e-6)
        XCTAssertEqual(controller.state.position.y, bounds.maxY - 4, accuracy: 1e-6)
        _ = t
    }

    func testEnteringPlaybackHoldsStillDuringThePoofThenLandsOnThePlayhead() {
        let controller = PetController(seed: 1, layout: layout())
        let media = playing(elapsed: 100, duration: 120, at: now())
        controller.tick(now: now(), media: media)
        let startX = controller.state.position.x
        controller.enter(.playback, now: now())
        XCTAssertEqual(controller.state.action, .teleportOut)
        controller.tick(now: now().addingTimeInterval(0.25), media: media)
        XCTAssertEqual(controller.state.position.x, startX, "the pet does not move while poofing out")

        let landed = now().addingTimeInterval(PetController.teleportDuration)
        controller.tick(now: landed, media: media)
        XCTAssertEqual(controller.state.action, .teleportIn)
        let target = layout().trailX(fraction: (100 + PetController.teleportDuration) / 120.0, spriteHalfWidth: 12)
        XCTAssertEqual(controller.state.position.x, target, accuracy: 1e-6, "lands on the live playhead")
    }

    func testRestsOnTrailWhenNothingIsPlaying() {
        let controller = settledOnTrail(media: MediaSnapshot(identity: "spotify", state: .stopped))
        XCTAssertNotEqual(controller.state.action, .progressFollow)
        XCTAssertTrue(controller.state.action.isRestful || controller.state.action == .inspect)
        XCTAssertEqual(controller.state.position.x, layout().trailX(fraction: 0, spriteHalfWidth: 12), accuracy: 1e-6)
    }

    func testRestsWhenLiveStreamHasNoDuration() {
        let live = MediaSnapshot(identity: "browser", state: .playing, elapsed: 45, duration: nil, elapsedAt: now(),
                                 rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: false)
        let controller = settledOnTrail(media: live)
        XCTAssertNotEqual(controller.state.action, .progressFollow)
    }

    func testExternalSeekSnapsWithoutTravelAnimation() {
        let media = playing(elapsed: 10, duration: 100, at: now())
        let controller = settledOnTrail(media: media)
        let t = now().addingTimeInterval(20)
        let firstX = controller.state.position.x

        let after = playing(elapsed: 90, duration: 100, at: t)
        controller.tick(now: t, media: after)
        let expectedX = layout().trailX(fraction: 0.9, spriteHalfWidth: 12)
        XCTAssertNotEqual(firstX, controller.state.position.x)
        XCTAssertEqual(controller.state.position.x, expectedX, accuracy: 1e-6)
    }

    func testScrubCarriesThePetAndReturnsTheSeekFraction() {
        let media = playing(elapsed: 10, duration: 100, at: now())
        let controller = settledOnTrail(media: media)
        let t = now().addingTimeInterval(20)
        controller.beginScrub(now: t)
        XCTAssertEqual(controller.state.action, .dash)
        let x = layout().trailX(fraction: 0.75, spriteHalfWidth: 12)
        controller.scrub(x: x, now: t)
        XCTAssertEqual(controller.state.position.x, x, accuracy: 1e-6)
        XCTAssertEqual(controller.state.facing, .right)
        // Ticks while scrubbing never pull the pet back to the playhead.
        controller.tick(now: t.addingTimeInterval(0.25), media: media)
        XCTAssertEqual(controller.state.position.x, x, accuracy: 1e-6)

        let fraction = controller.endScrub(now: t.addingTimeInterval(0.5))
        XCTAssertEqual(fraction ?? -1, 0.75, accuracy: 1e-9)
        XCTAssertEqual(controller.state.action, .progressFollow)

        // The seek hold keeps the pet there while the stale snapshot lingers…
        controller.tick(now: t.addingTimeInterval(1.0), media: media)
        XCTAssertEqual(controller.state.position.x, x, accuracy: 1e-6)
        // …and after it expires the readback steers again.
        controller.tick(now: t.addingTimeInterval(0.5 + PetController.seekHold + 0.1), media: media)
        XCTAssertNotEqual(controller.state.position.x, x)
    }

    func testScrubOutsideTheTrailClampsAndScrubWithoutMediaSeeksNothing() {
        let stopped = MediaSnapshot(identity: "spotify", state: .stopped)
        let controller = settledOnTrail(media: stopped)
        let t = now().addingTimeInterval(20)
        controller.beginScrub(now: t)
        controller.scrub(x: -500, now: t)
        XCTAssertEqual(controller.state.position.x, layout().trailX(fraction: 0, spriteHalfWidth: 12), accuracy: 1e-6)
        controller.scrub(x: 5000, now: t)
        XCTAssertEqual(controller.state.position.x, layout().trailX(fraction: 1, spriteHalfWidth: 12), accuracy: 1e-6)
        XCTAssertNil(controller.endScrub(now: t))
        XCTAssertEqual(controller.state.action, .idle)
    }

    func testTrailTapDashesToTheFractionAndHoldsIt() {
        // Paused, so the stale readback keeps saying 0.1 the whole time.
        let media = MediaSnapshot(identity: "spotify", state: .paused, elapsed: 10, duration: 100, elapsedAt: now(),
                                  rate: 0, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        let controller = settledOnTrail(media: media)
        let t = now().addingTimeInterval(20)
        controller.seekTo(fraction: 0.5, now: t)
        XCTAssertEqual(controller.state.action, .dash)
        let targetX = layout().trailX(fraction: 0.5, spriteHalfWidth: 12)
        var now = t
        var arrivedAt: Date?
        for _ in 0..<80 { // 20 s covers the dash even though the snapshot stays stale
            now = now.addingTimeInterval(0.25)
            controller.tick(now: now, media: media)
            if arrivedAt == nil, abs(controller.state.position.x - targetX) < 1e-6 { arrivedAt = now }
            if let a = arrivedAt, now.timeIntervalSince(a) < PetController.seekHold - 0.3 {
                XCTAssertEqual(controller.state.position.x, targetX, accuracy: 1e-6, "holds after arriving")
                XCTAssertEqual(controller.state.action, .progressFollow)
            }
        }
        XCTAssertNotNil(arrivedAt, "the dash reaches the tapped spot even if the readback is stale")
        // Long after the hold the (stale) readback steers again.
        XCTAssertNotEqual(controller.state.position.x, targetX)
    }

    func testWalkToIsIgnoredOnThePlaybackPage() {
        let controller = settledOnTrail(media: playing(elapsed: 10, duration: 100, at: now()))
        controller.walkTo(x: 100, now: now().addingTimeInterval(20))
        XCTAssertEqual(controller.state.action, .progressFollow)
    }
}
