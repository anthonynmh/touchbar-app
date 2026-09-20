import XCTest
@testable import SnappyNestCore

final class SolarScheduleCacheTests: XCTestCase {
    private func calendar(_ tz: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testUnknownZoneFallsBackToStylized() {
        let cache = SolarScheduleCache(locate: { _ in nil })
        let cal = calendar("GMT+8")
        XCTAssertEqual(cache.schedule(for: date(2026, 9, 20, in: cal), calendar: cal), .stylized)
        XCTAssertEqual(cache.lastResolved?.zoneIdentifier, cal.timeZone.identifier)
        XCTAssertNil(cache.lastResolved?.coordinates)
    }

    func testResolvesRealScheduleAndCachesWithinDay() {
        var lookups = 0
        let cache = SolarScheduleCache(locate: { id in
            lookups += 1
            XCTAssertEqual(id, "Asia/Singapore")
            return .init(latitude: 1.2833, longitude: 103.85)
        })
        let cal = calendar("Asia/Singapore")
        let morning = cache.schedule(for: date(2026, 9, 20, hour: 7, in: cal), calendar: cal)
        let evening = cache.schedule(for: date(2026, 9, 20, hour: 22, in: cal), calendar: cal)
        XCTAssertEqual(morning, evening)
        XCTAssertNotEqual(morning, .stylized)
        XCTAssertEqual(morning.sunriseMinutes, 6 * 60 + 55, accuracy: 3)
        XCTAssertEqual(lookups, 1)
    }

    func testNewDayRecomputesWithoutRelookingUpZone() {
        var lookups = 0
        let cache = SolarScheduleCache(locate: { _ in lookups += 1; return .init(latitude: 51.5, longitude: -0.12) })
        let cal = calendar("Europe/London")
        let june = cache.schedule(for: date(2026, 6, 21, in: cal), calendar: cal)
        let december = cache.schedule(for: date(2026, 12, 21, in: cal), calendar: cal)
        XCTAssertGreaterThan(june.dayLengthMinutes, december.dayLengthMinutes + 8 * 60)
        XCTAssertEqual(lookups, 1)
    }

    func testZoneChangeIsKeyed() {
        var ids: [String] = []
        let cache = SolarScheduleCache(locate: { id in ids.append(id); return .init(latitude: 1.2833, longitude: 103.85) })
        let sg = calendar("Asia/Singapore"), la = calendar("America/Los_Angeles")
        let now = date(2026, 9, 20, in: sg)
        _ = cache.schedule(for: now, calendar: sg)
        _ = cache.schedule(for: now, calendar: la)
        XCTAssertEqual(ids, ["Asia/Singapore", "America/Los_Angeles"])
    }
}
