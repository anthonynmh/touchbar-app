// Probe 02 — persistent presenter via DFRFoundation (private).
//
// Attempts to install a Control-Strip-level item that stays visible when
// other apps become frontmost. Uses `dlopen` + `dlsym` on
// /System/Library/PrivateFrameworks/DFRFoundation.framework so no linker
// dependency on private symbols exists.
//
// Success line:
//   PRESENTER ok dfrSetStatus=<int> controlStripPresence=<int>
// Failure line:
//   PRESENTER fail reason=<...>
//
// The probe waits 12 seconds so the user can Cmd-Tab to another app and
// visually confirm the custom strip is still present, then cleans up.

import AppKit
import Darwin

typealias DFRSetStatus_t                              = @convention(c) (Int32) -> Void
typealias DFRElementSetControlStripPresence_t         = @convention(c) (CFString, Bool) -> Void
typealias DFRSystemModalShowsCloseBoxWhenFrontMost_t  = @convention(c) (Bool) -> Void

func loadDFR() -> UnsafeMutableRawPointer? {
    let path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
    return dlopen(path, RTLD_LAZY | RTLD_LOCAL)
}

func sym<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
    guard let s = dlsym(handle, name) else { return nil }
    return unsafeBitCast(s, to: T.self)
}

let stripIdentifier = "com.local.snappy-nest.probe02.strip" as CFString
let itemIdentifier  = NSTouchBarItem.Identifier(rawValue: "com.local.snappy-nest.probe02.strip")

final class StripView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemGreen.cgColor
    }
    required init?(coder: NSCoder) { fatalError("unused") }
}

final class Delegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    private var handle: UnsafeMutableRawPointer?
    private var dfrSet: DFRSetStatus_t?
    private var dfrPresence: DFRElementSetControlStripPresence_t?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let h = loadDFR() else {
            NSLog("PRESENTER fail reason=dlopen_dfrfoundation")
            NSApp.terminate(nil); return
        }
        handle = h
        dfrSet      = sym(h, "DFRSetStatus", as: DFRSetStatus_t.self)
        dfrPresence = sym(h, "DFRElementSetControlStripPresenceForIdentifier",
                          as: DFRElementSetControlStripPresence_t.self)

        guard let dfrSet = dfrSet, let dfrPresence = dfrPresence else {
            NSLog("PRESENTER fail reason=dlsym missing setStatus=\(dfrSet != nil) presence=\(dfrPresence != nil)")
            NSApp.terminate(nil); return
        }

        // Register a system-modal touch-bar item, then mark it as Control-Strip resident.
        let item = NSCustomTouchBarItem(identifier: itemIdentifier)
        item.view = StripView(frame: NSRect(x: 0, y: 0, width: 60, height: 30))

        // `+[NSTouchBarItem addSystemTrayItem:]` is not exposed in the public
        // AppKit headers, so call it via the Obj-C runtime.
        let selector = NSSelectorFromString("addSystemTrayItem:")
        let cls: AnyClass = NSTouchBarItem.self
        if (cls as AnyObject).responds(to: selector) {
            _ = (cls as AnyObject).perform(selector, with: item)
        } else {
            NSLog("PRESENTER fail reason=no_addSystemTrayItem_selector")
            NSApp.terminate(nil); return
        }
        dfrPresence(stripIdentifier, true)
        dfrSet(2) // 2 = force show custom presentation

        NSLog("PRESENTER ok dfrSetStatus=2 controlStripPresence=1")
        NSLog("PRESENTER note switch to another app (Cmd-Tab) and verify the green square stays visible.")

        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
            self.cleanup()
        }
    }

    private func cleanup() {
        if let dfrPresence = dfrPresence {
            dfrPresence(stripIdentifier, false)
        }
        if let dfrSet = dfrSet {
            dfrSet(0)
        }
        NSLog("PRESENTER exit cleaned_up")
        NSApp.terminate(nil)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Delegate()
app.delegate = delegate
app.run()
