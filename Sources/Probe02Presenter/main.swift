// Probe 02 — full-width persistent system-modal Touch Bar presentation.
//
// This probe deliberately tests two separate claims:
//   1. The renderer actually attaches to a non-zero Touch Bar window and
//      reports its measured bounds/backing scale.
//   2. After the user switches applications, that attached renderer remains
//      present. Merely registering a Control Strip tray item is not success.

import AppKit
import Darwin

typealias DFRSetStatus = @convention(c) (Int32) -> Void
typealias DFRPresence = @convention(c) (CFString, Bool) -> Void

private let trayIdentifier = "com.local.snappy-nest.probe02.tray"
private let rendererIdentifier = NSTouchBarItem.Identifier("com.local.snappy-nest.probe02.renderer")

private func loadDFR() -> UnsafeMutableRawPointer? {
    dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation",
        RTLD_LAZY | RTLD_LOCAL
    )
}

private func symbol<T>(
    _ handle: UnsafeMutableRawPointer,
    _ name: String,
    as type: T.Type
) -> T? {
    guard let address = dlsym(handle, name) else { return nil }
    return unsafeBitCast(address, to: T.self)
}

final class ModalProbeView: NSView {
    var didAttach: ((NSRect, CGFloat) -> Void)?
    private var hasReportedAttachment = false
    private var pollTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.reportAttachmentIfReady()
        }
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportAttachmentIfReady()
    }

    override func layout() {
        super.layout()
        reportAttachmentIfReady()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let panelWidth = bounds.width / 6
        let colors: [NSColor] = [
            .systemIndigo, .systemPurple, .systemPink,
            .systemOrange, .systemYellow, .systemTeal
        ]
        for (index, color) in colors.enumerated() {
            color.setFill()
            NSRect(
                x: CGFloat(index) * panelWidth,
                y: 0,
                width: panelWidth + 1,
                height: bounds.height
            ).fill()
        }

        let message = "🐾  SNAPPY NEST · FULL-WIDTH MODAL PROBE · CMD-TAB NOW  🐾"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -2
        ]
        let size = message.size(withAttributes: attributes)
        message.draw(
            at: NSPoint(
                x: max(4, (bounds.width - size.width) / 2),
                y: max(1, (bounds.height - size.height) / 2)
            ),
            withAttributes: attributes
        )
    }

    private func reportAttachmentIfReady() {
        guard !hasReportedAttachment,
              let window,
              bounds.width > 0, bounds.height > 0,
              window.frame.width > 0, window.frame.height > 0 else { return }
        hasReportedAttachment = true
        pollTimer?.invalidate()
        pollTimer = nil
        didAttach?(bounds, window.backingScaleFactor)
    }
}

