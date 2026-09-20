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

    func testTapRoutesToBrightnessAndVolume() {
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
        renderer.handleTap(at: CGPoint(x: model.layout.battery.midX, y: 15))

        XCTAssertEqual(brightness ?? -1, 0.5, accuracy: 1e-6)
        XCTAssertEqual(volume ?? -1, 0.5, accuracy: 1e-6)
        XCTAssertEqual(toggleCount, 0, "play/pause lives on the playback page now")
    }

    func testPlaybackSignpostsRouteToSkipAndPlayPause() {
        let renderer = makeRenderer()
        let model = makeModel(page: .playback)
        renderer.update(model: model)
        var previous = 0, next = 0, toggles = 0
        var seek: Double?
        renderer.onPreviousTrack = { previous += 1 }
        renderer.onNextTrack = { next += 1 }
        renderer.onTogglePlayPause = { toggles += 1 }
        renderer.onSeek = { seek = $0 }

        renderer.handleTap(at: CGPoint(x: model.layout.previous.midX, y: 15))
        renderer.handleTap(at: CGPoint(x: model.layout.playPause.midX, y: 15))
        renderer.handleTap(at: CGPoint(x: model.layout.next.midX, y: 15))
        XCTAssertEqual([previous, toggles, next], [1, 1, 1])
        XCTAssertNil(seek)

        // Unavailable media: the signposts are inert.
        renderer.update(model: makeModel(page: .playback, media: MediaSnapshot(identity: "none", state: .unknown)))
        renderer.handleTap(at: CGPoint(x: model.layout.previous.midX, y: 15))
        renderer.handleTap(at: CGPoint(x: model.layout.playPause.midX, y: 15))
        renderer.handleTap(at: CGPoint(x: model.layout.next.midX, y: 15))
        XCTAssertEqual([previous, toggles, next], [1, 1, 1])
    }

    func testTapOnTheTrailSeeksToThatFraction() {
        let renderer = makeRenderer()
        let model = makeModel(page: .playback)
        renderer.update(model: model)
        var seek: Double?
        var petTaps = 0
        renderer.onSeek = { seek = $0 }
        renderer.onPetTap = { petTaps += 1 }

        let engine = LayoutEngine(bounds: bounds, backingScale: 2, page: .playback)
        let x = engine.trailX(fraction: 0.8, spriteHalfWidth: 12)
        renderer.handleTap(at: CGPoint(x: x, y: 20))
        XCTAssertEqual(seek ?? -1, 0.8, accuracy: 1e-9)
        XCTAssertEqual(petTaps, 0)

        // The pet itself still takes the tap.
        let pet = model.pet.hitRect(spriteSize: PetSprites.cellSize)
        renderer.handleTap(at: CGPoint(x: pet.midX, y: pet.midY))
        XCTAssertEqual(petTaps, 1)

        // The title sign is not part of the trail: tapping it never seeks.
        seek = nil
        renderer.handleTap(at: CGPoint(x: model.layout.titleBanner.midX, y: 15))
        XCTAssertNil(seek)
        XCTAssertEqual(petTaps, 1)

        // Media that cannot seek: trail taps do nothing.
        seek = nil
        let noSeek = MediaSnapshot(identity: "browser", state: .playing, elapsed: 1, duration: 2, elapsedAt: Date(),
                                   rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true, canSeek: false)
        renderer.update(model: makeModel(page: .playback, media: noSeek))
        renderer.handleTap(at: CGPoint(x: x, y: 20))
        XCTAssertNil(seek)
    }

    func testDragStartingOnThePetScrubsOnlyOnThePlaybackPage() {
        let renderer = makeRenderer()
        let playback = makeModel(page: .playback)
        renderer.update(model: playback)
        let pet = playback.pet.hitRect(spriteSize: PetSprites.cellSize)
        XCTAssertTrue(renderer.isScrubPoint(CGPoint(x: pet.midX, y: pet.midY)))
        XCTAssertTrue(renderer.isScrubPoint(CGPoint(x: pet.maxX + SceneRenderer.tapSlop - 1, y: pet.midY)))
        XCTAssertFalse(renderer.isScrubPoint(CGPoint(x: pet.maxX + 40, y: pet.midY)))

        let world = makeModel(page: .world)
        renderer.update(model: world)
        let worldPet = world.pet.hitRect(spriteSize: PetSprites.cellSize)
        XCTAssertFalse(renderer.isScrubPoint(CGPoint(x: worldPet.midX, y: worldPet.midY)),
                       "on the world page a drag on the pet pans the scene")
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
        XCTAssertEqual(renderer.currentPage, .world)
        XCTAssertEqual(pages, [])

        // Dragging past halfway commits to the controls page.
        renderer.beginCameraDrag()
        renderer.moveCameraDrag(translationX: -(bounds.width / 2 + 10))
        renderer.endCameraDrag(velocityX: 0)
        XCTAssertEqual(renderer.currentPage, .controls)
        XCTAssertEqual(pages, [.controls])

        // From the world, dragging right past halfway reaches the playback page.
        renderer.update(model: makeModel(page: .world))
        renderer.beginCameraDrag()
        renderer.moveCameraDrag(translationX: bounds.width / 2 + 10)
        renderer.endCameraDrag(velocityX: 0)
        XCTAssertEqual(renderer.currentPage, .playback)
        XCTAssertEqual(pages, [.controls, .playback])

        // The camera clamps at the ends: a huge drag from playback stays there.
        renderer.update(model: makeModel(page: .playback))
        renderer.beginCameraDrag()
        renderer.moveCameraDrag(translationX: 5000)
        renderer.endCameraDrag(velocityX: 0)
        XCTAssertEqual(renderer.currentPage, .playback)
        XCTAssertEqual(pages, [.controls, .playback])
    }

    func testFlickCommitsRegardlessOfDistance() {
        let renderer = makeRenderer()
        var pages: [LayoutEngine.Page] = []
        renderer.onPageChange = { pages.append($0) }
        renderer.update(model: makeModel(page: .world))

        renderer.beginCameraDrag()
        renderer.moveCameraDrag(translationX: -20)
        renderer.endCameraDrag(velocityX: -(SceneRenderer.flickVelocity + 1))
        XCTAssertEqual(renderer.currentPage, .controls)

        renderer.update(model: makeModel(page: .controls))
        renderer.beginCameraDrag()
        renderer.moveCameraDrag(translationX: 20)
        renderer.endCameraDrag(velocityX: SceneRenderer.flickVelocity + 1)
        XCTAssertEqual(renderer.currentPage, .world)

        // A flick moves exactly one page: world → playback, never past it.
        renderer.update(model: makeModel(page: .world))
        renderer.beginCameraDrag()
        renderer.moveCameraDrag(translationX: 20)
        renderer.endCameraDrag(velocityX: SceneRenderer.flickVelocity + 1)
        XCTAssertEqual(renderer.currentPage, .playback)
        renderer.update(model: makeModel(page: .playback))
        renderer.beginCameraDrag()
        renderer.moveCameraDrag(translationX: 20)
        renderer.endCameraDrag(velocityX: SceneRenderer.flickVelocity + 1)
        XCTAssertEqual(renderer.currentPage, .playback)
        XCTAssertEqual(pages, [.controls, .world, .playback])
    }

    func testOwnerPageChangePansTheCamera() {
        let renderer = makeRenderer()
        renderer.update(model: makeModel(page: .world))
        XCTAssertEqual(renderer.currentPage, .world)
        renderer.update(model: makeModel(page: .controls))
        XCTAssertEqual(renderer.currentPage, .controls)
        XCTAssertNotNil(renderer.layer?.sublayers?.compactMap { $0.animation(forKey: "pageSlide") }.first,
                        "an owner-driven page change should slide, not jump")
        renderer.update(model: makeModel(page: .playback))
        XCTAssertEqual(renderer.currentPage, .playback)
    }

    func testDragStartingOnASliderScrubsInsteadOfPanning() {
        let renderer = makeRenderer()
        let controls = makeModel(page: .controls)
        renderer.update(model: controls)
        XCTAssertTrue(renderer.isSliderPoint(CGPoint(x: controls.layout.brightness.midX, y: 15)))
        XCTAssertTrue(renderer.isSliderPoint(CGPoint(x: controls.layout.volume.midX, y: 15)))
        XCTAssertFalse(renderer.isSliderPoint(CGPoint(x: controls.layout.battery.midX, y: 15)))

        let world = makeModel(page: .world)
        renderer.update(model: world)
        XCTAssertFalse(renderer.isSliderPoint(CGPoint(x: controls.layout.brightness.midX, y: 15)),
                       "on the world page the same spot is scenery, so a drag pans")
    }

    private func makeRenderer() -> SceneRenderer {
        SceneRenderer(frame: bounds)
    }

    private func makeModel(page: LayoutEngine.Page = .world, brightnessAvailable: Bool = true,
                           media: MediaSnapshot? = nil, game: KeepAwayGame? = nil,
                           petX: CGFloat? = nil) -> SceneModel {
        let engine = LayoutEngine(bounds: bounds, backingScale: 2, page: page)
        let layout = engine.regions
        let world = engine.with(page: .world).regions
        let time = WorldTime(hour: 12, minute: 0, second: 0)
        let petX = petX ?? (page == .playback ? engine.trailX(fraction: 0.5, spriteHalfWidth: 12) : world.middle.minX + 80)
        let pet = PetState(action: .idle, facing: .right,
                           position: CGPoint(x: petX, y: world.middle.maxY - 4),
                           frameIndex: 0)
        let media = media ?? MediaSnapshot(
            identity: "test",
            state: .paused,
            elapsed: 1,
            duration: 2,
            elapsedAt: Date(),
            rate: 0,
            canPlayPause: true,
            canReadPosition: true,
            canReadDuration: true,
            canSeek: true,
            canSkip: true
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
            progressFraction: 0.5,
            game: game
        )
    }

    // MARK: - Keep-away

    /// A game that has been served with the pet far right, so the ball has
    /// rolled left out of the nook.
    private func servedGame(world: CGRect) -> KeepAwayGame {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        var game = KeepAwayGame(arena: world, nookX: SceneLayout.nookX(inside: world), now: t0)
        _ = game.tick(dt: 0.125, now: t0.addingTimeInterval(1), petX: world.maxX - 20)
        for i in 1...8 {
            _ = game.tick(dt: 0.125, now: t0.addingTimeInterval(1 + 0.125 * Double(i)), petX: world.maxX - 20)
        }
        XCTAssertLessThan(game.ballX, game.nookX - 40, "well clear of the nook")
        return game
    }

    func testNookTapStartsAndEndsTheGameFromTheWorldPageOnly() {
        let renderer = makeRenderer()
        let model = makeModel(page: .world)
        renderer.update(model: model)
        var zoneTaps = 0, groundTaps = 0, petTaps = 0
        renderer.onActivityZoneTap = { zoneTaps += 1 }
        renderer.onGroundTap = { _ in groundTaps += 1 }
        renderer.onPetTap = { petTaps += 1 }

        let zone = SceneLayout.activityZone(inside: model.layout.middle)
        renderer.handleTap(at: CGPoint(x: zone.midX, y: zone.midY))
        XCTAssertEqual([zoneTaps, groundTaps], [1, 0])
        XCTAssertFalse(renderer.isGameActive, "no game in the model yet")

        // Just outside the zone is ordinary ground.
        renderer.handleTap(at: CGPoint(x: zone.maxX + 2, y: zone.midY))
        XCTAssertEqual([zoneTaps, groundTaps], [1, 1])

        // The pet standing on the nook does not steal the exit tap.
        let onNook = makeModel(page: .world, game: servedGame(world: model.layout.middle), petX: zone.midX)
        renderer.update(model: onNook)
        XCTAssertTrue(renderer.isGameActive)
        renderer.handleTap(at: CGPoint(x: zone.midX, y: zone.midY))
        XCTAssertEqual([zoneTaps, petTaps], [2, 0])

        // Other pages have no nook.
        renderer.update(model: makeModel(page: .controls))
        renderer.handleTap(at: CGPoint(x: zone.midX, y: zone.midY))
        XCTAssertEqual(zoneTaps, 2)
    }

    func testAnyGroundTapKicksDuringPlayAndTheNookStillExits() {
        let renderer = makeRenderer()
        let idle = makeModel(page: .world)
        renderer.update(model: idle)
        var kicks: [CGFloat] = []
        var groundTaps = 0, petTaps = 0, zoneTaps = 0
        renderer.onKick = { kicks.append($0) }
        renderer.onGroundTap = { _ in groundTaps += 1 }
        renderer.onPetTap = { petTaps += 1 }
        renderer.onActivityZoneTap = { zoneTaps += 1 }

        // No game: ground is ground, the pet is the pet.
        let middle = idle.layout.middle
        renderer.handleTap(at: CGPoint(x: middle.maxX - 30, y: 20))
        XCTAssertEqual(kicks, [])
        XCTAssertEqual(groundTaps, 1)

        let game = servedGame(world: middle)
        let pet = makeModel(page: .world, game: game, petX: middle.maxX - 100)
        renderer.update(model: pet)
        let petRect = pet.pet.hitRect(spriteSize: PetSprites.cellSize)
        let ball = game.ballRect()
        renderer.handleTap(at: CGPoint(x: middle.maxX - 30, y: 20))    // empty ground
        renderer.handleTap(at: CGPoint(x: petRect.midX, y: petRect.midY)) // the pet
        renderer.handleTap(at: CGPoint(x: ball.midX, y: ball.midY))     // the ball itself
        XCTAssertEqual(kicks, [middle.maxX - 30, petRect.midX, ball.midX],
                       "during play every ground tap is a kick, whatever it lands on")
        XCTAssertEqual([groundTaps, petTaps], [1, 0])

        // The nook still exits, and the sun still shows the clock.
        let zone = SceneLayout.activityZone(inside: middle)
        renderer.handleTap(at: CGPoint(x: zone.midX, y: zone.midY))
        XCTAssertEqual(zoneTaps, 1)
        XCTAssertEqual(kicks.count, 3)
    }
}
