import AppKit
import Darwin

public struct TouchBarPresentationGeometry: Equatable, Sendable {
    public let width: CGFloat
    public let height: CGFloat
    public let backingScale: CGFloat

    public init(width: CGFloat, height: CGFloat, backingScale: CGFloat) {
        self.width = width
        self.height = height
        self.backingScale = backingScale
    }
}

public enum TouchBarPresentationState: Equatable, Sendable {
    case idle
    case installing
    case visible(TouchBarPresentationGeometry)
    case fallback(TouchBarPresentationGeometry)
    case hidden
    case failed(reason: String)

    public var isPresentationRequested: Bool {
        switch self {
        case .installing, .visible, .fallback:
            return true
        case .idle, .hidden, .failed:
            return false
        }
    }
}

/// Presents the renderer on the physical Touch Bar and reports only verified
/// visibility. Selector calls alone are deliberately not considered success.
public protocol TouchBarPresenter: AnyObject {
    var state: TouchBarPresentationState { get }
    var stateDidChange: ((TouchBarPresentationState) -> Void)? { get set }
    var rendererView: SceneRenderer { get }
    func install()
    func uninstall()
}

public extension TouchBarPresenter {
    var isInstalled: Bool { state.isPresentationRequested }
}

protocol TouchBarAttachmentObservation: AnyObject {
    func cancel()
}

enum TouchBarAttachmentResult {
    case attached(TouchBarPresentationGeometry)
    case timedOut
}

protocol TouchBarAttachmentMonitoring: AnyObject {
    func start(
        observing view: NSView,
        timeout: TimeInterval,
        completion: @escaping (TouchBarAttachmentResult) -> Void
    ) -> TouchBarAttachmentObservation
}

private final class TimerAttachmentObservation: TouchBarAttachmentObservation {
    var timer: Timer?

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit { cancel() }
}

final class SystemTouchBarAttachmentMonitor: TouchBarAttachmentMonitoring {
    func start(
        observing view: NSView,
        timeout: TimeInterval,
        completion: @escaping (TouchBarAttachmentResult) -> Void
    ) -> TouchBarAttachmentObservation {
        precondition(Thread.isMainThread)

        let observation = TimerAttachmentObservation()
        let deadline = Date().addingTimeInterval(timeout)

        func inspect() -> Bool {
            guard let window = view.window,
                  view.bounds.width > 0, view.bounds.height > 0,
                  window.frame.width > 0, window.frame.height > 0 else {
                return false
            }
            observation.cancel()
            completion(.attached(TouchBarPresentationGeometry(
                width: view.bounds.width,
                height: view.bounds.height,
                backingScale: window.backingScaleFactor
            )))
            return true
        }

        if !inspect() {
            observation.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if inspect() { return }
                if Date() >= deadline {
                    observation.cancel()
                    completion(.timedOut)
                }
            }
        }
        return observation
    }
}

private final class RendererTouchBarDelegate: NSObject, NSTouchBarDelegate {
    let item: NSCustomTouchBarItem

    init(item: NSCustomTouchBarItem) {
        self.item = item
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        identifier == item.identifier ? item : nil
    }
}

private final class TouchBarHostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Public AppKit fallback. A key-capable host window establishes a real
/// responder chain; the accessory app is activated whenever presentation is
/// requested.
public final class AppFrontmostPresenter: NSObject, TouchBarPresenter {
    public let rendererView: SceneRenderer
    public private(set) var state: TouchBarPresentationState = .idle
    public var stateDidChange: ((TouchBarPresentationState) -> Void)?

    private let itemIdentifier = NSTouchBarItem.Identifier("com.local.snappy-nest.fallback.renderer")
    private let attachmentMonitor: TouchBarAttachmentMonitoring
    private let attachmentTimeout: TimeInterval

    private var hostWindow: TouchBarHostWindow?
    private var touchBar: NSTouchBar?
    private var rendererItem: NSCustomTouchBarItem?
    private var touchBarDelegate: RendererTouchBarDelegate?
    private var attachmentObservation: TouchBarAttachmentObservation?
    private var generation = 0

    public convenience init(rendererView: SceneRenderer) {
        self.init(
            rendererView: rendererView,
            attachmentMonitor: SystemTouchBarAttachmentMonitor(),
            attachmentTimeout: 12
        )
    }

    init(
        rendererView: SceneRenderer,
        attachmentMonitor: TouchBarAttachmentMonitoring,
        attachmentTimeout: TimeInterval
    ) {
        self.rendererView = rendererView
        self.attachmentMonitor = attachmentMonitor
        self.attachmentTimeout = attachmentTimeout
    }

