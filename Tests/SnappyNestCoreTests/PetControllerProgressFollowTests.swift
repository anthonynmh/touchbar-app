import CoreGraphics
import XCTest
@testable import SnappyNestCore

final class PetControllerProgressFollowTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 685, height: 30)

    private func layout() -> LayoutEngine {
        LayoutEngine(bounds: bounds, backingScale: 2.0)
    }

    private func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

    func testFollowsProgressWhenPlaying() {
        let controller = PetController(seed: 1, layout: layout())
        let media = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 30, duration: 120, elapsedAt: now(), rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        controller.tick(now: now(), media: media)
        XCTAssertEqual(controller.state.action, .progressFollow)

        let expectedX = layout().petGroundX(fraction: 0.25, spriteHalfWidth: 12)
        XCTAssertEqual(controller.state.position.x, expectedX, accuracy: 1e-6)
    }

    func testFreeRoamsWhenPaused() {
        let controller = PetController(seed: 1, layout: layout())
        let media = MediaSnapshot(identity: "spotify", state: .stopped)
        controller.tick(now: now(), media: media)
        XCTAssertNotEqual(controller.state.action, .progressFollow)
    }

    func testFreeRoamsWhenLiveStream() {
        // Playing with unknown duration should NOT trigger follow.
        let controller = PetController(seed: 1, layout: layout())
        let live = MediaSnapshot(identity: "browser", state: .playing, elapsed: 45, duration: nil, elapsedAt: now(), rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: false)
        controller.tick(now: now(), media: live)
        XCTAssertNotEqual(controller.state.action, .progressFollow)
    }

    func testSeekSnapsWithoutTravelAnimation() {
        let controller = PetController(seed: 1, layout: layout())
        let before = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 10, duration: 100, elapsedAt: now(), rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        controller.tick(now: now(), media: before)
        let firstX = controller.state.position.x

        let after = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 90, duration: 100, elapsedAt: now(), rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        controller.tick(now: now(), media: after)
        let secondX = controller.state.position.x

        XCTAssertNotEqual(firstX, secondX)
        // Position went straight to the new fraction, no intermediate frames.
        let expectedX = layout().petGroundX(fraction: 0.9, spriteHalfWidth: 12)
        XCTAssertEqual(secondX, expectedX, accuracy: 1e-6)
    }
}
