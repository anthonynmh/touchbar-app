import Foundation

public enum ProviderCapability: Equatable {
    case supported
    case unavailable(reason: String)
}

public protocol BrightnessProvider: AnyObject {
    var capability: ProviderCapability { get }
    var value: Double { get }        // 0…1
    func set(_ newValue: Double)
    func subscribe(_ handler: @escaping (Double) -> Void)
    func unsubscribeAll()
}

public final class FakeBrightnessProvider: BrightnessProvider {
    public var capability: ProviderCapability
    public private(set) var value: Double {
        didSet {
            guard oldValue != value else { return }
            handlers.forEach { $0(value) }
        }
    }
    private var handlers: [(Double) -> Void] = []

    public init(_ value: Double = 0.5, capability: ProviderCapability = .supported) {
        self.value = min(1.0, max(0.0, value))
        self.capability = capability
    }

    public func set(_ newValue: Double) {
        guard case .supported = capability else { return }
        value = min(1.0, max(0.0, newValue))
    }

    public func externalChange(to newValue: Double) {
        value = min(1.0, max(0.0, newValue))
    }

    public func subscribe(_ handler: @escaping (Double) -> Void) {
        handlers.append(handler)
        handler(value)
    }

    public func unsubscribeAll() { handlers.removeAll() }
}