    public func install() {
        precondition(Thread.isMainThread)
        guard !state.isPresentationRequested else { return }

        generation += 1
        let installGeneration = generation
        setState(.installing)

        rendererView.frame = NSRect(x: 0, y: 0, width: 685, height: 30)
        let item = NSCustomTouchBarItem(identifier: itemIdentifier)
        item.view = rendererView
        item.customizationLabel = "Snappy Nest"

        let delegate = RendererTouchBarDelegate(item: item)
        let bar = NSTouchBar()
        bar.delegate = delegate
        bar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("com.local.snappy-nest.fallback")
        bar.defaultItemIdentifiers = [itemIdentifier]
        bar.principalItemIdentifier = itemIdentifier

        let window = TouchBarHostWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.alphaValue = 0
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        rendererItem = item
        touchBarDelegate = delegate
        touchBar = bar
        hostWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.touchBar = bar
        NSApp.touchBar = bar

        attachmentObservation = attachmentMonitor.start(
            observing: rendererView,
            timeout: attachmentTimeout
        ) { [weak self] result in
            guard let self, self.generation == installGeneration,
                  self.state.isPresentationRequested else { return }
            self.attachmentObservation = nil
            switch result {
            case let .attached(geometry):
                NSLog(
                    "[SnappyNest] presenter=fallback attached width=%.1f height=%.1f backingScale=%.2f",
                    geometry.width, geometry.height, geometry.backingScale
                )
                self.setState(.fallback(geometry))
            case .timedOut:
                self.tearDown()
                self.setState(.failed(reason: "app-frontmost renderer attachment timed out"))
            }
        }
    }

    public func uninstall() {
        precondition(Thread.isMainThread)
        generation += 1
        tearDown()
        setState(.hidden)
    }

    private func tearDown() {
        attachmentObservation?.cancel()
        attachmentObservation = nil
        if let touchBar, NSApp.touchBar === touchBar { NSApp.touchBar = nil }
        hostWindow?.touchBar = nil
        hostWindow?.orderOut(nil)
        rendererView.removeFromSuperview()
        rendererItem?.view = NSView(frame: .zero)
        rendererItem = nil
        touchBarDelegate = nil
        touchBar = nil
        hostWindow = nil
    }

    private func setState(_ newState: TouchBarPresentationState) {
        state = newState
        stateDidChange?(newState)
    }
}

protocol PersistentTouchBarRuntime: AnyObject {
    var capabilityFailureReason: String? { get }
    func addSystemTrayItem(_ item: NSCustomTouchBarItem) -> Bool
    func setControlStripPresence(identifier: String, present: Bool)
    func presentSystemModalTouchBar(_ touchBar: NSTouchBar, trayIdentifier: String) -> Bool
    func dismissSystemModalTouchBar(_ touchBar: NSTouchBar)
    func removeSystemTrayItem(_ item: NSCustomTouchBarItem)
    func setPresentationStatus(_ status: Int32)
}

final class SystemPersistentTouchBarRuntime: PersistentTouchBarRuntime {
    private typealias DFRSetStatus = @convention(c) (Int32) -> Void
    private typealias DFRPresence = @convention(c) (CFString, Bool) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let dfrSetStatus: DFRSetStatus?
    private let dfrPresence: DFRPresence?

    private let addSelector = NSSelectorFromString("addSystemTrayItem:")
    private let removeSelector = NSSelectorFromString("removeSystemTrayItem:")
    private let presentSelector = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    private let dismissSelector = NSSelectorFromString("dismissSystemModalTouchBar:")

    init() {
        let path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
        handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        if let handle,
           let setSymbol = dlsym(handle, "DFRSetStatus"),
           let presenceSymbol = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") {
            dfrSetStatus = unsafeBitCast(setSymbol, to: DFRSetStatus.self)
            dfrPresence = unsafeBitCast(presenceSymbol, to: DFRPresence.self)
        } else {
            dfrSetStatus = nil
            dfrPresence = nil
        }
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    var capabilityFailureReason: String? {
        guard handle != nil, dfrSetStatus != nil, dfrPresence != nil else {
            return "DFRFoundation symbols unavailable"
        }
        let itemClass: AnyClass = NSTouchBarItem.self
        guard (itemClass as AnyObject).responds(to: addSelector) else {
            return "addSystemTrayItem: selector unavailable"
        }
        guard (itemClass as AnyObject).responds(to: removeSelector) else {
            return "removeSystemTrayItem: selector unavailable"
        }
        let barClass: AnyClass = NSTouchBar.self
        guard (barClass as AnyObject).responds(to: presentSelector) else {
            return "presentSystemModalTouchBar:systemTrayItemIdentifier: selector unavailable"
        }
        guard (barClass as AnyObject).responds(to: dismissSelector) else {
            return "dismissSystemModalTouchBar: selector unavailable"
        }
        return nil
    }

