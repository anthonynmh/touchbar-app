import CoreGraphics
import XCTest
@testable import SnappyNestCore

final class LayoutEngineTests: XCTestCase {
    private let touchBarBounds = CGRect(x: 0, y: 0, width: 1004, height: 30)  // measured usable width

    func testWorldPageGivesTheSceneTheWholeStrip() {
        let r = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0).regions
        XCTAssertEqual(r.page, .world)
        XCTAssertEqual(r.middle, r.full)
        XCTAssertTrue(r.battery.isNull)
        XCTAssertTrue(r.brightness.isNull)
        XCTAssertTrue(r.volume.isNull)
        XCTAssertTrue(r.playPause.isNull)
        XCTAssertFalse(r.brightness.contains(CGPoint(x: 500, y: 15)))
    }

    func testControlsPageOrdersSlidersPlayPauseBattery() {
        let r = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0, page: .controls).regions
        XCTAssertEqual(r.page, .controls)
        XCTAssertEqual(r.right.minX, r.full.minX + LayoutEngine.controlsInset, accuracy: 1e-6)
        XCTAssertEqual(r.brightness.minX, r.right.minX, accuracy: 1e-6)
        XCTAssertEqual(r.volume.minX, r.brightness.maxX, accuracy: 1e-6)
        XCTAssertEqual(r.playPause.minX, r.volume.maxX, accuracy: 1e-6)
        XCTAssertEqual(r.battery.minX, r.playPause.maxX, accuracy: 1e-6)
        XCTAssertEqual(r.battery.maxX, r.right.maxX, accuracy: 1e-6)
        XCTAssertEqual(
            r.brightness.width + r.volume.width + r.playPause.width + r.battery.width,
            r.right.width, accuracy: 1e-6
        )
        XCTAssertTrue(r.middle.isNull)
        XCTAssertGreaterThanOrEqual(r.battery.width, LayoutEngine.minimumBatteryWidth - 1e-6)
        XCTAssertEqual(r.brightness.width, r.volume.width, accuracy: 1e-6)
    }

    func testSkySpansFullWidthOnBothPages() {
        for page in LayoutEngine.Page.allCases {
            let engine = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0, page: page)
            XCTAssertEqual(engine.regions.sky, engine.bounds)
        }
    }

    func testMinimumControlClampAtTinyWidth() {
        let r = LayoutEngine(bounds: CGRect(x: 0, y: 0, width: 120, height: 30), backingScale: 1.0, page: .controls).regions
        XCTAssertGreaterThanOrEqual(r.brightness.width, LayoutEngine.minimumControlWidth - 1e-6)
        XCTAssertGreaterThanOrEqual(r.volume.width, LayoutEngine.minimumControlWidth - 1e-6)
        XCTAssertGreaterThan(r.battery.width, 0)
    }

    func testPetGroundXUsesTheWorldPageOnEitherPage() {
        let world = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0)
        let controls = world.with(page: .controls)
        let m = world.regions.middle
        let halfW: CGFloat = 12
        for f in stride(from: 0.0, through: 1.0, by: 0.1) {
            let x = world.petGroundX(fraction: f, spriteHalfWidth: halfW)
            XCTAssertGreaterThanOrEqual(x, m.minX + halfW - 1e-6)
            XCTAssertLessThanOrEqual(x,    m.maxX - halfW + 1e-6)
            XCTAssertEqual(x, controls.petGroundX(fraction: f, spriteHalfWidth: halfW), accuracy: 1e-6)
        }
    }

    func testSnapToPixel() {
        let engine = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0)
        let snapped = engine.snap(CGPoint(x: 100.34, y: 15.19))
        XCTAssertEqual(snapped.x * 2, (snapped.x * 2).rounded(), accuracy: 1e-9)
        XCTAssertEqual(snapped.y * 2, (snapped.y * 2).rounded(), accuracy: 1e-9)
    }
}
