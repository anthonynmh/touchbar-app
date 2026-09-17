import CoreGraphics
import Darwin
import Foundation

/// Built-in-display brightness backed by the private DisplayServices
/// framework — the only path that works on Apple Silicon internal panels
/// (older `IODisplayGetFloatParameter(kIODisplayBrightnessKey)` returns
/// bogus values on M1 and later).
///
/// All private-API access is contained in this one file. `dlopen`-loaded;
/// nil symbols degrade to `.unavailable`.
public final class RealBrightnessProvider: BrightnessProvider {
    public private(set) var capability: ProviderCapability
    public private(set) var value: Double = 0

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getFn: GetFn?
    private let setFn: SetFn?
    private let display = CGMainDisplayID()
    private var pollTimer: Timer?
    private var writeInFlightUntil: Date = .distantPast
    private var handlers: [(Double) -> Void] = []

    public init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL),
              let getSym = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSym = dlsym(handle, "DisplayServicesSetBrightness") else {
            self.getFn = nil
            self.setFn = nil
            self.capability = .unavailable(reason: "displayservices_symbols_missing")
            return
        }
        self.getFn = unsafeBitCast(getSym, to: GetFn.self)
        self.setFn = unsafeBitCast(setSym, to: SetFn.self)
        self.capability = .supported
        readOnce()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.readExternalChange()
        }
    }

    private func readOnce() {
        guard let getFn = getFn else { return }
        var out: Float = 0
        if getFn(display, &out) == 0, out.isFinite, out >= 0, out <= 1 {
            value = Double(out)
        }
    }

    private func readExternalChange() {
        guard Date() > writeInFlightUntil else { return }
        let old = value
        readOnce()
        if old != value { notify() }
    }

    public func set(_ newValue: Double) {
        guard case .supported = capability, let setFn = setFn else { return }
        let clamped = min(1.0, max(0.0, newValue))
        writeInFlightUntil = Date().addingTimeInterval(0.2)
        _ = setFn(display, Float(clamped))
        value = clamped
        notify()
    }

    public func subscribe(_ handler: @escaping (Double) -> Void) {
        handlers.append(handler)
        handler(value)
    }

    public func unsubscribeAll() { handlers.removeAll() }

    private func notify() { handlers.forEach { $0(value) } }
}
