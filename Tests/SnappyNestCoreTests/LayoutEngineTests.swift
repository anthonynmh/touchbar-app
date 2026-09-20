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

    func testControlsPageIsACenteredClusterOrderedSlidersBattery() {
        let r = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0, page: .controls).regions
        XCTAssertEqual(r.page, .controls)
        XCTAssertEqual(r.brightness.minX, r.right.minX, accuracy: 1e-6)
        XCTAssertGreaterThan(r.volume.minX, r.brightness.maxX)
        XCTAssertGreaterThan(r.battery.minX, r.volume.maxX)
        XCTAssertTrue(r.playPause.isNull, "play/pause lives on the playback page")
        XCTAssertTrue(r.trail.isNull)
        XCTAssertTrue(r.titleBanner.isNull)
        XCTAssertEqual(r.battery.maxX, r.right.maxX, accuracy: 1e-6)
        XCTAssertEqual(r.right.midX, r.full.midX, accuracy: 1e-6)
        XCTAssertEqual(r.brightness.width, LayoutEngine.maximumSliderWidth, accuracy: 1e-6)
        XCTAssertEqual(r.brightness.width, r.volume.width, accuracy: 1e-6)
        XCTAssertEqual(r.battery.width, LayoutEngine.batteryWidth, accuracy: 1e-6)
        XCTAssertTrue(r.middle.isNull)
    }

    func testPlaybackPageOrdersLabelsTrailAndSignposts() {
        let r = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0, page: .playback).regions
        XCTAssertEqual(r.page, .playback)
        let ordered = [r.titleBanner, r.elapsedLabel, r.trail, r.durationLabel, r.previous, r.playPause, r.next]
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.minX, a.maxX, "regions must not overlap")
        }
        XCTAssertEqual(r.titleBanner.minX, r.full.minX + LayoutEngine.playbackInset)
        XCTAssertEqual(r.titleBanner.maxX, (r.full.width / 3).rounded(), accuracy: 1e-6,
                       "the title sign spans the left third")
        XCTAssertLessThanOrEqual(r.next.maxX, r.full.maxX)
        XCTAssertGreaterThan(r.trail.width, 350, "the trail is most of what remains")
        XCTAssertTrue(r.middle.isNull)
        XCTAssertTrue(r.brightness.isNull)
        XCTAssertTrue(r.battery.isNull)
        for region in ordered { XCTAssertEqual(region.height, r.full.height) }
    }

    func testTrailXAndTrailFractionRoundTrip() {
        let engine = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0)
        let t = engine.with(page: .playback).regions.trail
        for f in stride(from: 0.0, through: 1.0, by: 0.125) {
            let x = engine.trailX(fraction: f, spriteHalfWidth: 12)
            XCTAssertGreaterThanOrEqual(x, t.minX + 12 - 1e-6)
            XCTAssertLessThanOrEqual(x, t.maxX - 12 + 1e-6)
            XCTAssertEqual(engine.trailFraction(x: x, spriteHalfWidth: 12), f, accuracy: 1e-9)
        }
        XCTAssertEqual(engine.trailFraction(x: -50, spriteHalfWidth: 12), 0)
        XCTAssertEqual(engine.trailFraction(x: 5000, spriteHalfWidth: 12), 1)
    }

    func testPageIndicesAreContiguousAroundTheWorld() {
        XCTAssertEqual(LayoutEngine.Page.allCases.filter(\.isInSwipeRow).map(\.index), [-1, 0, 1])
        XCTAssertEqual(LayoutEngine.Page.court.index, 0, "the court overlays the world")
        XCTAssertFalse(LayoutEngine.Page.court.isInSwipeRow)
        XCTAssertEqual(LayoutEngine.Page(index: -1), .playback)
        XCTAssertEqual(LayoutEngine.Page(index: 0), .world)
        XCTAssertEqual(LayoutEngine.Page(index: 1), .controls)
        XCTAssertNil(LayoutEngine.Page(index: 2))
    }

    func testSkySpansFullWidthOnEveryPage() {
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
        XCTAssertEqual(r.right.minX, 0, accuracy: 1e-6, "cluster never starts off-strip")
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

    func testCourtRegions() {
        let engine = LayoutEngine(bounds: CGRect(x: 0, y: 0, width: 1004, height: 30), backingScale: 2, page: .court)
        let r = engine.regions
        XCTAssertEqual(r.page, .court)
        XCTAssertEqual(r.exitSign, CGRect(x: 8, y: 0, width: 34, height: 30))
        XCTAssertEqual(r.court.minX, r.exitSign.maxX + LayoutEngine.courtGap)
        XCTAssertEqual(r.court.maxX, 1004 - LayoutEngine.courtInset)
        XCTAssertEqual(r.net.midX, r.court.midX, accuracy: 1e-9)
        XCTAssertEqual(r.net.maxY, 26, "the net stands on the ground line")
        XCTAssertEqual(r.net.height, TennisGame.netHeight)
        XCTAssertEqual(r.scoreboard.midX, r.court.midX, accuracy: 1e-9)
        XCTAssertTrue(r.middle.isNull)
        XCTAssertTrue(r.trail.isNull)
        XCTAssertTrue(r.brightness.isNull)
        // And no court on the other pages.
        XCTAssertTrue(engine.with(page: .world).regions.court.isNull)
        XCTAssertTrue(engine.with(page: .world).regions.exitSign.isNull)
    }
}
