import CoreGraphics
import XCTest
@testable import SnappyNestCore

final class SceneComposerTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 685, height: 30)

    private func fixedCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func noonUTC() -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 21
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return fixedCalendar().date(from: comps)!
    }

    func testNoonComposesSunAtCenter() {
        let layout = LayoutEngine(bounds: bounds, backingScale: 2.0)
        let composer = SceneComposer(layout: layout)
        let model = composer.compose(
            now: noonUTC(),
            calendar: fixedCalendar(),
            pet: .placeholder,
            battery: BatterySnapshot(isPresent: true, percentage: 0.8, isCharging: false),
            brightness: (0.5, true),
            volume: (0.4, false, true),
            media: .unknown
        )
        XCTAssertEqual(model.celestial.body, .sun)
        XCTAssertEqual(model.celestial.point.x, layout.regions.middle.midX, accuracy: 1e-6)
        XCTAssertNil(model.progressFraction)
    }

    func testMoonStaysInsideTheWorldAllNight() {
        let layout = LayoutEngine(bounds: bounds, backingScale: 2.0)
        let composer = SceneComposer(layout: layout)
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 21
        components.hour = 0
        let midnight = fixedCalendar().date(from: components)!

        let model = composer.compose(
            now: midnight,
            calendar: fixedCalendar(),
            pet: .placeholder,
            battery: BatterySnapshot(isPresent: true, percentage: 0.8, isCharging: false),
            brightness: (0.5, true),
            volume: (0.4, false, true),
            media: .unknown
        )
        let halfWidth = CelestialSolver.bodyHalfWidth
        XCTAssertEqual(model.celestial.point.x, layout.regions.middle.midX, accuracy: 1e-6)

        // Sweep the whole night: the moon (and its glow) never crosses into
        // the battery or control regions.
        for hour in [18, 19, 21, 23, 0, 2, 4, 5] {
            components.hour = hour
            components.minute = hour == 5 ? 59 : 0
            let m = composer.compose(
                now: fixedCalendar().date(from: components)!,
                calendar: fixedCalendar(),
                pet: .placeholder,
                battery: BatterySnapshot(isPresent: true, percentage: 0.8, isCharging: false),
                brightness: (0.5, true),
                volume: (0.4, false, true),
                media: .unknown
            )
            XCTAssertGreaterThanOrEqual(m.celestial.point.x - halfWidth, m.layout.middle.minX - 1e-6)
            XCTAssertLessThanOrEqual(m.celestial.point.x + halfWidth, m.layout.middle.maxX + 1e-6)
        }
    }

    func testProgressTrailWhenPlaying() {
        let composer = SceneComposer(layout: LayoutEngine(bounds: bounds, backingScale: 2.0))
        let now = noonUTC()
        let media = MediaSnapshot(
            identity: "spotify", state: .playing, elapsed: 30, duration: 120,
            elapsedAt: now, rate: 1,
            canPlayPause: true, canReadPosition: true, canReadDuration: true
        )
        let model = composer.compose(
            now: now, calendar: fixedCalendar(), pet: .placeholder,
            battery: BatterySnapshot(isPresent: true, percentage: 0.8, isCharging: false),
            brightness: (0.5, true), volume: (0.4, false, true),
            media: media
        )
        XCTAssertEqual(model.progressFraction ?? -1, 0.25, accuracy: 1e-6)
    }

    func testUnavailableBrightnessShowsGreyed() {
        let composer = SceneComposer(layout: LayoutEngine(bounds: bounds, backingScale: 2.0))
        let model = composer.compose(
            now: noonUTC(), calendar: fixedCalendar(), pet: .placeholder,
            battery: BatterySnapshot(isPresent: true, percentage: 0.8, isCharging: false),
            brightness: (0.0, false), volume: (0.4, false, true),
            media: .unknown
        )
        XCTAssertFalse(model.brightnessAvailable)
    }

    func testBatteryChangeDoesNotAffectCelestial() {
        let composer = SceneComposer(layout: LayoutEngine(bounds: bounds, backingScale: 2.0))
        let a = composer.compose(
            now: noonUTC(), calendar: fixedCalendar(), pet: .placeholder,
            battery: BatterySnapshot(isPresent: true, percentage: 0.02, isCharging: false),
            brightness: (0.5, true), volume: (0.4, false, true), media: .unknown
        )
        let b = composer.compose(
            now: noonUTC(), calendar: fixedCalendar(), pet: .placeholder,
            battery: BatterySnapshot(isPresent: true, percentage: 1.0, isCharging: true),
            brightness: (0.5, true), volume: (0.4, false, true), media: .unknown
        )
        XCTAssertEqual(a.celestial, b.celestial)
        XCTAssertEqual(a.layout, b.layout)
    }
}
