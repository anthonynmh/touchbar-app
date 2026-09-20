import Foundation

/// Local wall-clock position in a 24-hour day, expressed as a fraction on
/// `[0, 1)` where `0.0` is 00:00, `0.5` is 12:00, and `0.75` is 18:00.
/// DST-safe: computed from the local calendar's hour/minute/second
/// components rather than seconds-since-epoch, so a repeated wall-clock hour
/// (fall-back) genuinely repeats its position and a skipped hour (spring-forward)
/// is genuinely skipped.
///
/// Day and night are defined by `schedule` (sunrise/sunset in minutes of the
/// day). The default `.stylized` schedule is 06:00 / 18:00; the app passes the
/// real schedule resolved by `SolarScheduleCache`.
public struct WorldTime: Equatable, Hashable, Sendable {
    public let hour: Int
    public let minute: Int
    public let second: Int
    public let schedule: SolarSchedule

    public init(hour: Int, minute: Int, second: Int, schedule: SolarSchedule = .stylized) {
        precondition((0...23).contains(hour),   "hour out of range: \(hour)")
        precondition((0...59).contains(minute), "minute out of range: \(minute)")
        precondition((0...60).contains(second), "second out of range: \(second)")
        self.hour = hour
        self.minute = minute
        self.second = second
        self.schedule = schedule
    }

    public init(from date: Date, in calendar: Calendar = .current, schedule: SolarSchedule = .stylized) {
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        self.init(hour: comps.hour ?? 0, minute: comps.minute ?? 0, second: comps.second ?? 0,
                  schedule: schedule)
    }

    /// Fraction of the 24-hour day. Clamped to `[0, 1)`.
    public var fraction: Double {
        let total = Double(hour) * 3600 + Double(minute) * 60 + Double(min(second, 59))
        return total / 86_400.0
    }

    /// True from sunrise (inclusive) to sunset (exclusive).
    public var isDaytime: Bool {
        let m = minutesOfDay
        return m >= schedule.sunriseMinutes && m < schedule.sunsetMinutes
    }

    /// Progress across the sun's arc (0 at sunrise, 1 at sunset).
    /// Returns nil outside daytime.
    public var dayProgress: Double? {
        guard isDaytime else { return nil }
        let sinceRise = minutesOfDay - schedule.sunriseMinutes
        return min(1.0, max(0.0, sinceRise / schedule.dayLengthMinutes))
    }

    /// Minutes since midnight, fractional.
    public var minutesOfDay: Double {
        Double(hour) * 60 + Double(minute) + Double(min(second, 59)) / 60.0
    }

    /// Daylight amount on `[0, 1]`: 0 at night, 1 in full day, with smooth
    /// 60-minute ramps centered on sunrise and sunset.
    public var daylight: Double {
        let m = minutesOfDay
        let rise = Self.smoothstep((m - (schedule.sunriseMinutes - 30)) / 60)
        let set = 1 - Self.smoothstep((m - (schedule.sunsetMinutes - 30)) / 60)
        return min(rise, set)
    }

    /// Warm horizon glow on `[0, 1]`, peaking at sunrise and sunset and
    /// fading to zero 75 minutes either side.
    public var twilight: Double {
        let m = minutesOfDay
        let width = 75.0
        let dawn = max(0, 1 - abs(m - schedule.sunriseMinutes) / width)
        let dusk = max(0, 1 - abs(m - schedule.sunsetMinutes) / width)
        return max(dawn, dusk)
    }

    /// Localized short clock label ("14:05" or "2:05 PM" depending on the
    /// locale's hour cycle).
    public func clockLabel(calendar: Calendar = .current, locale: Locale = .current) -> String {
        var comps = DateComponents()
        comps.year = 2000; comps.month = 1; comps.day = 1
        comps.hour = hour; comps.minute = minute; comps.second = min(second, 59)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("jm")
        let date = calendar.date(from: comps) ?? Date()
        return formatter.string(from: date)
    }

    private static func smoothstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    /// Progress across the moon's arc (0 at sunset, 1 at the next sunrise).
    /// Returns nil during daytime.
    public var nightProgress: Double? {
        guard !isDaytime else { return nil }
        var sinceSet = minutesOfDay - schedule.sunsetMinutes
        if sinceSet < 0 { sinceSet += 1440 }
        return min(1.0, max(0.0, sinceSet / schedule.nightLengthMinutes))
    }
}
