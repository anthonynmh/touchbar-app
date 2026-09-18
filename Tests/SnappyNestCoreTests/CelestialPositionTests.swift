import CoreGraphics
import XCTest
@testable import SnappyNestCore

final class CelestialPositionTests: XCTestCase {
    private let size = CGSize(width: 685, height: 30)

    private func at(_ h: Int, _ m: Int = 0) -> CelestialPosition {
        CelestialSolver.position(for: WorldTime(hour: h, minute: m, second: 0), sceneSize: size)
    }

    func testMidnightIsMoonAtCenter() {
        let p = at(0)
        XCTAssertEqual(p.body, .moon)
        XCTAssertEqual(p.point.x, size.width / 2, accuracy: 1e-6)
    }

    func testNoonIsSunAtCenter() {
        let p = at(12)
        XCTAssertEqual(p.body, .sun)
        XCTAssertEqual(p.point.x, size.width / 2, accuracy: 1e-6)
    }

    func testSunRisesAtLeftEdgeAndSetsAtRightEdge() {
        XCTAssertEqual(at(6).point.x, 0, accuracy: 1e-6)
        XCTAssertEqual(at(17, 59).point.x, size.width, accuracy: size.width / (12 * 60) + 1e-6)
        XCTAssertEqual(at(6).point.y, CelestialSolver.topInset + CelestialSolver.arcAmplitude, accuracy: 1e-6)
    }

    func testMoonRisesAtLeftEdgeAtSunset() {
        let p = at(18)
        XCTAssertEqual(p.body, .moon)
        XCTAssertEqual(p.point.x, 0, accuracy: 1e-6)
        XCTAssertEqual(at(5, 59).body, .moon)
        XCTAssertEqual(at(5, 59).point.x, size.width, accuracy: size.width / (12 * 60) + 1e-6)
    }

    func testArcPeaksAtNoonAndMidnight() {
        XCTAssertLessThan(at(12).point.y, at(10).point.y)
        XCTAssertLessThan(at(0).point.y, at(22).point.y)
        XCTAssertEqual(at(12).point.y, CelestialSolver.topInset, accuracy: 1e-6)
    }

    func testHorizontalRangeIsRespected() {
        let range: ClosedRange<CGFloat> = 100...500
        let rise = CelestialSolver.position(for: WorldTime(hour: 6, minute: 0, second: 0), sceneSize: size, horizontalRange: range)
        let noon = CelestialSolver.position(for: WorldTime(hour: 12, minute: 0, second: 0), sceneSize: size, horizontalRange: range)
        XCTAssertEqual(rise.point.x, 100, accuracy: 1e-6)
        XCTAssertEqual(noon.point.x, 300, accuracy: 1e-6)
    }
}