    func addSystemTrayItem(_ item: NSCustomTouchBarItem) -> Bool {
        let itemClass: AnyClass = NSTouchBarItem.self
        guard (itemClass as AnyObject).responds(to: addSelector) else { return false }
        _ = (itemClass as AnyObject).perform(addSelector, with: item)
        return true
    }

    func setControlStripPresence(identifier: String, present: Bool) {
        dfrPresence?(identifier as CFString, present)
    }

    func presentSystemModalTouchBar(_ touchBar: NSTouchBar, trayIdentifier: String) -> Bool {
        let barClass: AnyClass = NSTouchBar.self
        guard (barClass as AnyObject).responds(to: presentSelector) else { return false }
        _ = (barClass as AnyObject).perform(
            presentSelector,
            with: touchBar,
            with: trayIdentifier as NSString
        )
        return true
    }

    func dismissSystemModalTouchBar(_ touchBar: NSTouchBar) {
        let barClass: AnyClass = NSTouchBar.self
        guard (barClass as AnyObject).responds(to: dismissSelector) else { return }
        _ = (barClass as AnyObject).perform(dismissSelector, with: touchBar)
    }

    func removeSystemTrayItem(_ item: NSCustomTouchBarItem) {
        let itemClass: AnyClass = NSTouchBarItem.self
        guard (itemClass as AnyObject).responds(to: removeSelector) else { return }
        _ = (itemClass as AnyObject).perform(removeSelector, with: item)
    }

    func setPresentationStatus(_ status: Int32) {
        dfrSetStatus?(status)
    }
}

/// Persistent presenter. The Control Strip item is only a small retained
/// anchor; the full-width renderer lives in a separate system-modal bar.
public final class PersistentPresenter: NSObject, TouchBarPresenter {
    public let rendererView: SceneRenderer
    public private(set) var state: TouchBarPresentationState = .idle
    public var stateDidChange: ((TouchBarPresentationState) -> Void)?

    public var capabilityReady: Bool { runtime.capabilityFailureReason == nil }

    private let runtime: PersistentTouchBarRuntime
    private let attachmentMonitor: TouchBarAttachmentMonitoring
    private let attachmentTimeout: TimeInterval
    private let fallbackFactory: () -> TouchBarPresenter

    private let trayIdentifier = "com.local.snappy-nest.tray"
    private let rendererIdentifier = NSTouchBarItem.Identifier("com.local.snappy-nest.renderer")

    private var trayItem: NSCustomTouchBarItem?
    private var modalTouchBar: NSTouchBar?
    private var rendererItem: NSCustomTouchBarItem?
    private var touchBarDelegate: RendererTouchBarDelegate?
    private var fallbackPresenter: TouchBarPresenter?
    private var attachmentObservation: TouchBarAttachmentObservation?

    private var trayRegistered = false
    private var presenceEnabled = false
    private var modalPresented = false
    private var statusForced = false
    private var generation = 0

    public convenience init(rendererView: SceneRenderer) {
        self.init(
            rendererView: rendererView,
            runtime: SystemPersistentTouchBarRuntime(),
            attachmentMonitor: SystemTouchBarAttachmentMonitor(),
            attachmentTimeout: 12,
            fallbackFactory: nil
        )
    }

    init(
        rendererView: SceneRenderer,
        runtime: PersistentTouchBarRuntime,
        attachmentMonitor: TouchBarAttachmentMonitoring,
        attachmentTimeout: TimeInterval,
        fallbackFactory: (() -> TouchBarPresenter)?
    ) {
        self.rendererView = rendererView
        self.runtime = runtime
        self.attachmentMonitor = attachmentMonitor
        self.attachmentTimeout = attachmentTimeout
        self.fallbackFactory = fallbackFactory ?? {
            AppFrontmostPresenter(rendererView: rendererView)
        }
    }

