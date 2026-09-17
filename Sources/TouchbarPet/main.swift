import AppKit
import SnappyNestCore
import SnappyNestUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
