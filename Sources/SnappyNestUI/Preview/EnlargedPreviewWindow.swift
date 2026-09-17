import AppKit
import SnappyNestCore

/// A menu-bar-triggered NSWindow that shows a 6× nearest-neighbor scaled
/// preview of the same SceneRenderer used on the Touch Bar. Useful for
/// verifying artwork and inspecting the layout without touching hardware.
public final class EnlargedPreviewWindow {
    private let window: NSWindow
    private let scale: CGFloat = 6

    private let renderer: SceneRenderer
    private let stripSize = CGSize(width: 685, height: 30)

    public init() {
        let contentSize = CGSize(width: stripSize.width * scale, height: stripSize.height * scale)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Snappy Nest — Enlarged Preview"
        window.isReleasedWhenClosed = false
        window.setContentSize(contentSize)

        renderer = SceneRenderer(frame: NSRect(origin: .zero, size: stripSize))
        renderer.wantsLayer = true

        // Wrap the renderer in a scaled parent view so the native-bounds view
        // paints at 685×30 pt and we magnify to 6× via layer transform.
        let host = NSView(frame: NSRect(origin: .zero, size: contentSize))
        host.wantsLayer = true
        host.layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
        host.addSubview(renderer)
        renderer.frame = NSRect(origin: .zero, size: stripSize)
        renderer.layer?.magnificationFilter = .nearest
        renderer.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        renderer.layer?.anchorPoint = .zero
        renderer.frame = NSRect(x: 0, y: 0, width: stripSize.width, height: stripSize.height)
        window.contentView = host
    }

    public func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func update(model: SceneModel) {
        renderer.update(model: model)
    }
}
