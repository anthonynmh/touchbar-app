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

if let flagIndex = CommandLine.arguments.firstIndex(of: "--snappy-pid-file"),
   CommandLine.arguments.indices.contains(flagIndex + 1) {
    let pidPath = CommandLine.arguments[flagIndex + 1]
    do {
        try "\(ProcessInfo.processInfo.processIdentifier)\n".write(
            toFile: pidPath,
            atomically: true,
            encoding: .utf8
        )
    } catch {
        NSLog("TOUCHBAR_BOUNDS fail reason=pid_file error=%@", error.localizedDescription)
        exit(1)
    }
}

let itemIdentifier = NSTouchBarItem.Identifier("com.local.snappy-nest.probe01.strip")

final class ProbeView: NSView {
    static var didReportGlobal = false
    private var didReport = false
    private var pollTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemRed.cgColor
        layer?.magnificationFilter = .nearest
        NSLog("TOUCHBAR_BOUNDS init frame=%@", NSStringFromRect(frameRect))
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.reportBoundsIfReady()
        }
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NSLog("TOUCHBAR_BOUNDS viewDidMoveToWindow window=%@", window == nil ? "nil" : "present")
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
        let winFrame = window.frame
        let superBounds = superview?.bounds ?? .zero
        NSLog("TOUCHBAR_BOUNDS ok viewW=%.1f viewH=%.1f superW=%.1f superH=%.1f windowW=%.1f windowH=%.1f backingScale=%.2f",
              b.width, b.height,
              superBounds.width, superBounds.height,
              winFrame.width, winFrame.height,
              scale)
        didReport = true
        ProbeView.didReportGlobal = true
        pollTimer?.invalidate()
        pollTimer = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            NSLog("TOUCHBAR_BOUNDS exit")
            NSApp.terminate(nil)
        }
    }
}

final class Delegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate, NSWindowDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("TOUCHBAR_BOUNDS didFinishLaunching activationPolicy=%d isActive=%d",
              NSApp.activationPolicy().rawValue, NSApp.isActive ? 1 : 0)
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

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Set AFTER makeKeyAndOrderFront so the responder chain is established.
        window.touchBar = bar
        NSApp.touchBar = bar
        NSLog("TOUCHBAR_BOUNDS installed touchBar on window+NSApp key=%d",
              window.isKeyWindow ? 1 : 0)

        // Poll the current touch bar visibility after a small delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSLog("TOUCHBAR_BOUNDS after0.5s isVisible=%d",
                  NSTouchBar.isAutomaticCustomizeTouchBarMenuItemEnabled ? 1 : 0)
        }

        // Fallback: if we never got a bounds report (no Touch Bar on this
        // device), exit after 12 seconds with a NO_TOUCHBAR line so the caller
        // can record it. Touch Bar server cold-starts in ~6 s on macOS 26.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
            if !ProbeView.didReportGlobal {
                NSLog("TOUCHBAR_BOUNDS fail no_report_within_12s")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        NSLog("TOUCHBAR_BOUNDS makeItemForIdentifier %@", identifier.rawValue)
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
