import XCTest
@testable import SnappyNestCore

final class SolarScheduleTests: XCTestCase {
    private func calendar(_ tz: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func assertSchedule(
        lat: Double, lon: Double, tz: String, y: Int, m: Int, d: Int,
        sunrise: String, sunset: String, toleranceMinutes: Double = 3,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let cal = calendar(tz)
        guard let s = SolarSchedule.solar(latitude: lat, longitude: lon, date: date(y, m, d, in: cal), calendar: cal) else {
            XCTFail("expected a schedule", file: file, line: line); return
        }
        func minutes(_ hhmm: String) -> Double {
            let p = hhmm.split(separator: ":").map { Double($0)! }
            return p[0] * 60 + p[1]
        }
        XCTAssertEqual(s.sunriseMinutes, minutes(sunrise), accuracy: toleranceMinutes, "sunrise", file: file, line: line)
        XCTAssertEqual(s.sunsetMinutes, minutes(sunset), accuracy: toleranceMinutes, "sunset", file: file, line: line)
    }

    func testSingaporeEquinox() {
        // zone.tab reference for Asia/Singapore is +0117+10351.
        assertSchedule(lat: 1.2833, lon: 103.85, tz: "Asia/Singapore", y: 2026, m: 9, d: 20,
                       sunrise: "06:55", sunset: "19:02")
    }

    func testLondonSummerSolsticeHonoursDST() {
        assertSchedule(lat: 51.5083, lon: -0.1253, tz: "Europe/London", y: 2026, m: 6, d: 21,
                       sunrise: "04:43", sunset: "21:21")
    }

    func testLosAngelesWinterSolstice() {
        assertSchedule(lat: 34.0522, lon: -118.2437, tz: "America/Los_Angeles", y: 2026, m: 12, d: 21,
                       sunrise: "06:55", sunset: "16:48")
    }

    func testPolarDayAndNightReturnNil() {
        let cal = calendar("Europe/Oslo")
        // Tromsø
        XCTAssertNil(SolarSchedule.solar(latitude: 69.65, longitude: 18.96, date: date(2026, 6, 21, in: cal), calendar: cal))
        XCTAssertNil(SolarSchedule.solar(latitude: 69.65, longitude: 18.96, date: date(2026, 12, 21, in: cal), calendar: cal))
    }

    func testEquatorEquinoxDayLength() {
        let cal = calendar("UTC")
        let s = SolarSchedule.solar(latitude: 0, longitude: 0, date: date(2026, 3, 20, in: cal), calendar: cal)!
        XCTAssertEqual(s.dayLengthMinutes, 12 * 60 + 7, accuracy: 3)
        XCTAssertEqual(s.solarNoonMinutes, 12 * 60 + 7, accuracy: 5) // equation of time ≈ -7 min
    }

    func testStylizedDerivedValues() {
        let s = SolarSchedule.stylized
        XCTAssertEqual(s.dayLengthMinutes, 720)
        XCTAssertEqual(s.nightLengthMinutes, 720)
        XCTAssertEqual(s.solarNoonMinutes, 720)
    }

    func testInvalidCoordinatesReturnNil() {
        let cal = calendar("UTC")
        XCTAssertNil(SolarSchedule.solar(latitude: 91, longitude: 0, date: Date(), calendar: cal))
    }
}
