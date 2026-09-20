import Foundation

/// Sunrise and sunset for one civil day, as minutes after local midnight.
///
/// `.stylized` is the fixed 06:00 / 18:00 day the scene used before real
/// timing existed; it remains the default for every `WorldTime` so tests and
/// previews stay deterministic, and the fallback when no location is known.
public struct SolarSchedule: Equatable, Hashable, Sendable {
    public let sunriseMinutes: Double
    public let sunsetMinutes: Double

    public static let stylized = SolarSchedule(sunriseMinutes: 6 * 60, sunsetMinutes: 18 * 60)

    public init(sunriseMinutes: Double, sunsetMinutes: Double) {
        precondition(sunriseMinutes >= 0 && sunriseMinutes < 1440, "sunrise out of range: \(sunriseMinutes)")
        precondition(sunsetMinutes >= 0 && sunsetMinutes < 1440, "sunset out of range: \(sunsetMinutes)")
        precondition(sunriseMinutes < sunsetMinutes, "sunrise must precede sunset")
        self.sunriseMinutes = sunriseMinutes
        self.sunsetMinutes = sunsetMinutes
    }

    public var dayLengthMinutes: Double { sunsetMinutes - sunriseMinutes }
    public var nightLengthMinutes: Double { 1440 - dayLengthMinutes }
    public var solarNoonMinutes: Double { (sunriseMinutes + sunsetMinutes) / 2 }

    /// NOAA sunrise/sunset (zenith 90.833°, i.e. refraction and the solar
    /// disc included) for the civil day containing `date` in `calendar`.
    /// The calendar's time zone supplies the UTC offset for that day, so DST
    /// is honoured. Returns nil on polar day or polar night, and nil when the
    /// resulting times would not fit inside one local day (only possible at
    /// extreme longitudes for a zone).
    public static func solar(
        latitude: Double,
        longitude: Double,
        date: Date,
        calendar: Calendar
    ) -> SolarSchedule? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day,
              let localMidnight = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }

        let offsetMinutes = Double(calendar.timeZone.secondsFromGMT(for: localMidnight)) / 60
        let jd = julianDay(year: year, month: month, day: day)
        let t = (jd - 2_451_545.0) / 36_525.0  // Julian centuries since J2000

        let declination = solarDeclination(t)
        let eot = equationOfTime(t)  // minutes

        let latR = latitude * .pi / 180
        let cosH = (cos(90.833 * .pi / 180) / (cos(latR) * cos(declination))) - tan(latR) * tan(declination)
        guard cosH > -1, cosH < 1 else { return nil }
        let hourAngle = acos(cosH) * 180 / .pi  // degrees

        // Minutes after local midnight (NOAA: 720 - 4*(lon + H) - eot + tz).
        let rise = 720 - 4 * (longitude + hourAngle) - eot + offsetMinutes
        let set = 720 - 4 * (longitude - hourAngle) - eot + offsetMinutes
        guard rise >= 0, set < 1440, rise < set else { return nil }
        return SolarSchedule(sunriseMinutes: rise, sunsetMinutes: set)
    }

    // MARK: - NOAA helpers

    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = year, m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(Double(y) / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + Double(day) + b - 1524.5
    }

    private static func deg(_ x: Double) -> Double { x * .pi / 180 }

    private static func geomMeanLongitude(_ t: Double) -> Double {
        var l = 280.46646 + t * (36000.76983 + t * 0.0003032)
        l = l.truncatingRemainder(dividingBy: 360)
        return l < 0 ? l + 360 : l
    }

    private static func geomMeanAnomaly(_ t: Double) -> Double {
        357.52911 + t * (35999.05029 - 0.0001537 * t)
    }

    private static func eccentricity(_ t: Double) -> Double {
        0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    }

    private static func obliquityCorrection(_ t: Double) -> Double {
        let seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))
        let mean = 23 + (26 + seconds / 60) / 60
        let omega = 125.04 - 1934.136 * t
        return deg(mean + 0.00256 * cos(deg(omega)))
    }

    /// Radians.
    private static func solarDeclination(_ t: Double) -> Double {
        let m = geomMeanAnomaly(t)
        let c = sin(deg(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(deg(2 * m)) * (0.019993 - 0.000101 * t)
            + sin(deg(3 * m)) * 0.000289
        let trueLong = geomMeanLongitude(t) + c
        let omega = 125.04 - 1934.136 * t
        let apparent = trueLong - 0.00569 - 0.00478 * sin(deg(omega))
        return asin(sin(obliquityCorrection(t)) * sin(deg(apparent)))
    }

    /// Minutes.
    private static func equationOfTime(_ t: Double) -> Double {
        let eps = obliquityCorrection(t)
        let l0 = deg(geomMeanLongitude(t))
        let e = eccentricity(t)
        let m = deg(geomMeanAnomaly(t))
        var y = tan(eps / 2)
        y *= y
        let e1 = y * sin(2 * l0)
        let e2 = -2 * e * sin(m)
        let e3 = 4 * e * y * sin(m) * cos(2 * l0)
        let e4 = -0.5 * y * y * sin(4 * l0)
        let e5 = -1.25 * e * e * sin(2 * m)
        return (e1 + e2 + e3 + e4 + e5) * 180 / .pi * 4
    }
}
