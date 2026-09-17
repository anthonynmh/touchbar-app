import Foundation
import IOKit
import IOKit.ps

/// Battery snapshot from IOPS. Falls back to unavailable on Macs without a
/// battery (desktops), reports `isPresent = false`.
public final class RealBatteryProvider: BatteryProvider {
    public private(set) var snapshot: BatterySnapshot = .unavailable

    private var handlers: [(BatterySnapshot) -> Void] = []
    private var runLoopSource: CFRunLoopSource?

    public init() {
        refresh()
        let self_ = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx = ctx else { return }
            let s = Unmanaged<RealBatteryProvider>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { s.refresh() }
        }, self_)?.takeRetainedValue() {
            self.runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    private func refresh() {
        let old = snapshot
        snapshot = Self.readSnapshot()
        if old != snapshot { handlers.forEach { $0(snapshot) } }
    }

    private static func readSnapshot() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .unavailable
        }
        let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for src in list {
            guard let info = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any] else { continue }
            let isPresent = (info[kIOPSIsPresentKey] as? Bool) ?? false
            guard isPresent else { continue }
            let current = (info[kIOPSCurrentCapacityKey] as? Int) ?? 0
            let max = (info[kIOPSMaxCapacityKey] as? Int) ?? 100
            let charging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            let pct = max > 0 ? Double(current) / Double(max) : 0
            return BatterySnapshot(isPresent: true, percentage: pct, isCharging: charging)
        }
        return .unavailable
    }

    public func subscribe(_ handler: @escaping (BatterySnapshot) -> Void) {
        handlers.append(handler)
        handler(snapshot)
    }

    public func unsubscribeAll() { handlers.removeAll() }
}
