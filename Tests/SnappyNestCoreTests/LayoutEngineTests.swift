import CoreGraphics
import XCTest
@testable import SnappyNestCore

final class LayoutEngineTests: XCTestCase {
    private let touchBarBounds = CGRect(x: 0, y: 0, width: 685, height: 30)  // measured M1 13"

    func testRegionsCoverFullWidthAndAddUp() {
        let engine = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0)
        let r = engine.regions
        XCTAssertEqual(r.battery.minX, r.full.minX, accuracy: 1e-6)
        XCTAssertEqual(r.middle.minX,  r.battery.maxX, accuracy: 1e-6)
        XCTAssertEqual(r.right.minX,   r.middle.maxX, accuracy: 1e-6)
        XCTAssertEqual(r.right.maxX,   r.full.maxX,   accuracy: 1e-6)

        XCTAssertEqual(
            r.battery.width + r.middle.width + r.right.width,
            r.full.width,
            accuracy: 1e-6
        )
    }

    func testRightRegionSplitsIntoThreeControls() {
        let engine = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0)
        let r = engine.regions
        XCTAssertEqual(r.brightness.minX, r.right.minX, accuracy: 1e-6)
        XCTAssertEqual(r.volume.minX,     r.brightness.maxX, accuracy: 1e-6)
        XCTAssertEqual(r.playPause.minX,  r.volume.maxX, accuracy: 1e-6)
        XCTAssertEqual(r.playPause.maxX,  r.right.maxX, accuracy: 1e-6)
        XCTAssertEqual(
            r.brightness.width + r.volume.width + r.playPause.width,
            r.right.width,
            accuracy: 1e-6
        )
    }

    func testSkySpansFullWidth() {
        let engine = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0)
        XCTAssertEqual(engine.regions.sky, engine.bounds)
    }

    func testShareRatiosAtStandardWidth() {
        let engine = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0)
        let r = engine.regions
        // Sanity: standard width comfortably exceeds the minimum-control clamp.
        XCTAssertEqual(r.battery.width / touchBarBounds.width, 0.09, accuracy: 1e-6)
        XCTAssertEqual(r.middle.width  / touchBarBounds.width, 0.58, accuracy: 1e-6)
        XCTAssertEqual(r.right.width   / touchBarBounds.width, 0.33, accuracy: 1e-6)
    }

    func testMinimumControlClampAtTinyWidth() {
        // Ridiculous 90pt strip: battery + right hit minimums, middle shrinks.
        let engine = LayoutEngine(bounds: CGRect(x: 0, y: 0, width: 90, height: 30),
                                  backingScale: 1.0)
        let r = engine.regions
        XCTAssertGreaterThanOrEqual(r.battery.width, LayoutEngine.minimumControlWidth - 1e-6)
        XCTAssertGreaterThanOrEqual(r.right.width,   3 * LayoutEngine.minimumControlWidth - 1e-6)
    }

    func testPetGroundXStaysInsideMiddle() {
        let engine = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0)
        let m = engine.regions.middle
        let halfW: CGFloat = 8
        for f in stride(from: 0.0, through: 1.0, by: 0.1) {
            let x = engine.petGroundX(fraction: f, spriteHalfWidth: halfW)
            XCTAssertGreaterThanOrEqual(x, m.minX + halfW - 1e-6)
            XCTAssertLessThanOrEqual(x,    m.maxX - halfW + 1e-6)
        }
    }

    func testSnapToPixel() {
        let engine = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0)
        let snapped = engine.snap(CGPoint(x: 100.34, y: 15.19))
        // On 2x, half-points align. Should round to nearest 0.5.
        XCTAssertEqual(snapped.x * 2, (snapped.x * 2).rounded(), accuracy: 1e-9)
        XCTAssertEqual(snapped.y * 2, (snapped.y * 2).rounded(), accuracy: 1e-9)
    }
}
