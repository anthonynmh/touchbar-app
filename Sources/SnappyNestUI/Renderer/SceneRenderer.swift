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

    // Layers, back to front.
    private let skyLayer = CALayer()
    private let celestialLayer = CALayer()
    private let sceneryContainer = CALayer()
    private let progressTrailLayer = CAShapeLayer()
    private let petLayer = CALayer()
    private let clockPillLayer = CALayer()
    private let clockTextLayer = CATextLayer()

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
    private var currentModel: SceneModel?

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
        if let m = currentModel { update(model: m) }
    }

    public override func layout() {
        super.layout()
        cachedSky = nil
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

        let ordered: [CALayer] = [
            skyLayer, celestialLayer, sceneryContainer, progressTrailLayer, petLayer,
            clockPillLayer,
            batteryGlyphLayer, batteryTextLayer,
            brightnessIconLayer, brightnessTrackLayer, brightnessFillLayer, brightnessKnob,
            volumeIconLayer, volumeTrackLayer, volumeFillLayer, volumeKnob,
            playPauseLayer
        ]
        for l in ordered {
            l.contentsScale = backingScale
            l.magnificationFilter = .nearest
            l.minificationFilter = .nearest
            l.isOpaque = false
            layer?.addSublayer(l)
        }
        clockPillLayer.addSublayer(clockTextLayer)
        clockPillLayer.isHidden = true

        progressTrailLayer.strokeColor = Palette.cyan.copy(alpha: 0.55)
        progressTrailLayer.lineWidth = 1.0
        progressTrailLayer.fillColor = nil
        progressTrailLayer.lineCap = .round

        for track in [brightnessTrackLayer, volumeTrackLayer] {
            track.strokeColor = CGColor(gray: 1, alpha: 0.18)
            track.lineWidth = 4
            track.lineCap = .round
            track.fillColor = nil
        }
        for fill in [brightnessFillLayer, volumeFillLayer] {
            fill.lineWidth = 4
            fill.lineCap = .round
            fill.fillColor = nil
        }
        for knob in [brightnessKnob, volumeKnob] {
            knob.cornerRadius = 3
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        paintSky(regions: model.layout, time: model.time)
        paintCelestial(pos: model.celestial)
        paintScenery(model.props, regions: model.layout)
        paintProgressTrail(regions: model.layout, fraction: model.progressFraction)
        paintPet(state: model.pet, regions: model.layout)
        paintClock(model: model)
        paintBattery(model.battery, regions: model.layout)
        paintBrightness(value: model.brightness, available: model.brightnessAvailable, regions: model.layout)
        paintVolume(value: model.volume, muted: model.volumeMuted, available: model.volumeAvailable, regions: model.layout)
        paintPlayPause(media: model.media, regions: model.layout)
        CATransaction.commit()
    }

    // MARK: - Sky

    private func paintSky(regions: LayoutEngine.Regions, time: WorldTime) {
        skyLayer.frame = regions.full
        skyLayer.magnificationFilter = .linear
        let key = SkyPainter.Key(time: time, size: regions.full.size, scale: backingScale)
        if cachedSky?.key != key {
            cachedSky = (key, SkyPainter.image(regions: regions, time: time, scale: backingScale))
        }
        skyLayer.contents = cachedSky?.image
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

    private func paintClock(model: SceneModel) {
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
        let middle = model.layout.middle
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
        knob.frame = CGRect(x: (max(trackStart, knobX) - 5).rounded(), y: r.midY - 7, width: 10, height: 14)
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

    @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        handleDrag(at: recognizer.location(in: self))
    }

    func handleTap(at point: CGPoint) {
        guard let model = currentModel else { return }
        if model.layout.playPause.contains(point) && model.media.canPlayPause {
            onTogglePlayPause?()
            return
        }
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
        if celestialRect(model.celestial).insetBy(dx: -Self.tapSlop, dy: -Self.tapSlop).contains(point) {
            revealClock()
            return
        }
        if model.pet.hitRect(spriteSize: PetSprites.cellSize).insetBy(dx: -Self.tapSlop, dy: -Self.tapSlop).contains(point) {
            onPetTap?()
            return
        }
        if model.layout.middle.contains(point) {
            onGroundTap?(point.x)
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