    public func install() {
        precondition(Thread.isMainThread)
        guard !state.isPresentationRequested else { return }

        generation += 1
        let installGeneration = generation
        setState(.installing)

        if let reason = runtime.capabilityFailureReason {
            beginFallback(after: "persistent presenter unavailable: \(reason)", generation: installGeneration)
            return
        }

        let tray = NSCustomTouchBarItem(
            identifier: NSTouchBarItem.Identifier(trayIdentifier)
        )
        let anchor = NSButton(title: "🐾", target: nil, action: nil)
        anchor.isBordered = false
        anchor.frame = NSRect(x: 0, y: 0, width: 28, height: 30)
        tray.view = anchor
        tray.customizationLabel = "Snappy Nest"

        rendererView.frame = NSRect(x: 0, y: 0, width: 685, height: 30)
        let rendererItem = NSCustomTouchBarItem(identifier: rendererIdentifier)
        rendererItem.view = rendererView
        rendererItem.customizationLabel = "Snappy Nest World"

        let delegate = RendererTouchBarDelegate(item: rendererItem)
        let bar = NSTouchBar()
        bar.delegate = delegate
        bar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("com.local.snappy-nest.modal")
        bar.defaultItemIdentifiers = [rendererIdentifier]
        bar.principalItemIdentifier = rendererIdentifier

        trayItem = tray
        self.rendererItem = rendererItem
        touchBarDelegate = delegate
        modalTouchBar = bar

        guard runtime.addSystemTrayItem(tray) else {
            beginFallback(after: "system tray registration failed", generation: installGeneration)
            return
        }
        trayRegistered = true
        runtime.setControlStripPresence(identifier: trayIdentifier, present: true)
        presenceEnabled = true

        guard runtime.presentSystemModalTouchBar(bar, trayIdentifier: trayIdentifier) else {
            beginFallback(after: "system-modal presentation failed", generation: installGeneration)
            return
        }
        modalPresented = true
        runtime.setPresentationStatus(2)
        statusForced = true

        attachmentObservation = attachmentMonitor.start(
            observing: rendererView,
            timeout: attachmentTimeout
        ) { [weak self] result in
            guard let self, self.generation == installGeneration,
                  self.state.isPresentationRequested else { return }
            self.attachmentObservation = nil
            switch result {
            case let .attached(geometry):
                NSLog(
                    "[SnappyNest] presenter=persistent attached width=%.1f height=%.1f backingScale=%.2f",
                    geometry.width, geometry.height, geometry.backingScale
                )
                self.setState(.visible(geometry))
            case .timedOut:
                self.beginFallback(
                    after: "persistent renderer attachment timed out",
                    generation: installGeneration
                )
            }
        }
    }

    public func uninstall() {
        precondition(Thread.isMainThread)
        generation += 1
        attachmentObservation?.cancel()
        attachmentObservation = nil
        fallbackPresenter?.stateDidChange = nil
        fallbackPresenter?.uninstall()
        fallbackPresenter = nil
        tearDownPersistentPresentation()
        setState(.hidden)
    }

    private func beginFallback(after reason: String, generation installGeneration: Int) {
        guard generation == installGeneration, state.isPresentationRequested else { return }
        NSLog("[SnappyNest] \(reason); selecting app-frontmost fallback")
        attachmentObservation?.cancel()
        attachmentObservation = nil
        tearDownPersistentPresentation()

        let fallback = fallbackFactory()
        fallbackPresenter = fallback
        fallback.stateDidChange = { [weak self, weak fallback] fallbackState in
            guard let self, let fallback,
                  self.generation == installGeneration,
                  self.fallbackPresenter === fallback else { return }
            switch fallbackState {
            case let .visible(geometry), let .fallback(geometry):
                self.setState(.fallback(geometry))
            case let .failed(fallbackReason):
                self.setState(.failed(reason: "\(reason); \(fallbackReason)"))
            case .installing:
                self.setState(.installing)
            case .idle, .hidden:
                break
            }
        }
        fallback.install()
    }

    private func tearDownPersistentPresentation() {
        // Cleanup ordering matters: dismiss the modal UI before removing its
        // Control Strip anchor, then restore the normal system presentation.
        if modalPresented, let modalTouchBar {
            runtime.dismissSystemModalTouchBar(modalTouchBar)
            modalPresented = false
        }
        if presenceEnabled {
            runtime.setControlStripPresence(identifier: trayIdentifier, present: false)
            presenceEnabled = false
        }
        if trayRegistered, let trayItem {
            runtime.removeSystemTrayItem(trayItem)
            trayRegistered = false
        }
        if statusForced {
            runtime.setPresentationStatus(0)
            statusForced = false
        }

        rendererView.removeFromSuperview()
        rendererItem?.view = NSView(frame: .zero)
        rendererItem = nil
        touchBarDelegate = nil
        modalTouchBar = nil
        trayItem = nil
    }

    private func setState(_ newState: TouchBarPresentationState) {
        state = newState
        stateDidChange?(newState)
    }
}
