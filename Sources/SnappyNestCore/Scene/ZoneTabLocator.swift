import Foundation

/// Looks up the reference coordinates of an IANA time zone from the tz
/// database's `zone.tab`, which macOS ships at `/usr/share/zoneinfo/zone.tab`.
/// Each row is `CC<TAB>±DDMM[SS]±DDDMM[SS]<TAB>Area/City[<TAB>comment]`; the
/// coordinates are the zone's principal city, so they locate the user only to
/// within the zone (exact for small zones such as `Asia/Singapore`, tens of
/// minutes of solar time off at the edges of `America/Chicago`).
///
/// Fixed-offset identifiers (`GMT+8`, `UTC`, `Etc/GMT-3`) have no row and
/// resolve to nil, which callers treat as "no location".
public enum ZoneTabLocator {
    public struct Coordinates: Equatable, Hashable, Sendable {
        public let latitude: Double
        public let longitude: Double
        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public static let defaultURL = URL(fileURLWithPath: "/usr/share/zoneinfo/zone.tab")

    /// Pure parser: identifier → coordinates. Comment lines and malformed
    /// rows are skipped.
    public static func parse(_ text: String) -> [String: Coordinates] {
        var result: [String: Coordinates] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3, let coords = parseISO6709(String(fields[1])) else { continue }
            result[String(fields[2])] = coords
        }
        return result
    }

    /// `±DDMM[SS]±DDDMM[SS]` → decimal degrees.
    static func parseISO6709(_ s: String) -> Coordinates? {
        let chars = Array(s)
        guard let first = chars.first, first == "+" || first == "-" else { return nil }
        guard let split = chars.indices.dropFirst().first(where: { chars[$0] == "+" || chars[$0] == "-" })
        else { return nil }
        let latPart = String(chars[..<split])
        let lonPart = String(chars[split...])
        guard let lat = sexagesimal(latPart, degreeDigits: 2), let lon = sexagesimal(lonPart, degreeDigits: 3)
        else { return nil }
        return Coordinates(latitude: lat, longitude: lon)
    }

    private static func sexagesimal(_ s: String, degreeDigits: Int) -> Double? {
        let sign: Double = s.hasPrefix("-") ? -1 : 1
        let digits = String(s.dropFirst())
        guard digits.allSatisfy(\.isNumber) else { return nil }
        let expected = [degreeDigits + 2, degreeDigits + 4]
        guard expected.contains(digits.count) else { return nil }
        let d = Double(digits.prefix(degreeDigits))!
        let m = Double(digits.dropFirst(degreeDigits).prefix(2))!
        let sec = digits.count == degreeDigits + 4 ? Double(digits.suffix(2))! : 0
        return sign * (d + m / 60 + sec / 3600)
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var tables: [URL: [String: Coordinates]] = [:]

    /// Reads and caches `zoneTab` on first use (one file read per URL for the
    /// process lifetime), then looks up `identifier`.
    public static func coordinates(for identifier: String, zoneTab: URL = defaultURL) -> Coordinates? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if tables[zoneTab] == nil {
            let text = (try? String(contentsOf: zoneTab, encoding: .utf8)) ?? ""
            tables[zoneTab] = parse(text)
        }
        return tables[zoneTab]?[identifier]
    }
}
