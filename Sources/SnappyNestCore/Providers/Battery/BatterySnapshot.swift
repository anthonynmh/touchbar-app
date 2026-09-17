import Foundation

public struct BatterySnapshot: Equatable {
    public let isPresent: Bool
    public let percentage: Double?   // 0…1; nil when unavailable
    public let isCharging: Bool

    public init(isPresent: Bool, percentage: Double?, isCharging: Bool) {
        self.isPresent = isPresent
        self.percentage = percentage.map { min(1.0, max(0.0, $0)) }
        self.isCharging = isCharging
    }

    public static let unavailable = BatterySnapshot(isPresent: false, percentage: nil, isCharging: false)
}

public protocol BatteryProvider: AnyObject {
    var snapshot: BatterySnapshot { get }
    func subscribe(_ handler: @escaping (BatterySnapshot) -> Void)
    func unsubscribeAll()
}

public final class FakeBatteryProvider: BatteryProvider {
    public var snapshot: BatterySnapshot {
        didSet {
            guard oldValue != snapshot else { return }
            handlers.forEach { $0(snapshot) }
        }
    }
    private var handlers: [(BatterySnapshot) -> Void] = []

    public init(_ snapshot: BatterySnapshot = BatterySnapshot(isPresent: true, percentage: 0.75, isCharging: false)) {
        self.snapshot = snapshot
    }

    public func subscribe(_ handler: @escaping (BatterySnapshot) -> Void) {
        handlers.append(handler)
        handler(snapshot)
    }

    public func unsubscribeAll() { handlers.removeAll() }
}
