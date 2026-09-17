import Foundation

public protocol VolumeProvider: AnyObject {
    var capability: ProviderCapability { get }
    var value: Double { get }        // 0…1
    var isMuted: Bool { get }
    func set(_ newValue: Double)
    func setMuted(_ muted: Bool)
    func subscribe(_ handler: @escaping (Double, Bool) -> Void)
    func unsubscribeAll()
}

public final class FakeVolumeProvider: VolumeProvider {
    public var capability: ProviderCapability
    public private(set) var value: Double {
        didSet { notify(force: oldValue != value) }
    }
    public private(set) var isMuted: Bool {
        didSet { notify(force: oldValue != isMuted) }
    }
    private var handlers: [(Double, Bool) -> Void] = []

    public init(_ value: Double = 0.4, isMuted: Bool = false, capability: ProviderCapability = .supported) {
        self.value = min(1.0, max(0.0, value))
        self.isMuted = isMuted
        self.capability = capability
    }

    public func set(_ newValue: Double) {
        guard case .supported = capability else { return }
        value = min(1.0, max(0.0, newValue))
    }

    public func setMuted(_ muted: Bool) {
        guard case .supported = capability else { return }
        isMuted = muted
    }

    public func externalChange(to newValue: Double, muted: Bool? = nil) {
        value = min(1.0, max(0.0, newValue))
        if let m = muted { isMuted = m }
    }

    public func subscribe(_ handler: @escaping (Double, Bool) -> Void) {
        handlers.append(handler)
        handler(value, isMuted)
    }

    public func unsubscribeAll() { handlers.removeAll() }

    private func notify(force: Bool) {
        guard force else { return }
        handlers.forEach { $0(value, isMuted) }
    }
}
