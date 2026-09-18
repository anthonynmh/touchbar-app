import AppKit
import CoreGraphics
import SnappyNestCore

/// Layer-backed NSView that paints a `SceneModel`. Owns a small CALayer tree
/// and re-uses layers across frames — only `contents` swaps for the pet, and
/// integer-pixel-aligned position moves for props/celestial.
///
/// The view assumes flipped coordinates (`isFlipped = true`) and is safe to
/// resize (`layout()` re-lays out sublayers). Consumers call
/// `update(model:)` on the main thread each tick.
public final class SceneRenderer: NSView {

    // Layers, back to front. The sky is fixed; the world and the controls
    // page each live in a full-width container that slides horizontally when
    // the page changes.
    private let skyLayer = CALayer()
    private let worldContainer = CALayer()
    private let terrainLayer = CALayer()
    private let celestialLayer = CALayer()
    private let sceneryContainer = CALayer()
    private let progressTrailLayer = CAShapeLayer()
    private let petLayer = CALayer()
    private let clockPillLayer = CALayer()
    private let clockTextLayer = CATextLayer()

    private let controlsContainer = CALayer()
    private let controlsTerrainLayer = CALayer()
    private let batteryGlyphLayer = CALayer()
    private let batteryTextLayer = CATextLayer()
    private let brightnessIconLayer = CALayer()
    private let brightnessTrackLayer = CAShapeLayer()
    private let brightnessFillLayer = CAShapeLayer()
    private let brightnessKnob = CALayer()
    private let volumeIconLayer = CALayer()
    private let volumeTrackLayer = CAShapeLayer()
    private let volumeFillLayer = CAShapeLayer()
    private let volumeKnob = CALayer()
    private let playPauseLayer = CALayer()

    private var backingScale: CGFloat = 2.0
    private var cachedSky: (key: SkyPainter.Key, image: CGImage)?
    private var cachedTerrain: (key: SkyPainter.Key, image: CGImage)?
    private var cachedControlsTerrain: (key: SkyPainter.Key, image: CGImage)?
    private var currentModel: SceneModel?
    /// Camera over the two pages: 0 shows the world, `full.width` shows the
    /// controls. Dragging the scene moves it; releasing snaps to a page.
    private var cameraOffset: CGFloat = 0
    private var settledPage: LayoutEngine.Page = .world
    private var isDraggingCamera = false
    private var dragStartOffset: CGFloat = 0
    public static let pageSlideDuration: TimeInterval = 0.28
    /// Flick speed (points/second) that commits a page change regardless of
    /// how far the scene was dragged.
    public static let flickVelocity: CGFloat = 250

    // Clock reveal: tapping the sun/moon shows the time briefly.
    private var clockRevealUntil: Date?
    public static let clockRevealDuration: TimeInterval = 3
    /// Injected clock so tests can drive the reveal deterministically.
    var now: () -> Date = { Date() }

    /// Extra points around the pet and the sun/moon that still count as a hit.
    public static let tapSlop: CGFloat = 6

    // Callbacks — the presenter wires these to the volume/brightness/media
    // providers when the user drags a control or taps play/pause, and to the
    // pet controller for taps on the pet or the ground.
    public var onBrightnessChange: ((Double) -> Void)?
    public var onVolumeChange:     ((Double) -> Void)?
    public var onTogglePlayPause:  (() -> Void)?
    public var onPetTap:           (() -> Void)?
    public var onGroundTap:        ((CGFloat) -> Void)?
    /// The scene was dragged and settled on a page; the owner should compose
    /// with that `LayoutEngine.Page` from now on.
    public var onPageChange:       ((LayoutEngine.Page) -> Void)?

