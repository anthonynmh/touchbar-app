import AppKit
import SnappyNestCore
import SnappyNestUI

// Placeholder app entry; real AppDelegate lands with the main-app milestone.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Snappy Nest scaffold — core=\(SnappyNestCore.versionTag) ui=\(SnappyNestUI.core)")
        NSLog("Real app milestone not yet reached. Quit with Cmd-Q or `kill` the process.")
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
