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

    private var touchBarBounds = NSRect(x: 0, y: 0, width: 1085, height: 30)
    private let seed: UInt64 = 0xC0FF_EECA_FED0_0DF0

    /// Which page the strip shows. The pet follows the camera (`PetController.Mode`).
    private var page: LayoutEngine.Page = .world
    private var controlsLastTouchedAt: Date?
    /// The controls page slides back to the world after this much idle time.
    private let controlsIdleTimeout: TimeInterval = 10

    private enum MediaChoice: String { case auto, spotify, browser }
    private var mediaChoice: MediaChoice = .auto
    /// The source `currentMedia()` last picked in auto mode; `activeSource()`
    /// follows it so commands go to the player the pet is showing, and the
    /// arbiter keeps it on ties.
    private var autoChoice: MediaArbiter.Choice?

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
        let hostLibrary = PerlMediaRemoteHost.locateLibrary()
        NSLog("[SnappyNest] mediaremote host library=%@", hostLibrary?.path ?? "missing")
        mediaBrowser = MediaRemoteSource(hostLibraryURL: hostLibrary)
        NSLog("[SnappyNest] providers ready")

        // Scene
        let layout = LayoutEngine(bounds: touchBarBounds, backingScale: 2.0, page: page)
        composer = SceneComposer(layout: layout)
        pet = PetController(seed: seed, layout: layout.with(page: .world))

        // Renderer + presenter
        renderer = SceneRenderer(frame: touchBarBounds)
        renderer.onBrightnessChange = { [weak self] v in self?.touchedControls(); self?.brightness.set(v) }
        renderer.onVolumeChange     = { [weak self] v in self?.touchedControls(); self?.volume.set(v) }
        renderer.onTogglePlayPause  = { [weak self] in self?.activeSource().togglePlayPause() }
        renderer.onNextTrack        = { [weak self] in self?.activeSource().nextTrack() }
        renderer.onPreviousTrack    = { [weak self] in self?.activeSource().previousTrack() }
        renderer.onPageChange       = { [weak self] page in self?.setPage(page) }
        renderer.onSeek = { [weak self] fraction in
            guard let self else { return }
            self.pet.seekTo(fraction: fraction, now: self.clock.now)
            self.seek(toFraction: fraction)
            self.renderOnce()
        }
        renderer.onScrubBegin = { [weak self] in
            guard let self else { return }
            self.pet.beginScrub(now: self.clock.now)
        }
        renderer.onScrubMove = { [weak self] x in
            guard let self else { return }
            self.pet.scrub(x: x, now: self.clock.now)
            self.renderOnce()
        }
        renderer.onScrubEnd = { [weak self] in
            guard let self else { return }
            if let fraction = self.pet.endScrub(now: self.clock.now) {
                self.seek(toFraction: fraction)
            }
            self.renderOnce()
        }
        renderer.onPetTap = { [weak self] in
            guard let self else { return }
            self.pet.tapPet(now: self.clock.now)
            self.renderOnce()
        }
        renderer.onGroundTap = { [weak self] x in
            guard let self else { return }
            self.pet.walkTo(x: x, now: self.clock.now)
            self.renderOnce()
        }

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
        if page == .controls, let touched = controlsLastTouchedAt,
           now.timeIntervalSince(touched) > controlsIdleTimeout {
            setPage(.world)
        }
        renderOnce()
    }

    private func touchedControls() {
        controlsLastTouchedAt = clock.now
    }

    private func setPage(_ newPage: LayoutEngine.Page) {
        guard newPage != page else { return }
        page = newPage
        controlsLastTouchedAt = newPage == .controls ? clock.now : nil
        composer = SceneComposer(layout: composer.layout.with(page: newPage))
        pet.enter(Self.petMode(for: newPage), now: clock.now)
        NSLog("[SnappyNest] page=%@", String(describing: newPage))
        renderOnce()
    }

    private static func petMode(for page: LayoutEngine.Page) -> PetController.Mode {
        switch page {
        case .playback: return .playback
        case .world:    return .roam
        case .controls: return .workshop
        }
    }

    /// Seek the active source to a fraction of the current track. The
    /// source's own gate decides whether anything is sent; the readback
    /// steers the pet afterwards.
    private func seek(toFraction fraction: Double) {
        let media = currentMedia()
        guard media.canSeek, let duration = media.duration else { return }
        activeSource().seek(to: fraction * duration)
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
            let choice = MediaArbiter.choose(spotify: mediaSpotify.snapshot,
                                             remote: mediaBrowser.snapshot,
                                             previous: autoChoice)
            if choice != autoChoice {
                NSLog("[SnappyNest] auto media source=%@", String(describing: choice))
            }
            autoChoice = choice
            switch choice {
            case .spotify: return mediaSpotify.snapshot
            case .remote:  return mediaBrowser.snapshot
            case .none:    return .unknown
            }
        }
    }

    private func activeSource() -> MediaSource {
        switch mediaChoice {
        case .spotify: return mediaSpotify
        case .browser: return mediaBrowser
        case .auto:
            // The same source `currentMedia()` chose, so a seek or skip goes
            // to the player the pet is showing (paused Spotify included).
            _ = currentMedia()
            return autoChoice == .spotify ? mediaSpotify : mediaBrowser
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
            adoptMeasuredGeometry(geometry)
            statusItem?.button?.title = "🐾"
            toggleOverlayMenuItem?.title = "Hide Touch Bar Overlay"
            presentationStatusMenuItem?.title = String(
                format: "Touch Bar: Persistent %.0f×%.0f @ %.1f×",
                geometry.width, geometry.height, geometry.backingScale
            )
            NSLog("[SnappyNest] presenter state=visible")
        case let .fallback(geometry):
            adoptMeasuredGeometry(geometry)
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

    private func adoptMeasuredGeometry(_ geometry: TouchBarPresentationGeometry) {
        let measuredBounds = NSRect(
            x: 0,
            y: 0,
            width: geometry.width,
            height: geometry.height
        )
        guard measuredBounds != touchBarBounds ||
              composer.layout.backingScale != geometry.backingScale else { return }

        let oldMiddle = composer.layout.with(page: .world).regions.middle
        let oldState = pet.state
        let oldFraction = min(1, max(0,
            (oldState.position.x - oldMiddle.minX) / max(1, oldMiddle.width)
        ))
        let layout = LayoutEngine(
            bounds: measuredBounds,
            backingScale: geometry.backingScale,
            page: page
        )
        var resizedState = oldState
        resizedState.position.x = layout.petGroundX(
            fraction: Double(oldFraction),
            spriteHalfWidth: 12
        )
        resizedState.position.y = layout.with(page: .world).regions.middle.maxY - 4

        touchBarBounds = measuredBounds
        composer = SceneComposer(layout: layout)
        let mode = pet.mode
        pet = PetController(
            seed: seed,
            layout: layout.with(page: .world),
            initial: resizedState
        )
        pet.enter(mode, now: clock.now)
        NSLog(
            "[SnappyNest] scene layout width=%.1f height=%.1f backingScale=%.2f",
            geometry.width, geometry.height, geometry.backingScale
        )
        renderOnce()
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
        (mediaBrowser as? MediaRemoteSource)?.shutdown()
    }
}
