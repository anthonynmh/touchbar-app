import AppKit
import SnappyNestCore
import XCTest
@testable import SnappyNestUI

final class SceneRendererInteractionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1004, height: 30)

    func testConfiguresDirectTouchClickAndPanRecognizers() {
        let renderer = makeRenderer()
        let recognizers = renderer.gestureRecognizers

        let click = recognizers.compactMap { $0 as? NSClickGestureRecognizer }
        let pan = recognizers.compactMap { $0 as? NSPanGestureRecognizer }

        XCTAssertEqual(click.count, 1)
        XCTAssertEqual(pan.count, 1)
        XCTAssertTrue(click[0].allowedTouchTypes.contains(.direct))
        XCTAssertTrue(pan[0].allowedTouchTypes.contains(.direct))
        XCTAssertTrue(renderer.acceptsFirstMouse(for: nil))
    }

    func testTapRoutesToBrightnessVolumeAndPlayPause() {
        let renderer = makeRenderer()
        let model = makeModel()
        renderer.update(model: model)

        var brightness: Double?
        var volume: Double?
        var toggleCount = 0
        renderer.onBrightnessChange = { brightness = $0 }
        renderer.onVolumeChange = { volume = $0 }
        renderer.onTogglePlayPause = { toggleCount += 1 }

        renderer.handleTap(at: CGPoint(x: model.layout.brightness.midX, y: 15))
        renderer.handleTap(at: CGPoint(x: model.layout.volume.midX, y: 15))
        renderer.handleTap(at: CGPoint(x: model.layout.playPause.midX, y: 15))

        XCTAssertEqual(brightness ?? -1, 0.5, accuracy: 1e-6)
        XCTAssertEqual(volume ?? -1, 0.5, accuracy: 1e-6)
        XCTAssertEqual(toggleCount, 1)
    }

    func testPanClampsControlValues() {
        let renderer = makeRenderer()
        let model = makeModel()
        renderer.update(model: model)

        var brightness: Double?
        var volume: Double?
        renderer.onBrightnessChange = { brightness = $0 }
        renderer.onVolumeChange = { volume = $0 }

        renderer.handleDrag(at: CGPoint(x: model.layout.brightness.minX, y: 15))
        renderer.handleDrag(at: CGPoint(x: model.layout.volume.maxX - 0.001, y: 15))

        XCTAssertEqual(brightness ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(volume ?? -1, 1, accuracy: 1e-6)
    }

    func testTapOnPetCallsPetTapNotGround() {
        let renderer = makeRenderer()
        let model = makeModel()
        renderer.update(model: model)
        var petTaps = 0
        var groundX: CGFloat?
        renderer.onPetTap = { petTaps += 1 }
        renderer.onGroundTap = { groundX = $0 }

        let pet = model.pet.hitRect(spriteSize: PetSprites.cellSize)
        renderer.handleTap(at: CGPoint(x: pet.midX, y: pet.midY))
        // Just outside the sprite but inside the slop still counts.
        renderer.handleTap(at: CGPoint(x: pet.maxX + SceneRenderer.tapSlop - 1, y: pet.midY))

        XCTAssertEqual(petTaps, 2)
        XCTAssertNil(groundX)
    }

    func testTapOnEmptyGroundCallsGroundTapWithX() {
        let renderer = makeRenderer()
        let model = makeModel()
        renderer.update(model: model)
        var petTaps = 0
        var groundX: CGFloat?
        renderer.onPetTap = { petTaps += 1 }
        renderer.onGroundTap = { groundX = $0 }

        let x = model.layout.middle.maxX - 40
        renderer.handleTap(at: CGPoint(x: x, y: 24))

        XCTAssertEqual(petTaps, 0)
        XCTAssertEqual(groundX ?? -1, x, accuracy: 1e-6)
    }

    func testTapOutsideMiddleDoesNotCallGroundTap() {
        let renderer = makeRenderer()
        var model = makeModel()
        model = makeModel(brightnessAvailable: false)
        renderer.update(model: model)
        var groundX: CGFloat?
        renderer.onGroundTap = { groundX = $0 }
        renderer.handleTap(at: CGPoint(x: model.layout.brightness.midX, y: 15))
        renderer.handleTap(at: CGPoint(x: model.layout.battery.midX, y: 15))
        XCTAssertNil(groundX)
    }

    func testTapOnSunRevealsClockThenHidesIt() {
        let renderer = makeRenderer()
        let model = makeModel()
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        renderer.now = { clock }
        renderer.update(model: model)
        var petTaps = 0
        var groundX: CGFloat?
        renderer.onPetTap = { petTaps += 1 }
        renderer.onGroundTap = { groundX = $0 }
        XCTAssertFalse(renderer.isClockRevealed)

        renderer.handleTap(at: model.celestial.point)
        XCTAssertTrue(renderer.isClockRevealed)
        XCTAssertEqual(petTaps, 0)
        XCTAssertNil(groundX)

        clock = clock.addingTimeInterval(SceneRenderer.clockRevealDuration - 0.5)
        renderer.update(model: model)
        XCTAssertTrue(renderer.isClockRevealed)

        clock = clock.addingTimeInterval(1)
        renderer.update(model: model)
        XCTAssertFalse(renderer.isClockRevealed)
    }

    private func makeRenderer() -> SceneRenderer {
        SceneRenderer(frame: bounds)
    }

    private func makeModel(brightnessAvailable: Bool = true) -> SceneModel {
        let engine = LayoutEngine(bounds: bounds, backingScale: 2)
        let layout = engine.regions
        let time = WorldTime(hour: 12, minute: 0, second: 0)
        let pet = PetState(action: .idle, facing: .right,
                           position: CGPoint(x: layout.middle.minX + 80, y: layout.middle.maxY - 4),
                           frameIndex: 0)
        let media = MediaSnapshot(
            identity: "test",
            state: .paused,
            elapsed: 1,
            duration: 2,
            elapsedAt: Date(),
            rate: 0,
            canPlayPause: true,
            canReadPosition: true,
            canReadDuration: true
        )
        return SceneModel(
            time: time,
            celestial: CelestialSolver.position(
                for: time,
                sceneSize: bounds.size,
                horizontalRange: (layout.middle.minX + 8)...(layout.middle.maxX - 8)
            ),
            layout: layout,
            props: [],
            pet: pet,
            battery: BatterySnapshot(isPresent: true, percentage: 0.8, isCharging: false),
            brightness: 0.5,
            brightnessAvailable: brightnessAvailable,
            volume: 0.5,
            volumeMuted: false,
            volumeAvailable: true,
            media: media,
            progressFraction: 0.5
        )
    }
}