    public override var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildLayerTree()
        configureInput()
    }

    public required init?(coder: NSCoder) { fatalError() }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        backingScale = window?.backingScaleFactor ?? 2.0
        applyContentsScale(to: layer)
        cachedSky = nil
        cachedTerrain = nil
        cachedControlsTerrain = nil
        if let m = currentModel { update(model: m) }
    }

    public override func layout() {
        super.layout()
        cachedSky = nil
        cachedTerrain = nil
        cachedControlsTerrain = nil
        if let m = currentModel { update(model: m) }
    }

    private func applyContentsScale(to layer: CALayer?) {
        guard let layer = layer else { return }
        layer.contentsScale = backingScale
        layer.rasterizationScale = backingScale
        for sub in layer.sublayers ?? [] { applyContentsScale(to: sub) }
    }

    private func buildLayerTree() {
        layer = CALayer()
        layer?.masksToBounds = true
        layer?.contentsScale = backingScale

        let worldLayers: [CALayer] = [
            terrainLayer, celestialLayer, sceneryContainer, progressTrailLayer, petLayer,
            clockPillLayer
        ]
        let controlLayers: [CALayer] = [
            controlsTerrainLayer,
            brightnessIconLayer, brightnessTrackLayer, brightnessFillLayer, brightnessKnob,
            volumeIconLayer, volumeTrackLayer, volumeFillLayer, volumeKnob,
            playPauseLayer, batteryGlyphLayer, batteryTextLayer
        ]
        for l in [skyLayer, worldContainer, controlsContainer] + worldLayers + controlLayers {
            l.contentsScale = backingScale
            l.magnificationFilter = .nearest
            l.minificationFilter = .nearest
            l.isOpaque = false
        }
        layer?.addSublayer(skyLayer)
        layer?.addSublayer(worldContainer)
        layer?.addSublayer(controlsContainer)
        worldLayers.forEach { worldContainer.addSublayer($0) }
        controlLayers.forEach { controlsContainer.addSublayer($0) }
        for c in [worldContainer, controlsContainer] { c.anchorPoint = .zero }

        clockPillLayer.addSublayer(clockTextLayer)
        clockPillLayer.isHidden = true

        progressTrailLayer.strokeColor = Palette.cyan.copy(alpha: 0.55)
        progressTrailLayer.lineWidth = 1.0
        progressTrailLayer.fillColor = nil
        progressTrailLayer.lineCap = .round

        for track in [brightnessTrackLayer, volumeTrackLayer] {
            track.strokeColor = Palette.brown.copy(alpha: 0.55)
            track.lineWidth = 5
            track.lineCap = .round
            track.fillColor = nil
        }
        for fill in [brightnessFillLayer, volumeFillLayer] {
            fill.lineWidth = 3
            fill.lineCap = .round
            fill.fillColor = nil
        }
        for knob in [brightnessKnob, volumeKnob] {
            knob.cornerRadius = 4
            knob.borderWidth = 1
            knob.borderColor = Palette.brown
        }

        for text in [batteryTextLayer, clockTextLayer] {
            text.alignmentMode = .center
            text.truncationMode = .none
            text.foregroundColor = Palette.cream
            text.contentsScale = backingScale
        }
        batteryTextLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        batteryTextLayer.fontSize = 9
        clockTextLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        clockTextLayer.fontSize = 10
        clockPillLayer.backgroundColor = CGColor(red: 0x18/255, green: 0x14/255, blue: 0x0F/255, alpha: 0.82)
        clockPillLayer.cornerRadius = 5
        clockPillLayer.borderWidth = 1
        clockPillLayer.borderColor = Palette.cream.copy(alpha: 0.35)
    }

    private func configureInput() {
        // Custom Touch Bar views do not automatically behave like NSControl.
        // Direct-touch gesture recognizers keep taps and scrubbing functional
        // while the persistent bar's accessory app is not frontmost.
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        click.numberOfTouchesRequired = 1
        click.allowedTouchTypes = .direct
        addGestureRecognizer(click)

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.numberOfTouchesRequired = 1
        pan.allowedTouchTypes = .direct
        addGestureRecognizer(pan)
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public func update(model: SceneModel) {
        currentModel = model
        let full = model.layout.full
        let world = LayoutEngine(bounds: full, backingScale: backingScale, page: .world).regions
        let controls = LayoutEngine(bounds: full, backingScale: backingScale, page: .controls).regions

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        paintSky(regions: world, time: model.time)
        paintTerrain(regions: world, time: model.time)
        paintCelestial(pos: model.celestial)
        paintScenery(model.props, regions: world)
        paintProgressTrail(regions: world, fraction: model.progressFraction)
        paintPet(state: model.pet, regions: world)
        paintClock(model: model, regions: world)
        paintControlsTerrain(regions: controls, time: model.time)
        paintBattery(model.battery, regions: controls)
        paintBrightness(value: model.brightness, available: model.brightnessAvailable, regions: controls)
        paintVolume(value: model.volume, muted: model.volumeMuted, available: model.volumeAvailable, regions: controls)
        paintPlayPause(media: model.media, regions: controls)
        syncCamera(to: model.layout.page, full: full)
        CATransaction.commit()
    }

    // MARK: - Camera / pages

    /// True once the camera has settled on the controls page.
    var isShowingControls: Bool { settledPage == .controls }

    /// Called from `update(model:)`: follow the owner's page unless the user
    /// is mid-drag, so an idle timeout or an external change pans the scene.
    private func syncCamera(to page: LayoutEngine.Page, full: CGRect) {
        worldContainer.bounds = full
        controlsContainer.bounds = full
        if isDraggingCamera { return }
        if page != settledPage {
            settledPage = page
            animateCamera(to: page == .world ? 0 : full.width, width: full.width)
        } else if worldContainer.animation(forKey: "pageSlide") == nil {
            cameraOffset = page == .world ? 0 : full.width
            positionContainers(offset: cameraOffset, width: full.width)
        }
    }

    private func positionContainers(offset: CGFloat, width: CGFloat) {
        worldContainer.position = CGPoint(x: -offset, y: 0)
        controlsContainer.position = CGPoint(x: width - offset, y: 0)
    }

    private func animateCamera(to target: CGFloat, width: CGFloat) {
        let from = cameraOffset
        cameraOffset = target
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        positionContainers(offset: target, width: width)
        for (container, fromX) in [(worldContainer, -from), (controlsContainer, width - from)] {
            let slide = CABasicAnimation(keyPath: "position")
            slide.fromValue = NSValue(point: CGPoint(x: fromX, y: 0))
            slide.toValue = NSValue(point: container.position)
            slide.duration = Self.pageSlideDuration
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            container.add(slide, forKey: "pageSlide")
        }
        CATransaction.commit()
    }

    /// Drive the camera from a horizontal drag. `translation` is the finger's
    /// movement since the drag began; a positive value pulls the world back
    /// into view.
    func beginCameraDrag() {
        isDraggingCamera = true
        dragStartOffset = cameraOffset
        worldContainer.removeAnimation(forKey: "pageSlide")
        controlsContainer.removeAnimation(forKey: "pageSlide")
    }

    func moveCameraDrag(translationX: CGFloat) {
        guard isDraggingCamera, let width = currentModel?.layout.full.width else { return }
        cameraOffset = min(width, max(0, dragStartOffset - translationX))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        positionContainers(offset: cameraOffset, width: width)
        CATransaction.commit()
    }

    func endCameraDrag(velocityX: CGFloat) {
        guard isDraggingCamera, let width = currentModel?.layout.full.width else { return }
        isDraggingCamera = false
        let page: LayoutEngine.Page
        if velocityX < -Self.flickVelocity {
            page = .controls
        } else if velocityX > Self.flickVelocity {
            page = .world
        } else {
            page = cameraOffset < width / 2 ? .world : .controls
        }
        let changed = page != settledPage
        settledPage = page
        animateCamera(to: page == .world ? 0 : width, width: width)
        if changed { onPageChange?(page) }
    }

    // MARK: - Sky

    private func paintSky(regions: LayoutEngine.Regions, time: WorldTime) {
        skyLayer.frame = regions.full
        skyLayer.magnificationFilter = .linear
        let key = SkyPainter.Key(time: time, size: regions.full.size, scale: backingScale)
        if cachedSky?.key != key {
            cachedSky = (key, SkyPainter.sky(size: regions.full.size, time: time, scale: backingScale))
        }
        skyLayer.contents = cachedSky?.image
    }

    private func paintTerrain(regions: LayoutEngine.Regions, time: WorldTime) {
        terrainLayer.frame = regions.middle
        terrainLayer.magnificationFilter = .linear
        let key = SkyPainter.Key(time: time, size: regions.middle.size, scale: backingScale)
        if cachedTerrain?.key != key {
            cachedTerrain = (key, SkyPainter.terrain(size: regions.middle.size, time: time, scale: backingScale))
        }
        terrainLayer.contents = cachedTerrain?.image
    }

    private func paintControlsTerrain(regions: LayoutEngine.Regions, time: WorldTime) {
        controlsTerrainLayer.frame = regions.full
        controlsTerrainLayer.magnificationFilter = .linear
        let key = SkyPainter.Key(time: time, size: regions.full.size, scale: backingScale)
        if cachedControlsTerrain?.key != key {
            cachedControlsTerrain = (key, SkyPainter.terrain(size: regions.full.size, time: time,
                                                             scale: backingScale, xOffset: regions.full.width))
        }
        controlsTerrainLayer.contents = cachedControlsTerrain?.image
    }

    // MARK: - Celestial

    private func celestialRect(_ pos: CelestialPosition) -> CGRect {
        let size = pos.body == .sun ? PlaceholderSprites.sunSize : PlaceholderSprites.moonSize
        return CGRect(x: pos.point.x - size.width / 2, y: pos.point.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    private func paintCelestial(pos: CelestialPosition) {
        celestialLayer.magnificationFilter = .linear
        switch pos.body {
        case .sun:  celestialLayer.contents = PlaceholderSprites.sunImage(scale: backingScale)
        case .moon: celestialLayer.contents = PlaceholderSprites.moonImage(scale: backingScale)
        }
        celestialLayer.frame = celestialRect(pos)
    }

    // MARK: - Scenery

    private var sceneryLayers: [CALayer] = []

    private func paintScenery(_ objs: [SceneObject], regions: LayoutEngine.Regions) {
        while sceneryLayers.count < objs.count {
            let l = CALayer()
            l.magnificationFilter = .nearest
            l.contentsScale = backingScale
            sceneryContainer.addSublayer(l)
            sceneryLayers.append(l)
        }
        let size = PlaceholderSprites.propSize
        for (idx, obj) in objs.enumerated() {
            let layer = sceneryLayers[idx]
            layer.isHidden = false
            layer.contents = PlaceholderSprites.propImage(prop: obj.prop.rawValue, scale: backingScale)
            layer.frame = CGRect(x: (obj.position.x - size.width / 2).rounded(),
                                 y: obj.position.y - size.height,
                                 width: size.width, height: size.height)
        }
        for extra in objs.count..<sceneryLayers.count {
            sceneryLayers[extra].isHidden = true
        }
    }

    // MARK: - Progress trail

    private func paintProgressTrail(regions: LayoutEngine.Regions, fraction: Double?) {
        guard let f = fraction else {
            progressTrailLayer.path = nil
            return
        }
        let m = regions.middle
        let inset: CGFloat = 8
        let y = m.maxY - 3
        let x0 = m.minX + inset
        let x1 = m.minX + inset + CGFloat(f) * (m.width - 2 * inset)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0, y: y))
        path.addLine(to: CGPoint(x: x1, y: y))
        progressTrailLayer.frame = regions.full
        progressTrailLayer.path = path
    }

    // MARK: - Pet

    private func paintPet(state: PetState, regions: LayoutEngine.Regions) {
        let size = PetSprites.cellSize
        petLayer.contents = PetSprites.image(
            action: state.action,
            frame: state.frameIndex,
            facing: state.facing,
            scale: backingScale
        )
        // Anchor: horizontal center of sprite, feet on the ground line. Hop
        // frames lift the whole cell.
        let lift = PetSprites.lift(action: state.action, frame: state.frameIndex)
        let x = (state.position.x - size.width / 2).rounded()
        let y = state.position.y - size.height - lift
        petLayer.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: - Clock reveal

    /// True while the tapped-sun/moon clock pill is showing.
    var isClockRevealed: Bool { !clockPillLayer.isHidden }

    private func paintClock(model: SceneModel, regions: LayoutEngine.Regions) {
        guard let until = clockRevealUntil, now() < until else {
            clockRevealUntil = nil
            clockPillLayer.isHidden = true
            return
        }
        let label = model.time.clockLabel()
        clockTextLayer.string = label
        let textWidth = (label as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        ]).width
        let pillSize = CGSize(width: (textWidth + 12).rounded(), height: 16)
        let body = celestialRect(model.celestial)
        let middle = regions.middle
        // Beside the body on whichever side has room, vertically centered on it.
        var x = body.maxX + 3
        if x + pillSize.width > middle.maxX - 2 { x = body.minX - 3 - pillSize.width }
        x = min(middle.maxX - 2 - pillSize.width, max(middle.minX + 2, x))
        let y = min(model.layout.full.maxY - pillSize.height - 1, max(1, body.midY - pillSize.height / 2))
        clockPillLayer.frame = CGRect(x: x.rounded(), y: y.rounded(), width: pillSize.width, height: pillSize.height)
        clockTextLayer.frame = CGRect(x: 0, y: 1.5, width: pillSize.width, height: 13)
        clockPillLayer.isHidden = false
    }

    private func revealClock() {
        clockRevealUntil = now().addingTimeInterval(Self.clockRevealDuration)
        if let m = currentModel { update(model: m) }
    }

    // MARK: - Battery

    private func paintBattery(_ snap: BatterySnapshot, regions: LayoutEngine.Regions) {
        let r = regions.battery
        let glyph = BatteryGlyph.size
        let label: String
        if let pct = snap.percentage {
            label = "\(Int((pct * 100).rounded()))%"
        } else {
            label = "—"
        }
        let textWidth: CGFloat = 26
        let gap: CGFloat = 4
        let total = glyph.width + gap + textWidth
        let x0 = (r.midX - total / 2).rounded()

        batteryGlyphLayer.contents = BatteryGlyph.image(snapshot: snap, scale: backingScale)
        batteryGlyphLayer.magnificationFilter = .linear
        batteryGlyphLayer.frame = CGRect(x: x0, y: (r.midY - glyph.height / 2).rounded(),
                                         width: glyph.width, height: glyph.height)
        batteryTextLayer.string = label
        batteryTextLayer.foregroundColor = snap.percentage == nil ? Palette.unavailableTint : Palette.cream
        batteryTextLayer.alignmentMode = .left
        batteryTextLayer.frame = CGRect(x: x0 + glyph.width + gap, y: (r.midY - 6).rounded(),
                                        width: textWidth, height: 12)
    }

    // MARK: - Brightness / Volume / Play-Pause

    /// The hit/track geometry the tests rely on: `region.insetBy(dx: 8, dy: 8)`.
    private func trackRect(_ region: CGRect) -> CGRect { region.insetBy(dx: 8, dy: 8) }

    private func paintSlider(region: CGRect, value: Double, accent: CGColor, active: Bool,
                             icon: CGImage, iconLayer: CALayer, track: CAShapeLayer,
                             fill: CAShapeLayer, knob: CALayer, regions: LayoutEngine.Regions) {
        let r = trackRect(region)
        let iconSize = ControlGlyphs.size
        iconLayer.contents = icon
        iconLayer.magnificationFilter = .linear
        iconLayer.frame = CGRect(x: r.minX - 2, y: (r.midY - iconSize.height / 2).rounded(),
                                 width: iconSize.width, height: iconSize.height)

        // The visible track starts after the icon but the value still maps
        // across the full inset rect, so taps/drags land where they always did.
        let trackStart = r.minX + iconSize.width + 3
        let knobX = r.minX + r.width * CGFloat(value)
        let trackPath = CGMutablePath()
        trackPath.move(to: CGPoint(x: trackStart, y: r.midY))
        trackPath.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        track.path = trackPath
        track.frame = regions.full

        let fillPath = CGMutablePath()
        fillPath.move(to: CGPoint(x: trackStart, y: r.midY))
        fillPath.addLine(to: CGPoint(x: max(trackStart, knobX), y: r.midY))
        fill.path = fillPath
        fill.strokeColor = active ? accent : Palette.unavailableTint.copy(alpha: 0.5)
        fill.frame = regions.full
        fill.isHidden = !active

        knob.backgroundColor = active ? Palette.cream : Palette.unavailableTint
        knob.frame = CGRect(x: (max(trackStart, knobX) - 4.5).rounded(), y: r.midY - 6.5, width: 9, height: 13)
    }

    private func paintBrightness(value: Double, available: Bool, regions: LayoutEngine.Regions) {
        paintSlider(region: regions.brightness, value: value, accent: Palette.golden, active: available,
                    icon: ControlGlyphs.brightness(available: available, scale: backingScale),
                    iconLayer: brightnessIconLayer, track: brightnessTrackLayer,
                    fill: brightnessFillLayer, knob: brightnessKnob, regions: regions)
    }

    private func paintVolume(value: Double, muted: Bool, available: Bool, regions: LayoutEngine.Regions) {
        let displayed = muted ? 0 : value
        paintSlider(region: regions.volume, value: displayed, accent: Palette.cyan, active: available && !muted,
                    icon: ControlGlyphs.volume(level: value, muted: muted, available: available, scale: backingScale),
                    iconLayer: volumeIconLayer, track: volumeTrackLayer,
                    fill: volumeFillLayer, knob: volumeKnob, regions: regions)
        if available && muted {
            volumeKnob.backgroundColor = Palette.cream.copy(alpha: 0.6)
        }
    }

    private func paintPlayPause(media: MediaSnapshot, regions: LayoutEngine.Regions) {
        let r = regions.playPause
        if !media.canPlayPause {
            playPauseLayer.isHidden = true
            return
        }
        playPauseLayer.isHidden = false
        playPauseLayer.magnificationFilter = .linear
        let size = ControlGlyphs.playPauseSize
        playPauseLayer.frame = CGRect(x: (r.midX - size.width / 2).rounded(), y: (r.midY - size.height / 2).rounded(),
                                      width: size.width, height: size.height)
        playPauseLayer.contents = ControlGlyphs.playPause(isPlaying: media.state == .playing, scale: backingScale)
    }

    // MARK: - Input

    @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        handleTap(at: recognizer.location(in: self))
    }

    private var panIsSlider = false

    @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            panIsSlider = isSliderPoint(point)
            if panIsSlider { handleDrag(at: point) } else { beginCameraDrag() }
        case .changed:
            if panIsSlider { handleDrag(at: point) }
            else { moveCameraDrag(translationX: recognizer.translation(in: self).x) }
        case .ended, .cancelled, .failed:
            if !panIsSlider { endCameraDrag(velocityX: recognizer.velocity(in: self).x) }
        default:
            break
        }
    }

    /// A drag that starts on a live slider scrubs it; anywhere else pans the scene.
    func isSliderPoint(_ point: CGPoint) -> Bool {
        guard let model = currentModel else { return false }
        return (model.layout.brightness.contains(point) && model.brightnessAvailable)
            || (model.layout.volume.contains(point) && model.volumeAvailable)
    }

    func handleTap(at point: CGPoint) {
        guard let model = currentModel else { return }
        let regions = model.layout
        switch regions.page {
        case .controls:
            if regions.playPause.contains(point) && model.media.canPlayPause {
                onTogglePlayPause?()
            } else if regions.brightness.contains(point) && model.brightnessAvailable {
                onBrightnessChange?(fraction(x: point.x, in: trackRect(regions.brightness)))
            } else if regions.volume.contains(point) && model.volumeAvailable {
                onVolumeChange?(fraction(x: point.x, in: trackRect(regions.volume)))
            }
        case .world:
            if celestialRect(model.celestial).insetBy(dx: -Self.tapSlop, dy: -Self.tapSlop).contains(point) {
                revealClock()
            } else if model.pet.hitRect(spriteSize: PetSprites.cellSize).insetBy(dx: -Self.tapSlop, dy: -Self.tapSlop).contains(point) {
                onPetTap?()
            } else if regions.middle.contains(point) {
                onGroundTap?(point.x)
            }
        }
    }

    func handleDrag(at point: CGPoint) {
        guard let model = currentModel else { return }
        if model.layout.brightness.contains(point) && model.brightnessAvailable {
            let f = fraction(x: point.x, in: trackRect(model.layout.brightness))
            onBrightnessChange?(f)
            return
        }
        if model.layout.volume.contains(point) && model.volumeAvailable {
            let f = fraction(x: point.x, in: trackRect(model.layout.volume))
            onVolumeChange?(f)
            return
        }
    }

    private func fraction(x: CGFloat, in rect: CGRect) -> Double {
        Double(min(1.0, max(0.0, (x - rect.minX) / max(1e-6, rect.width))))
    }
}
