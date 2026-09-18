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
        let model = makeModel(page: .controls)
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
        let model = makeModel(page: .controls)
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

    func testControlsPageNeverRoutesToPetOrGround() {
        let renderer = makeRenderer()
        let model = makeModel(page: .controls, brightnessAvailable: false)
        renderer.update(model: model)
        var groundX: CGFloat?
        var petTaps = 0
        renderer.onGroundTap = { groundX = $0 }
        renderer.onPetTap = { petTaps += 1 }
        renderer.handleTap(at: CGPoint(x: model.layout.brightness.midX, y: 15))
        renderer.handleTap(at: CGPoint(x: model.layout.battery.midX, y: 15))
        let pet = model.pet.hitRect(spriteSize: PetSprites.cellSize)
        renderer.handleTap(at: CGPoint(x: pet.midX, y: pet.midY))
        XCTAssertNil(groundX)
        XCTAssertEqual(petTaps, 0)
    }

    func testWorldPageIgnoresControlDragsAndTaps() {
        let renderer = makeRenderer()
        let model = makeModel(page: .world)
        renderer.update(model: model)
        var brightness: Double?
        renderer.onBrightnessChange = { brightness = $0 }
        // Where the brightness slider would be on the controls page.
        let controls = LayoutEngine(bounds: bounds, backingScale: 2, page: .controls).regions
        renderer.handleDrag(at: CGPoint(x: controls.brightness.midX, y: 15))
        XCTAssertNil(brightness)
    }

    func testDraggingTheSceneSnapsToTheNearerPage() {
        let renderer = makeRenderer()
        var pages: [LayoutEngine.Page] = []
        renderer.onPageChange = { pages.append($0) }
        renderer.update(model: makeModel(page: .world))

        // A short drag left snaps back to the world.
        renderer.beginCameraDrag()
        renderer.moveCameraDrag(translationX: -100)
        renderer.endCameraDrag(velocityX: 0)
        XCTAssertFalse(renderer.isShowingControls)
        XCTAssertEqual(pages, [])

        // Dragging past halfway commits to the controls page.
        renderer.beginCameraDrag()
        renderer.moveCameraDrag(translationX: -(bounds.width / 2 + 10))
        renderer.endCameraDrag(velocityX: 0)
        XCTAssertTrue(renderer.isShowingControls)
        XCTAssertEqual(pages, [.controls])
    }

    func testFlickCommitsRegardlessOfDistance() {
        let renderer = makeRenderer()
        var pages: [LayoutEngine.Page] = []
        renderer.onPageChange = { pages.append($0) }
        renderer.update(model: makeModel(page: .world))

        renderer.beginCameraDrag()
        renderer.moveCameraDrag(translationX: -20)
        renderer.endCameraDrag(velocityX: -(SceneRenderer.flickVelocity + 1))
        XCTAssertTrue(renderer.isShowingControls)

        renderer.update(model: makeModel(page: .controls))
        renderer.beginCameraDrag()
        renderer.moveCameraDrag(translationX: 20)
        renderer.endCameraDrag(velocityX: SceneRenderer.flickVelocity + 1)
        XCTAssertFalse(renderer.isShowingControls)
        XCTAssertEqual(pages, [.controls, .world])
    }

    func testOwnerPageChangePansTheCamera() {
        let renderer = makeRenderer()
        renderer.update(model: makeModel(page: .world))
        XCTAssertFalse(renderer.isShowingControls)
        renderer.update(model: makeModel(page: .controls))
        XCTAssertTrue(renderer.isShowingControls)
        XCTAssertNotNil(renderer.layer?.sublayers?.compactMap { $0.animation(forKey: "pageSlide") }.first,
                        "an owner-driven page change should slide, not jump")
        renderer.update(model: makeModel(page: .world))
        XCTAssertFalse(renderer.isShowingControls)
    }

    func testDragStartingOnASliderScrubsInsteadOfPanning() {
        let renderer = makeRenderer()
        let controls = makeModel(page: .controls)
        renderer.update(model: controls)
        XCTAssertTrue(renderer.isSliderPoint(CGPoint(x: controls.layout.brightness.midX, y: 15)))
        XCTAssertTrue(renderer.isSliderPoint(CGPoint(x: controls.layout.volume.midX, y: 15)))
        XCTAssertFalse(renderer.isSliderPoint(CGPoint(x: controls.layout.battery.midX, y: 15)))
        XCTAssertFalse(renderer.isSliderPoint(CGPoint(x: controls.layout.playPause.midX, y: 15)))

        let world = makeModel(page: .world)
        renderer.update(model: world)
        XCTAssertFalse(renderer.isSliderPoint(CGPoint(x: controls.layout.brightness.midX, y: 15)),
                       "on the world page the same spot is scenery, so a drag pans")
    }

    private func makeRenderer() -> SceneRenderer {
        SceneRenderer(frame: bounds)
    }

    private func makeModel(page: LayoutEngine.Page = .world, brightnessAvailable: Bool = true) -> SceneModel {
        let engine = LayoutEngine(bounds: bounds, backingScale: 2, page: page)
        let layout = engine.regions
        let world = engine.with(page: .world).regions
        let time = WorldTime(hour: 12, minute: 0, second: 0)
        let pet = PetState(action: .idle, facing: .right,
                           position: CGPoint(x: world.middle.minX + 80, y: world.middle.maxY - 4),
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
                horizontalRange: (world.middle.minX + 8)...(world.middle.maxX - 8)
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
