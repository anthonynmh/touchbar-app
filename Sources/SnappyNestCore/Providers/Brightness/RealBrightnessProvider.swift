import CoreGraphics
import Darwin
import Foundation

/// The DisplayServices surface used by `RealBrightnessProvider`. Tests inject
/// this bridge so they never modify the machine's actual display brightness.
internal protocol BrightnessBridge: AnyObject {
    func getBrightness() -> (status: Int32, value: Float)
    func setBrightness(_ value: Float) -> Int32
}

private final class SystemBrightnessBridge: BrightnessBridge {
    private typealias GetFunction = @convention(c)
        (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c)
        (CGDirectDisplayID, Float) -> Int32

    private let handle: UnsafeMutableRawPointer
    private let getFunction: GetFunction
    private let setFunction: SetFunction
    private let display = CGMainDisplayID()

    init?() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSymbol = dlsym(handle, "DisplayServicesSetBrightness") else {
            dlclose(handle)
            return nil
        }
        self.handle = handle
        getFunction = unsafeBitCast(getSymbol, to: GetFunction.self)
        setFunction = unsafeBitCast(setSymbol, to: SetFunction.self)
    }

    func getBrightness() -> (status: Int32, value: Float) {
        var value: Float = 0
        return (getFunction(display, &value), value)
    }

    func setBrightness(_ value: Float) -> Int32 {
        setFunction(display, value)
    }

    deinit { dlclose(handle) }
}

/// Built-in-display brightness backed by the private DisplayServices
/// framework — the only path that works on Apple Silicon internal panels.
/// Writes are transactional: setter status and readback are checked, and a
/// failed or mismatched write restores and verifies the captured value.
public final class RealBrightnessProvider: BrightnessProvider {
    public private(set) var capability: ProviderCapability
    public private(set) var value: Double = 0

    private let bridge: BrightnessBridge?
    private var pollTimer: Timer?
    private var writeInFlightUntil: Date = .distantPast
    private var handlers: [(Double) -> Void] = []

    public init() {
        bridge = SystemBrightnessBridge()
        capability = bridge == nil
            ? .unavailable(reason: "displayservices_symbols_missing")
            : .supported
        configure(pollInterval: 1.0)
    }

    internal init(bridge: BrightnessBridge, pollInterval: TimeInterval? = nil) {
        self.bridge = bridge
        capability = .supported
        configure(pollInterval: pollInterval)
    }

    deinit { pollTimer?.invalidate() }

    private func configure(pollInterval: TimeInterval?) {
        guard bridge != nil else { return }
        guard let initial = readValidBrightness() else {
            capability = .unavailable(reason: "brightness_read_failed")
            return
        }
        value = Double(initial)
        if let pollInterval {
            pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) {
                [weak self] _ in self?.readExternalChange()
            }
        }
    }

    private func readValidBrightness() -> Float? {
        guard let bridge else { return nil }
        let result = bridge.getBrightness()
        guard result.status == 0,
              result.value.isFinite,
              result.value >= 0,
              result.value <= 1 else { return nil }
        return result.value
    }

    private func readExternalChange() {
        guard Date() > writeInFlightUntil,
              case .supported = capability else { return }
        guard let actual = readValidBrightness() else {
            capability = .unavailable(reason: "brightness_read_failed")
            notify()
            return
        }
        publish(Double(actual))
    }

    public func set(_ newValue: Double) {
        guard case .supported = capability, let bridge else { return }
        guard let original = readValidBrightness() else {
            capability = .unavailable(reason: "brightness_snapshot_failed")
            notify()
            return
        }

        let target = Float(min(1.0, max(0.0, newValue)))
        writeInFlightUntil = Date().addingTimeInterval(0.2)
        let setStatus = bridge.setBrightness(target)
        let changed = setStatus == 0 ? readValidBrightness() : nil

        if setStatus == 0,
           let changed,
           abs(changed - target) <= 0.001 {
            publish(Double(changed))
            return
        }

        let restoreStatus = bridge.setBrightness(original)
        let restored = readValidBrightness()
        let restoredOK = restoreStatus == 0
            && restored.map { abs($0 - original) <= 0.001 } == true

        if restoredOK, let restored {
            publish(Double(restored), alwaysNotify: true)
        } else {
            capability = .unavailable(reason: "brightness_rollback_failed")
            if let restored { value = Double(restored) }
            notify()
        }
    }

    public func subscribe(_ handler: @escaping (Double) -> Void) {
        handlers.append(handler)
        handler(value)
    }

    public func unsubscribeAll() { handlers.removeAll() }

    private func publish(_ newValue: Double, alwaysNotify: Bool = false) {
        guard alwaysNotify || value != newValue else { return }
        value = newValue
        notify()
    }

    private func notify() { handlers.forEach { $0(value) } }
}
