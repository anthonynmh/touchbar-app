import Foundation

/// Resolves the day's `SolarSchedule` for the calendar's time zone and caches
/// it by (zone identifier, day), so per-frame use costs a dictionary lookup.
/// The zone → coordinates lookup is injectable for tests and memoised per
/// identifier. A zone without coordinates, or a polar day/night, yields
/// `.stylized`.
///
/// No notification wiring is needed: `RealClockProvider` already ticks on
/// `NSSystemTimeZoneDidChange`, and the next `schedule(for:)` sees the new
/// identifier in its key.
public final class SolarScheduleCache {
    public struct Resolution: Equatable {
        public let zoneIdentifier: String
        public let coordinates: ZoneTabLocator.Coordinates?
        public let schedule: SolarSchedule
    }

    private struct Key: Hashable {
        let zone: String
        let day: Int
    }

    private let locate: (String) -> ZoneTabLocator.Coordinates?
    private var coordinatesByZone: [String: ZoneTabLocator.Coordinates?] = [:]
    private var schedules: [Key: SolarSchedule] = [:]
    public private(set) var lastResolved: Resolution?

    public init(locate: @escaping (String) -> ZoneTabLocator.Coordinates? = { ZoneTabLocator.coordinates(for: $0) }) {
        self.locate = locate
    }

    public func schedule(for date: Date, calendar: Calendar = .current) -> SolarSchedule {
        let zone = calendar.timeZone.identifier
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let key = Key(zone: zone, day: day)
        if let cached = schedules[key] { return cached }

        let coords: ZoneTabLocator.Coordinates?
        if let known = coordinatesByZone[zone] {
            coords = known
        } else {
            coords = locate(zone)
            coordinatesByZone[zone] = coords
        }
        let schedule = coords.flatMap {
            SolarSchedule.solar(latitude: $0.latitude, longitude: $0.longitude, date: date, calendar: calendar)
        } ?? .stylized

        // Keep the cache bounded: only today (and yesterday around midnight) matter.
        if schedules.count > 4 { schedules.removeAll() }
        schedules[key] = schedule
        lastResolved = Resolution(zoneIdentifier: zone, coordinates: coords, schedule: schedule)
        return schedule
    }
}
