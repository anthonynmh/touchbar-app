import XCTest
@testable import SnappyNestCore

final class WorldTimeTests: XCTestCase {
    func testFractionForMidnight() {
        let t = WorldTime(hour: 0, minute: 0, second: 0)
        XCTAssertEqual(t.fraction, 0.0, accuracy: 1e-9)
    }

    func testFractionForNoon() {
        let t = WorldTime(hour: 12, minute: 0, second: 0)
        XCTAssertEqual(t.fraction, 0.5, accuracy: 1e-9)
    }

    func testFractionForSixAM() {
        let t = WorldTime(hour: 6, minute: 0, second: 0)
        XCTAssertEqual(t.fraction, 0.25, accuracy: 1e-9)
    }

    func testFractionMonotonic() {
        var prev: Double = -1
        for hour in 0..<24 {
            for minute in stride(from: 0, to: 60, by: 15) {
                let t = WorldTime(hour: hour, minute: minute, second: 0)
                XCTAssertGreaterThan(t.fraction, prev)
                prev = t.fraction
            }
        }
    }

    func testDayProgressAtSunriseNoonSunset() {
        XCTAssertEqual(WorldTime(hour: 6, minute: 0, second: 0).dayProgress ?? -1, 0.0, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 12, minute: 0, second: 0).dayProgress ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 17, minute: 59, second: 59).dayProgress ?? -1, 1.0, accuracy: 0.01)
    }

    func testNightProgressAtMoonriseMidnightMoonset() {
        XCTAssertEqual(WorldTime(hour: 18, minute: 0, second: 0).nightProgress ?? -1, 0.0, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 0, minute: 0, second: 0).nightProgress ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 5, minute: 59, second: 59).nightProgress ?? -1, 1.0, accuracy: 0.01)
    }

    func testDaytimeBoundaries() {
        XCTAssertTrue(WorldTime(hour: 6, minute: 0, second: 0).isDaytime)
        XCTAssertTrue(WorldTime(hour: 17, minute: 59, second: 0).isDaytime)
        XCTAssertFalse(WorldTime(hour: 18, minute: 0, second: 0).isDaytime)
        XCTAssertFalse(WorldTime(hour: 5, minute: 59, second: 0).isDaytime)
    }
}
