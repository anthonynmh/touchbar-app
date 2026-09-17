import AppKit
import Darwin
import SnappyNestCore

/// A Touch Bar presenter is anything that hands our renderer view to the
/// Touch Bar strip. Two concrete implementations:
///
///   AppFrontmostPresenter  — plain public AppKit; strip shows only when
///                             our (accessory) app has key window focus.
///   PersistentPresenter    — private DFRFoundation path; strip stays
///                             visible under other apps. Fails-safe to
///                             AppFrontmostPresenter on any capability
///                             error at startup.
public protocol TouchBarPresenter: AnyObject {
    var isInstalled: Bool { get }
    var rendererView: SceneRenderer { get }
    func install()
    func uninstall()
}

/// App-frontmost fallback. Owns a hidden window whose `touchBar` provides
/// the item; the strip renders while the app is key.
public final class AppFrontmostPresenter: NSObject, TouchBarPresenter, NSTouchBarDelegate {
    public let rendererView: SceneRenderer
    public private(set) var isInstalled = false
    private let itemIdentifier = NSTouchBarItem.Identifier("com.local.snappy-nest.strip")
    private var hostWindow: NSWindow?

    public init(rendererView: SceneRenderer) {
        self.rendererView = rendererView
    }

    public func install() {
        guard !isInstalled else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.alphaValue = 0
        window.orderFrontRegardless()
        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("com.local.snappy-nest.strip")
        bar.defaultItemIdentifiers = [itemIdentifier]
        window.touchBar = bar
        NSApp.touchBar = bar
        hostWindow = window
        isInstalled = true
    }

    public func uninstall() {
        NSApp.touchBar = nil
        hostWindow?.orderOut(nil)
        hostWindow = nil
        isInstalled = false
    }

    public func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == itemIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        rendererView.frame = NSRect(x: 0, y: 0, width: 685, height: 30)
        item.view = rendererView
        return item
    }
}

/// Private-API Control-Strip resident presenter. The item stays visible
/// regardless of which app is frontmost.
public final class PersistentPresenter: NSObject, TouchBarPresenter {
    public let rendererView: SceneRenderer
    public private(set) var isInstalled = false

    private typealias DFRSetStatus_t             = @convention(c) (Int32) -> Void
    private typealias DFRPresence_t              = @convention(c) (CFString, Bool) -> Void

    private let dfrSetStatus: DFRSetStatus_t?
    private let dfrPresence: DFRPresence_t?
    private let stripIdentifier: CFString = "com.local.snappy-nest.strip" as CFString
    private let touchBarItem: NSCustomTouchBarItem

    /// True iff `dlopen` + both symbols resolved.
    public let capabilityReady: Bool

    public init(rendererView: SceneRenderer) {
        self.rendererView = rendererView
        self.touchBarItem = NSCustomTouchBarItem(
            identifier: NSTouchBarItem.Identifier(rawValue: stripIdentifier as String)
        )
        let path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
        if let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL),
           let setSym = dlsym(handle, "DFRSetStatus"),
           let prSym  = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") {
            self.dfrSetStatus = unsafeBitCast(setSym, to: DFRSetStatus_t.self)
            self.dfrPresence  = unsafeBitCast(prSym,  to: DFRPresence_t.self)
            self.capabilityReady = true
        } else {
            self.dfrSetStatus = nil
            self.dfrPresence  = nil
            self.capabilityReady = false
        }
    }

    public func install() {
        guard !isInstalled, capabilityReady,
              let set = dfrSetStatus, let pres = dfrPresence else { return }
        rendererView.frame = NSRect(x: 0, y: 0, width: 685, height: 30)
        touchBarItem.view = rendererView

        let cls: AnyClass = NSTouchBarItem.self
        let selector = NSSelectorFromString("addSystemTrayItem:")
        if (cls as AnyObject).responds(to: selector) {
            _ = (cls as AnyObject).perform(selector, with: touchBarItem)
        }
        pres(stripIdentifier, true)
        set(2)
        isInstalled = true
    }

    public func uninstall() {
        guard isInstalled else { return }
        if let pres = dfrPresence { pres(stripIdentifier, false) }
        if let set  = dfrSetStatus { set(0) }
        // Remove the system tray item too.
        let cls: AnyClass = NSTouchBarItem.self
        let selector = NSSelectorFromString("removeSystemTrayItem:")
        if (cls as AnyObject).responds(to: selector) {
            _ = (cls as AnyObject).perform(selector, with: touchBarItem)
        }
        isInstalled = false
    }
}
