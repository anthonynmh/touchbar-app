import Foundation

/// Wall-clock ClockProvider that fires on the next minute boundary and on
/// system clock / time-zone changes.
public final class RealClockProvider: ClockProvider {
    public var now: Date { Date() }

    private var handlers: [(Date) -> Void] = []
    private var timer: DispatchSourceTimer?

    public init() {
        scheduleTimer()
        NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.fire() }
        NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.fire() }
    }

    private func scheduleTimer() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        // Align the first fire to the next 00-second wall-clock instant.
        let secondsUntilNextMinute = 60 - Int(Date().timeIntervalSinceReferenceDate) % 60
        t.schedule(deadline: .now() + .seconds(secondsUntilNextMinute), repeating: .seconds(60))
        t.setEventHandler { [weak self] in self?.fire() }
        t.resume()
        timer = t
    }

    private func fire() {
        let d = now
        handlers.forEach { $0(d) }
    }

    public func subscribe(_ handler: @escaping (Date) -> Void) {
        handlers.append(handler)
        handler(now)
    }

    public func unsubscribeAll() { handlers.removeAll() }
}
