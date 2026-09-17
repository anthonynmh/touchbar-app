import CoreGraphics
import XCTest
@testable import SnappyNestCore

final class CelestialPositionTests: XCTestCase {
    private let size = CGSize(width: 685, height: 30)

    func testSunIsAtLeftAtMidnightNo() {
        // midnight is a moon, not a sun
        let p = CelestialSolver.position(for: WorldTime(hour: 0, minute: 0, second: 0), sceneSize: size)
        XCTAssertEqual(p.body, .moon)
    }

    func testSunAtNoonIsCentered() {
        let p = CelestialSolver.position(for: WorldTime(hour: 12, minute: 0, second: 0), sceneSize: size)
        XCTAssertEqual(p.body, .sun)
        XCTAssertEqual(p.point.x, size.width / 2, accuracy: 1e-6)
    }

    func testMoonAtMidnightIsCentered() {
        let p = CelestialSolver.position(for: WorldTime(hour: 0, minute: 0, second: 0), sceneSize: size)
        XCTAssertEqual(p.body, .moon)
        XCTAssertEqual(p.point.x, 0, accuracy: 1e-6)
        // Midnight is the left edge in the panorama; a mirrored copy should
        // render at x = width to keep the moon visible at the seam.
        XCTAssertNotNil(p.seamMirror)
        XCTAssertEqual(p.seamMirror?.x ?? -1, size.width, accuracy: 1e-6)
    }

    func testSunArcPeaksAtNoon() {
        let noon = CelestialSolver.position(for: WorldTime(hour: 12, minute: 0, second: 0), sceneSize: size)
        let ten = CelestialSolver.position(for: WorldTime(hour: 10, minute: 0, second: 0), sceneSize: size)
        // Peak = smallest y in flipped coords.
        XCTAssertLessThan(noon.point.y, ten.point.y)
    }

    func testHorizontalLinearMapping() {
        let a = CelestialSolver.position(for: WorldTime(hour: 6, minute: 0, second: 0), sceneSize: size).point.x
        let b = CelestialSolver.position(for: WorldTime(hour: 18, minute: 0, second: 0), sceneSize: size).point.x
        XCTAssertEqual(a, size.width * 0.25, accuracy: 1e-6)
        XCTAssertEqual(b, size.width * 0.75, accuracy: 1e-6)
    }

    func testMoonSeamMirrorNearEnd() {
        // Just before midnight: moon at x close to width. Mirror should be near 0.
        let t = WorldTime(hour: 23, minute: 59, second: 59)
        let p = CelestialSolver.position(for: t, sceneSize: size)
        if p.point.x > size.width - CelestialSolver.bodyHalfWidth {
            XCTAssertNotNil(p.seamMirror)
        }
    }
}
