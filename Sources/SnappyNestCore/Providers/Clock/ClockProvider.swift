import Foundation

/// Emits `Date` values as wall-clock time advances or drifts. Real
/// implementations should fire on minute boundaries and on
/// `.NSSystemClockDidChange` / `.NSSystemTimeZoneDidChange`. Tests inject
/// `FakeClockProvider` for full determinism.
public protocol ClockProvider: AnyObject {
    var now: Date { get }
    func subscribe(_ handler: @escaping (Date) -> Void)
    func unsubscribeAll()
}

public final class FakeClockProvider: ClockProvider {
    public private(set) var now: Date
    private var handlers: [(Date) -> Void] = []

    public init(_ date: Date = Date(timeIntervalSince1970: 0)) {
        self.now = date
    }

    public func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        handlers.forEach { $0(now) }
    }

    public func set(_ date: Date) {
        now = date
        handlers.forEach { $0(now) }
    }

    public func subscribe(_ handler: @escaping (Date) -> Void) {
        handlers.append(handler)
        handler(now)
    }

    public func unsubscribeAll() { handlers.removeAll() }
}
