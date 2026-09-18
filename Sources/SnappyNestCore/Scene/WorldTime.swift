import Foundation

/// Local wall-clock position in a 24-hour day, expressed as a fraction on
/// `[0, 1)` where `0.0` is 00:00, `0.25` is 06:00, `0.5` is 12:00, and `0.75`
/// is 18:00. DST-safe: computed from the local calendar's hour/minute/second
/// components rather than seconds-since-epoch, so a repeated wall-clock hour
/// (fall-back) genuinely repeats its position and a skipped hour (spring-forward)
/// is genuinely skipped.
public struct WorldTime: Equatable, Hashable, Sendable {
    public let hour: Int
    public let minute: Int
    public let second: Int

    public init(hour: Int, minute: Int, second: Int) {
        precondition((0...23).contains(hour),   "hour out of range: \(hour)")
        precondition((0...59).contains(minute), "minute out of range: \(minute)")
        precondition((0...60).contains(second), "second out of range: \(second)")
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    public init(from date: Date, in calendar: Calendar = .current) {
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        self.init(hour: comps.hour ?? 0, minute: comps.minute ?? 0, second: comps.second ?? 0)
    }

    /// Fraction of the 24-hour day. Clamped to `[0, 1)`.
    public var fraction: Double {
        let total = Double(hour) * 3600 + Double(minute) * 60 + Double(min(second, 59))
        return total / 86_400.0
    }

    public var isDaytime: Bool {
        // Stylized 06:00 – 18:00.
        (6...17).contains(hour)
    }

    /// Progress across the sun's arc (0 at sunrise 06:00, 1 at sunset 18:00).
    /// Returns nil outside daytime.
    public var dayProgress: Double? {
        guard isDaytime else { return nil }
        let minutesFromSix = Double((hour - 6) * 60 + minute) + Double(second) / 60.0
        return min(1.0, max(0.0, minutesFromSix / (12 * 60)))
    }

    /// Minutes since midnight, fractional.
    public var minutesOfDay: Double {
        Double(hour) * 60 + Double(minute) + Double(min(second, 59)) / 60.0
    }

    /// Stylized daylight amount on `[0, 1]`: 0 at night, 1 in full day, with
    /// smooth 60-minute ramps centered on 06:00 and 18:00.
    public var daylight: Double {
        let m = minutesOfDay
        let rise = Self.smoothstep((m - (6 * 60 - 30)) / 60)
        let set = 1 - Self.smoothstep((m - (18 * 60 - 30)) / 60)
        return min(rise, set)
    }

    /// Warm horizon glow on `[0, 1]`, peaking at 06:00 and 18:00 and fading
    /// to zero 75 minutes either side.
    public var twilight: Double {
        let m = minutesOfDay
        let width = 75.0
        let dawn = max(0, 1 - abs(m - 6 * 60) / width)
        let dusk = max(0, 1 - abs(m - 18 * 60) / width)
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

    /// Progress across the moon's arc (0 at moonrise 18:00, 1 at moonset next 06:00).
    /// Returns nil during daytime.
    public var nightProgress: Double? {
        guard !isDaytime else { return nil }
        let offsetHour = ((hour - 18 + 24) % 24)
        let minutesFromEighteen = Double(offsetHour * 60 + minute) + Double(second) / 60.0
        return min(1.0, max(0.0, minutesFromEighteen / (12 * 60)))
    }
}
