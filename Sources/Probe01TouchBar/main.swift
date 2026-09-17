// Probe 01 — custom NSTouchBar rendering + measured bounds.
//
// Runs as a regular (dock-visible) menu-bar app with a tiny key window so the
// responder chain resolves our NSTouchBar. When the custom item's view moves
// into the Touch Bar window, we log `view.bounds` and the backing scale, then
// exit after 3 seconds so the probe can be scripted from install.sh / CI.
//
// Success criterion: a line of the form
//   TOUCHBAR_BOUNDS ok width=<pt> height=<pt> backingScale=<x>
// is emitted, and the strip visibly shows the red panel.

import AppKit

let itemIdentifier = NSTouchBarItem.Identifier("com.local.snappy-nest.probe01.strip")

final class ProbeView: NSView {
    private var didReport = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemRed.cgColor
        layer?.magnificationFilter = .nearest
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportBoundsIfReady()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        reportBoundsIfReady()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        reportBoundsIfReady()
    }

    override func layout() {
        super.layout()
        reportBoundsIfReady()
    }

    private func reportBoundsIfReady() {
        guard !didReport, let window = window else { return }
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }
        let scale = window.backingScaleFactor
        NSLog("TOUCHBAR_BOUNDS ok width=%.2f height=%.2f backingScale=%.2f", b.width, b.height, scale)
        didReport = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            NSLog("TOUCHBAR_BOUNDS exit")
            NSApp.terminate(nil)
        }
    }
}

final class Delegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate, NSWindowDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let styleMask: NSWindow.StyleMask = [.titled, .closable]
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 120),
                          styleMask: styleMask,
                          backing: .buffered,
                          defer: false)
        window.title = "Snappy Nest — Probe 01"
        window.delegate = self
        window.isReleasedWhenClosed = false

        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("com.local.snappy-nest.probe01")
        bar.defaultItemIdentifiers = [itemIdentifier]
        window.touchBar = bar

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Fallback: if we never got a bounds report (no Touch Bar on this device),
        // exit after 6 seconds with a NO_TOUCHBAR line so the caller can record it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            NSLog("TOUCHBAR_BOUNDS fail no_report_within_6s")
            NSApp.terminate(nil)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == itemIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = ProbeView(frame: NSRect(x: 0, y: 0, width: 400, height: 30))
        item.customizationLabel = "Snappy Nest Probe 01"
        return item
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate()
app.delegate = delegate
app.run()