final class ProbeDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    private var handle: UnsafeMutableRawPointer?
    private var dfrSetStatus: DFRSetStatus?
    private var dfrPresence: DFRPresence?

    private var trayItem: NSCustomTouchBarItem?
    private var rendererItem: NSCustomTouchBarItem?
    private var modalTouchBar: NSTouchBar?
    private var rendererView: ModalProbeView?

    private var modalPresented = false
    private var trayRegistered = false
    private var presenceEnabled = false
    private var statusForced = false
    private var rendererAttached = false
    private var appSwitchDetected = false
    private var cleanedUp = false
    private var workspaceObserver: NSObjectProtocol?

    private let addSelector = NSSelectorFromString("addSystemTrayItem:")
    private let removeSelector = NSSelectorFromString("removeSystemTrayItem:")
    private let presentSelector = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    private let dismissSelector = NSSelectorFromString("dismissSystemModalTouchBar:")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard prepareRuntime() else {
            NSApp.terminate(nil)
            return
        }

        let tray = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(trayIdentifier))
        let anchor = NSButton(title: "🐾", target: nil, action: nil)
        anchor.isBordered = false
        anchor.frame = NSRect(x: 0, y: 0, width: 28, height: 30)
        tray.view = anchor

        let view = ModalProbeView(frame: NSRect(x: 0, y: 0, width: 685, height: 30))
        view.didAttach = { [weak self] bounds, scale in
            guard let self else { return }
            self.rendererAttached = true
            NSLog(
                "PRESENTER attachment=ok width=%.1f height=%.1f backingScale=%.2f pixels=%.0fx%.0f",
                bounds.width, bounds.height, scale,
                bounds.width * scale, bounds.height * scale
            )
        }
        let item = NSCustomTouchBarItem(identifier: rendererIdentifier)
        item.view = view
        item.customizationLabel = "Snappy Nest Modal Probe"

        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("com.local.snappy-nest.probe02.modal")
        bar.defaultItemIdentifiers = [rendererIdentifier]
        bar.principalItemIdentifier = rendererIdentifier

        trayItem = tray
        rendererItem = item
        modalTouchBar = bar
        rendererView = view

        let itemClass: AnyClass = NSTouchBarItem.self
        _ = (itemClass as AnyObject).perform(addSelector, with: tray)
        trayRegistered = true
        dfrPresence?(trayIdentifier as CFString, true)
        presenceEnabled = true

        let barClass: AnyClass = NSTouchBar.self
        _ = (barClass as AnyObject).perform(
            presentSelector,
            with: bar,
            with: trayIdentifier as NSString
        )
        modalPresented = true
        dfrSetStatus?(2)
        statusForced = true

        NSLog("PRESENTER modal_requested tray_registered=1 status=2")
        NSLog("PRESENTER instruction=Cmd-Tab_to_another_app_to_test_persistence")
        observeApplicationSwitches()

        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, !self.rendererAttached else { return }
            NSLog("PRESENTER attachment=fail reason=no_nonzero_touchbar_window_within_12s")
            self.cleanupAndExit()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak self] in
            guard let self else { return }
            if !self.appSwitchDetected {
                NSLog("PRESENTER persistence=untested reason=no_external_app_switch_detected")
            }
            self.cleanupAndExit()
        }
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        identifier == rendererIdentifier ? rendererItem : nil
    }

    private func prepareRuntime() -> Bool {
        guard let handle = loadDFR() else {
            NSLog("PRESENTER fail reason=dlopen_dfrfoundation")
            return false
        }
        self.handle = handle
        dfrSetStatus = symbol(handle, "DFRSetStatus", as: DFRSetStatus.self)
        dfrPresence = symbol(
            handle,
            "DFRElementSetControlStripPresenceForIdentifier",
            as: DFRPresence.self
        )
        guard dfrSetStatus != nil, dfrPresence != nil else {
            NSLog("PRESENTER fail reason=missing_dfr_symbols")
            return false
        }

        let itemClass: AnyClass = NSTouchBarItem.self
        let barClass: AnyClass = NSTouchBar.self
        guard (itemClass as AnyObject).responds(to: addSelector),
              (itemClass as AnyObject).responds(to: removeSelector),
              (barClass as AnyObject).responds(to: presentSelector),
              (barClass as AnyObject).responds(to: dismissSelector) else {
            NSLog(
                "PRESENTER fail reason=missing_selector add=%d remove=%d present=%d dismiss=%d",
                (itemClass as AnyObject).responds(to: addSelector) ? 1 : 0,
                (itemClass as AnyObject).responds(to: removeSelector) ? 1 : 0,
                (barClass as AnyObject).responds(to: presentSelector) ? 1 : 0,
                (barClass as AnyObject).responds(to: dismissSelector) ? 1 : 0
            )
            return false
        }
        return true
    }

    private func observeApplicationSwitches() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.appSwitchDetected = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard let self else { return }
                let stillAttached = self.rendererView?.window != nil
                    && (self.rendererView?.bounds.width ?? 0) > 0
                    && (self.rendererView?.bounds.height ?? 0) > 0
                NSLog(
                    "PRESENTER persistence=%@ switchedTo=%@ rendererAttached=%d",
                    stillAttached ? "ok" : "fail",
                    app.localizedName ?? app.bundleIdentifier ?? "unknown",
                    stillAttached ? 1 : 0
                )
            }
        }
    }

    private func cleanupAndExit() {
        guard !cleanedUp else { return }
        cleanedUp = true
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }

        let barClass: AnyClass = NSTouchBar.self
        if modalPresented, let modalTouchBar {
            _ = (barClass as AnyObject).perform(dismissSelector, with: modalTouchBar)
            modalPresented = false
        }
        if presenceEnabled {
            dfrPresence?(trayIdentifier as CFString, false)
            presenceEnabled = false
        }
        let itemClass: AnyClass = NSTouchBarItem.self
        if trayRegistered, let trayItem {
            _ = (itemClass as AnyObject).perform(removeSelector, with: trayItem)
            trayRegistered = false
        }
        if statusForced {
            dfrSetStatus?(0)
            statusForced = false
        }
        NSLog("PRESENTER exit cleaned_up=1")
        NSApp.terminate(nil)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = ProbeDelegate()
app.delegate = delegate
app.run()
