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

    private func makeRenderer() -> SceneRenderer {
        SceneRenderer(frame: bounds)
    }

    private func makeModel() -> SceneModel {
        let layout = LayoutEngine(bounds: bounds, backingScale: 2).regions
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
            time: WorldTime(hour: 12, minute: 0, second: 0),
            celestial: CelestialSolver.position(
                for: WorldTime(hour: 12, minute: 0, second: 0),
                sceneSize: bounds.size
            ),
            layout: layout,
            props: [],
            pet: .placeholder,
            battery: BatterySnapshot(isPresent: true, percentage: 0.8, isCharging: false),
            brightness: 0.5,
            brightnessAvailable: true,
            volume: 0.5,
            volumeMuted: false,
            volumeAvailable: true,
            media: media,
            progressFraction: 0.5
        )
    }
}
