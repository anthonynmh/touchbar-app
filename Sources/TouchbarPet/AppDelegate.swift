import AppKit
import SnappyNestCore
import SnappyNestUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var toggleOverlayMenuItem: NSMenuItem!
    private var presentationStatusMenuItem: NSMenuItem!
    private var renderer: SceneRenderer!
    private var presenter: TouchBarPresenter!
    private var preferPersistent = true
    private var didShowPresentationFailure = false

    private var clock: ClockProvider!
    private var battery: BatteryProvider!
    private var volume: VolumeProvider!
    private var brightness: BrightnessProvider!
    private var mediaSpotify: MediaSource!
    private var mediaBrowser: MediaSource!
    private var pet: PetController!
    private var composer: SceneComposer!

    private var tickTimer: Timer?
    private var spriteTimer: Timer?
    private var preview: EnlargedPreviewWindow?

    private let touchBarBounds = NSRect(x: 0, y: 0, width: 685, height: 30)
    private let seed: UInt64 = 0xC0FF_EECA_FED0_0DF0

    private enum MediaChoice: String { case auto, spotify, browser }
    private var mediaChoice: MediaChoice = .auto

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[SnappyNest] launching")

        // Providers
        NSLog("[SnappyNest] setup clock")
        clock       = RealClockProvider()
        NSLog("[SnappyNest] setup battery")
        battery     = RealBatteryProvider()
        NSLog("[SnappyNest] setup volume")
        volume      = RealVolumeProvider()
        NSLog("[SnappyNest] setup brightness")
        brightness  = RealBrightnessProvider()
        NSLog("[SnappyNest] setup spotify")
        mediaSpotify = SpotifyMediaSource()
        NSLog("[SnappyNest] setup mediaremote")
        mediaBrowser = MediaRemoteSource()
        NSLog("[SnappyNest] providers ready")

        // Scene
        let layout = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0)
        composer = SceneComposer(layout: layout)
        pet = PetController(seed: seed, layout: layout)

        // Renderer + presenter
        renderer = SceneRenderer(frame: touchBarBounds)
        renderer.onBrightnessChange = { [weak self] v in self?.brightness.set(v) }
        renderer.onVolumeChange     = { [weak self] v in self?.volume.set(v) }
        renderer.onTogglePlayPause  = { [weak self] in self?.activeSource().togglePlayPause() }

        installMenuBar()
        installPresenter()
        startTimers()
        renderOnce()
    }

    private func installPresenter() {
        if preferPersistent {
            let p = PersistentPresenter(rendererView: renderer)
            presenter = p
        } else {
            presenter = AppFrontmostPresenter(rendererView: renderer)
        }
        presenter.stateDidChange = { [weak self] state in
            self?.presentationStateDidChange(state)
        }
        presenter.install()
    }

    private func installMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐾"
        let menu = NSMenu()
        menu.addItem(withTitle: "Snappy Nest", action: nil, keyEquivalent: "").isEnabled = false
        presentationStatusMenuItem = NSMenuItem(
            title: "Touch Bar: Starting…",
            action: nil,
            keyEquivalent: ""
        )
        presentationStatusMenuItem.isEnabled = false
        menu.addItem(presentationStatusMenuItem)
        menu.addItem(NSMenuItem.separator())

        let toggle = NSMenuItem(title: "Hide Touch Bar Overlay", action: #selector(toggleOverlay), keyEquivalent: "\\")
        toggle.keyEquivalentModifierMask = [.command, .option]
        toggle.target = self
        menu.addItem(toggle)
        toggleOverlayMenuItem = toggle

        let preview = NSMenuItem(title: "Enlarged Preview…", action: #selector(showPreview), keyEquivalent: "P")
        preview.target = self
        menu.addItem(preview)

        menu.addItem(NSMenuItem.separator())
        let choice = NSMenu(title: "Media source")
        for opt in [MediaChoice.auto, .spotify, .browser] {
            let mi = NSMenuItem(title: opt.rawValue.capitalized, action: #selector(pickMedia(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = opt.rawValue
            mi.state = (opt == mediaChoice) ? .on : .off
            choice.addItem(mi)
        }
        let choiceHeader = NSMenuItem(title: "Media source", action: nil, keyEquivalent: "")
        choiceHeader.submenu = choice
        menu.addItem(choiceHeader)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit Snappy Nest", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func startTimers() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        spriteTimer?.invalidate()
        spriteTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in
            self?.pet.advanceFrame()
            self?.renderOnce()
        }
    }

    private func tick() {
        let now = clock.now
        let media = currentMedia()
        pet.tick(now: now, media: media)
        renderOnce()
    }

    private func renderOnce() {
        let now = clock.now
        let media = currentMedia()
        let bright = brightness.value
        let brightAvail: Bool
        if case .supported = brightness.capability { brightAvail = true } else { brightAvail = false }
        let vol = volume.value
        let volMuted = volume.isMuted
        let volAvail: Bool
        if case .supported = volume.capability { volAvail = true } else { volAvail = false }
        let model = composer.compose(
            now: now,
            pet: pet.state,
            battery: battery.snapshot,
            brightness: (bright, brightAvail),
            volume: (vol, volMuted, volAvail),
            media: media
        )
        renderer.update(model: model)
        preview?.update(model: model)
    }

    private func currentMedia() -> MediaSnapshot {
        switch mediaChoice {
        case .spotify: return mediaSpotify.snapshot
        case .browser: return mediaBrowser.snapshot
        case .auto:
            let s = mediaSpotify.snapshot
            let b = mediaBrowser.snapshot
            if s.state == .playing { return s }
            if b.state == .playing { return b }
            if s.state == .paused  { return s }
            if b.state == .paused  { return b }
            return .unknown
        }
    }

    private func activeSource() -> MediaSource {
        switch mediaChoice {
        case .spotify: return mediaSpotify
        case .browser: return mediaBrowser
        case .auto:
            return mediaSpotify.snapshot.state == .playing ? mediaSpotify : mediaBrowser
        }
    }

    @objc private func toggleOverlay() {
        if presenter.state.isPresentationRequested {
            presenter.uninstall()
        } else {
            presenter.install()
            renderOnce()
        }
    }

    private func presentationStateDidChange(_ state: TouchBarPresentationState) {
        switch state {
        case .idle:
            presentationStatusMenuItem?.title = "Touch Bar: Idle"
        case .installing:
            statusItem?.button?.title = "🐾…"
            toggleOverlayMenuItem?.title = "Hide Touch Bar Overlay"
            presentationStatusMenuItem?.title = "Touch Bar: Installing…"
            NSLog("[SnappyNest] presenter state=installing")
        case let .visible(geometry):
            statusItem?.button?.title = "🐾"
            toggleOverlayMenuItem?.title = "Hide Touch Bar Overlay"
            presentationStatusMenuItem?.title = String(
                format: "Touch Bar: Persistent %.0f×%.0f @ %.1f×",
                geometry.width, geometry.height, geometry.backingScale
            )
            NSLog("[SnappyNest] presenter state=visible")
        case let .fallback(geometry):
            statusItem?.button?.title = "🐾⚠︎"
            toggleOverlayMenuItem?.title = "Hide Touch Bar Overlay"
            presentationStatusMenuItem?.title = String(
                format: "Touch Bar: App-frontmost %.0f×%.0f @ %.1f×",
                geometry.width, geometry.height, geometry.backingScale
            )
            NSLog("[SnappyNest] presenter state=fallback")
        case .hidden:
            statusItem?.button?.title = "🐾💤"
            toggleOverlayMenuItem?.title = "Show Touch Bar Overlay"
            presentationStatusMenuItem?.title = "Touch Bar: Hidden"
            NSLog("[SnappyNest] presenter state=hidden")
        case let .failed(reason):
            statusItem?.button?.title = "🐾⚠︎"
            toggleOverlayMenuItem?.title = "Show Touch Bar Overlay"
            presentationStatusMenuItem?.title = "Touch Bar: Not visible"
            presentationStatusMenuItem?.toolTip = reason
            NSLog("[SnappyNest] presenter state=failed reason=\(reason)")
            showPresentationFailureOnce(reason: reason)
        }
    }

    private func showPresentationFailureOnce(reason: String) {
        guard !didShowPresentationFailure else { return }
        didShowPresentationFailure = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Snappy Nest could not open the Touch Bar"
        alert.informativeText = "Neither the persistent presenter nor the app-frontmost fallback became visible (\(reason)). Use 🐾 → Enlarged Preview to inspect the world, then run ./Install/run-probe.sh 02 from the source checkout for Touch Bar diagnostics."
        alert.addButton(withTitle: "Open Enlarged Preview")
        alert.addButton(withTitle: "Dismiss")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            showPreview()
        }
    }

    @objc private func showPreview() {
        if preview == nil { preview = EnlargedPreviewWindow() }
        preview?.show()
        renderOnce()
    }

    @objc private func pickMedia(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let c = MediaChoice(rawValue: raw) else { return }
        mediaChoice = c
        if let siblings = sender.menu?.items {
            for it in siblings { it.state = (it == sender) ? .on : .off }
        }
        renderOnce()
    }

    @objc private func quit() {
        presenter?.uninstall()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        presenter?.uninstall()
    }
}
