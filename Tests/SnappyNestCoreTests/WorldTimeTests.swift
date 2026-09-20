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

    func testDaylightRampsAroundSunriseAndSunset() {
        XCTAssertEqual(WorldTime(hour: 3, minute: 0, second: 0).daylight, 0, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 5, minute: 30, second: 0).daylight, 0, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 6, minute: 0, second: 0).daylight, 0.5, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 6, minute: 30, second: 0).daylight, 1, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 12, minute: 0, second: 0).daylight, 1, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 18, minute: 0, second: 0).daylight, 0.5, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 18, minute: 30, second: 0).daylight, 0, accuracy: 1e-9)
    }

    func testTwilightPeaksAtDawnAndDusk() {
        XCTAssertEqual(WorldTime(hour: 6, minute: 0, second: 0).twilight, 1, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 18, minute: 0, second: 0).twilight, 1, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 12, minute: 0, second: 0).twilight, 0, accuracy: 1e-9)
        XCTAssertEqual(WorldTime(hour: 0, minute: 0, second: 0).twilight, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(WorldTime(hour: 17, minute: 30, second: 0).twilight, 0)
    }

    func testClockLabelFollowsLocaleHourCycle() {
        let t = WorldTime(hour: 14, minute: 5, second: 0)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(t.clockLabel(calendar: cal, locale: Locale(identifier: "en_GB")), "14:05")
        XCTAssertTrue(t.clockLabel(calendar: cal, locale: Locale(identifier: "en_US")).hasPrefix("2:05"))
    }
}

final class WorldTimeScheduleTests: XCTestCase {
    private let schedule = SolarSchedule(sunriseMinutes: 7 * 60, sunsetMinutes: 19 * 60)

    private func at(_ h: Int, _ m: Int = 0, _ s: Int = 0) -> WorldTime {
        WorldTime(hour: h, minute: m, second: s, schedule: schedule)
    }

    func testDaytimeBoundariesFollowSchedule() {
        XCTAssertFalse(at(6, 59).isDaytime)
        XCTAssertTrue(at(7, 0).isDaytime)
        XCTAssertTrue(at(18, 59).isDaytime)
        XCTAssertFalse(at(19, 0).isDaytime)
    }

    func testDayProgressSpansSunriseToSunset() {
        XCTAssertEqual(at(7).dayProgress ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(at(13).dayProgress ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(at(18, 59, 59).dayProgress ?? -1, 1, accuracy: 0.01)
        XCTAssertNil(at(6, 30).dayProgress)
    }

    func testNightProgressSpansSunsetToSunrise() {
        XCTAssertEqual(at(19).nightProgress ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(at(1).nightProgress ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(at(6, 59, 59).nightProgress ?? -1, 1, accuracy: 0.01)
        XCTAssertNil(at(12).nightProgress)
    }

    func testUnequalDayAndNightLengths() {
        let short = SolarSchedule(sunriseMinutes: 8 * 60, sunsetMinutes: 16 * 60)
        let t = WorldTime(hour: 0, minute: 0, second: 0, schedule: short)
        // 8 hours after sunset out of a 16-hour night.
        XCTAssertEqual(t.nightProgress ?? -1, 0.5, accuracy: 1e-9)
        let noon = WorldTime(hour: 12, minute: 0, second: 0, schedule: short)
        XCTAssertEqual(noon.dayProgress ?? -1, 0.5, accuracy: 1e-9)
    }

    func testDaylightRampsCentreOnSchedule() {
        XCTAssertEqual(at(6, 30).daylight, 0, accuracy: 1e-9)
        XCTAssertEqual(at(7).daylight, 0.5, accuracy: 1e-9)
        XCTAssertEqual(at(7, 30).daylight, 1, accuracy: 1e-9)
        XCTAssertEqual(at(19).daylight, 0.5, accuracy: 1e-9)
        XCTAssertEqual(at(19, 30).daylight, 0, accuracy: 1e-9)
    }

    func testTwilightPeaksOnSchedule() {
        XCTAssertEqual(at(7).twilight, 1, accuracy: 1e-9)
        XCTAssertEqual(at(19).twilight, 1, accuracy: 1e-9)
        XCTAssertEqual(at(5, 30).twilight, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(at(6).twilight, 0)
        XCTAssertEqual(at(13).twilight, 0, accuracy: 1e-9)
    }

    func testDefaultScheduleIsStylized() {
        XCTAssertEqual(WorldTime(hour: 1, minute: 2, second: 3).schedule, .stylized)
        XCTAssertEqual(WorldTime(from: Date()).schedule, .stylized)
    }
}
