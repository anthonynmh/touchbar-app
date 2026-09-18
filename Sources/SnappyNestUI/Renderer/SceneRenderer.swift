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

    // Layers (documented in the plan).
    private let skyLayer = CALayer()
    private let hourTickLayer = CAShapeLayer()
    private let celestialLayer = CALayer()
    private let celestialMirrorLayer = CALayer()   // for the moon-midnight seam
    private let sceneryContainer = CALayer()
    private let progressTrailLayer = CAShapeLayer()
    private let petLayer = CALayer()

    private let batteryContainer = CALayer()
    private let brightnessLayer = CAShapeLayer()
    private let brightnessKnob = CALayer()
    private let volumeLayer = CAShapeLayer()
    private let volumeKnob = CALayer()
    private let playPauseLayer = CALayer()

    private var backingScale: CGFloat = 2.0
    private var cachedSkyImage: CGImage?
    private var currentModel: SceneModel?

    // Callbacks — the presenter wires these to the volume/brightness/media
    // providers when the user drags a control or taps play/pause.
    public var onBrightnessChange: ((Double) -> Void)?
    public var onVolumeChange:     ((Double) -> Void)?
    public var onTogglePlayPause:  (() -> Void)?

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
        cachedSkyImage = nil
        if let m = currentModel { update(model: m) }
    }

    public override func layout() {
        super.layout()
        cachedSkyImage = nil
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

        for l in [skyLayer, sceneryContainer, progressTrailLayer,
                  celestialLayer, celestialMirrorLayer, petLayer,
                  batteryContainer, brightnessLayer, brightnessKnob,
                  volumeLayer, volumeKnob, playPauseLayer, hourTickLayer] {
            l.contentsScale = backingScale
            l.magnificationFilter = .nearest
            l.minificationFilter = .nearest
            l.isOpaque = false
            layer?.addSublayer(l)
        }

        // Cyan trail styling
        progressTrailLayer.strokeColor = Palette.cyan.copy(alpha: 0.55)
        progressTrailLayer.lineWidth = 1.0
        progressTrailLayer.fillColor = nil
        progressTrailLayer.lineCap = .round

        hourTickLayer.strokeColor = CGColor(gray: 1.0, alpha: 0.25)
        hourTickLayer.lineWidth = 1.0

        brightnessLayer.strokeColor = Palette.golden.copy(alpha: 0.75)
        brightnessLayer.lineWidth = 4.0
        brightnessLayer.lineCap = .round
        volumeLayer.strokeColor = Palette.cyan.copy(alpha: 0.75)
        volumeLayer.lineWidth = 4.0
        volumeLayer.lineCap = .round
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
        paintHourTicks(regions: model.layout)
        paintCelestial(pos: model.celestial)
        paintScenery(model.props, regions: model.layout)
        paintProgressTrail(regions: model.layout, fraction: model.progressFraction)
        paintPet(state: model.pet, regions: model.layout)
        paintBattery(model.battery, regions: model.layout)
        paintBrightness(value: model.brightness, available: model.brightnessAvailable, regions: model.layout)
        paintVolume(value: model.volume, muted: model.volumeMuted, available: model.volumeAvailable, regions: model.layout)
        paintPlayPause(media: model.media, regions: model.layout)
        CATransaction.commit()
    }

    // MARK: - Sky + hour ticks

    private func paintSky(regions: LayoutEngine.Regions, time: WorldTime) {
        skyLayer.frame = regions.full
        if cachedSkyImage == nil {
            cachedSkyImage = makeSkyImage(size: regions.full.size, backingScale: backingScale)
        }
        skyLayer.contents = cachedSkyImage
    }

    private func makeSkyImage(size: CGSize, backingScale: CGFloat) -> CGImage {
        let w = Int(size.width * backingScale)
        let h = Int(size.height * backingScale)
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: 4 * w, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Horizontal color-band gradient from Palette.sky24 with darker
        // ground band along the bottom (~40 % height).
        let bands = Palette.sky24
        let bandCount = bands.count
        for xPix in 0..<w {
            let f = Double(xPix) / Double(w)
            let idx = f * Double(bandCount)
            let a = Int(idx) % bandCount
            let b = (a + 1) % bandCount
            let t = idx - Double(Int(idx))
            let ca = bands[a].components ?? [0, 0, 0, 1]
            let cb = bands[b].components ?? [0, 0, 0, 1]
            let lerp = (0..<4).map { i in ca[i] * (1 - t) + cb[i] * t }
            let color = CGColor(red: lerp[0], green: lerp[1], blue: lerp[2], alpha: lerp[3])
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: xPix, y: 0, width: 1, height: Int(Double(h) * 0.65)))
        }
        // Ground band along the bottom in flipped view coords means low y at top,
        // but our CGContext is bottom-origin — so the bottom of the CGContext maps
        // to the bottom of the view.
        ctx.setFillColor(Palette.ground)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: Int(Double(h) * 0.35)))
        return ctx.makeImage()!
    }

    private func paintHourTicks(regions: LayoutEngine.Regions) {
        let path = CGMutablePath()
        for hour in 0...24 {
            let x = regions.full.minX + regions.full.width * CGFloat(hour) / 24.0
            let strong = (hour % 6 == 0)
            let y0: CGFloat = 1
            let y1: CGFloat = strong ? 5 : 3
            path.move(to: CGPoint(x: x, y: y0))
            path.addLine(to: CGPoint(x: x, y: y1))
        }
        hourTickLayer.frame = regions.full
        hourTickLayer.path = path
    }

    // MARK: - Celestial

    private func paintCelestial(pos: CelestialPosition) {
        let img: CGImage
        let size: CGSize
        switch pos.body {
        case .sun:
            img = PlaceholderSprites.sunImage(scale: backingScale)
            size = CGSize(width: 14, height: 14)
        case .moon:
            img = PlaceholderSprites.moonImage(scale: backingScale)
            size = CGSize(width: 12, height: 12)
        }
        celestialLayer.contents = img
        celestialLayer.frame = CGRect(x: pos.point.x - size.width/2, y: pos.point.y - size.height/2, width: size.width, height: size.height)

        if let mirror = pos.seamMirror {
            celestialMirrorLayer.contents = img
            celestialMirrorLayer.frame = CGRect(x: mirror.x - size.width/2, y: mirror.y - size.height/2, width: size.width, height: size.height)
            celestialMirrorLayer.isHidden = false
        } else {
            celestialMirrorLayer.isHidden = true
        }
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
        for (idx, obj) in objs.enumerated() {
            let layer = sceneryLayers[idx]
            layer.contents = PlaceholderSprites.propImage(prop: obj.prop.rawValue, scale: backingScale)
            let size = CGSize(width: 10, height: 10)
            layer.frame = CGRect(x: obj.position.x - size.width/2,
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
        let y = m.midY + 4
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
        let x = state.position.x - size.width / 2
        let y = state.position.y - size.height - lift
        petLayer.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: - Battery

    private var batterySegments: [CALayer] = []
    private var chargingBolt: CATextLayer?

    private func paintBattery(_ snap: BatterySnapshot, regions: LayoutEngine.Regions) {
        let r = regions.battery.insetBy(dx: 6, dy: 8)
        batteryContainer.frame = regions.battery
        let segCount = 6
        while batterySegments.count < segCount {
            let l = CALayer()
            l.cornerRadius = 1
            batteryContainer.addSublayer(l)
            batterySegments.append(l)
        }
        let pct = snap.percentage ?? 0
        let gap: CGFloat = 1
        let segW = (r.width - gap * CGFloat(segCount - 1)) / CGFloat(segCount)
        for (i, seg) in batterySegments.enumerated() {
            let filled = Double(i + 1) / Double(segCount) <= pct + 1e-6
            let color: CGColor
            if snap.percentage == nil { color = Palette.unavailableTint }
            else if !filled            { color = Palette.batteryEmpty }
            else if pct < 0.2          { color = Palette.batteryLow }
            else                       { color = Palette.batteryFill }
            seg.backgroundColor = color
            seg.frame = CGRect(
                x: r.minX + (segW + gap) * CGFloat(i) - regions.battery.minX,
                y: r.minY - regions.battery.minY,
                width: segW, height: r.height
            )
        }
        if snap.isCharging {
            let bolt = chargingBolt ?? {
                let t = CATextLayer()
                t.string = "⚡"
                t.font = NSFont.systemFont(ofSize: 10) as CFTypeRef
                t.fontSize = 10
                t.foregroundColor = Palette.golden
                t.alignmentMode = .center
                t.contentsScale = backingScale
                batteryContainer.addSublayer(t)
                chargingBolt = t
                return t
            }()
            bolt.frame = CGRect(x: r.minX - regions.battery.minX + r.width/2 - 6,
                                y: r.minY - regions.battery.minY - 1,
                                width: 12, height: 14)
            bolt.isHidden = false
        } else {
            chargingBolt?.isHidden = true
        }
    }

    // MARK: - Brightness / Volume / Play-Pause

    private func paintBrightness(value: Double, available: Bool, regions: LayoutEngine.Regions) {
        let r = regions.brightness.insetBy(dx: 8, dy: 8)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX, y: r.midY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        brightnessLayer.path = path
        brightnessLayer.strokeColor = available ? Palette.golden.copy(alpha: 0.75) : Palette.unavailableTint
        brightnessLayer.frame = regions.full
        let knobX = r.minX + (r.width * CGFloat(value))
        brightnessKnob.backgroundColor = available ? Palette.cream : Palette.unavailableTint
        brightnessKnob.frame = CGRect(x: knobX - 3, y: r.midY - 4, width: 6, height: 8)
        brightnessKnob.cornerRadius = 2
    }

    private func paintVolume(value: Double, muted: Bool, available: Bool, regions: LayoutEngine.Regions) {
        let r = regions.volume.insetBy(dx: 8, dy: 8)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX, y: r.midY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        volumeLayer.path = path
        volumeLayer.strokeColor = (available && !muted) ? Palette.cyan.copy(alpha: 0.75) : Palette.unavailableTint
        volumeLayer.frame = regions.full
        let displayed = muted ? 0 : value
        let knobX = r.minX + (r.width * CGFloat(displayed))
        volumeKnob.backgroundColor = available ? Palette.cream : Palette.unavailableTint
        volumeKnob.frame = CGRect(x: knobX - 3, y: r.midY - 4, width: 6, height: 8)
        volumeKnob.cornerRadius = 2
    }

    private func paintPlayPause(media: MediaSnapshot, regions: LayoutEngine.Regions) {
        let r = regions.playPause
        playPauseLayer.frame = r
        if !media.canPlayPause {
            playPauseLayer.isHidden = true
            return
        }
        playPauseLayer.isHidden = false
        let image = playPauseImage(isPlaying: media.state == .playing, size: r.size, scale: backingScale)
        playPauseLayer.contents = image
    }

    private func playPauseImage(isPlaying: Bool, size: CGSize, scale: CGFloat) -> CGImage {
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: 4 * w, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(Palette.cream)
        if isPlaying {
            // Two pause rectangles
            ctx.fill(CGRect(x: size.width * 0.32, y: size.height * 0.25, width: 3, height: size.height * 0.5))
            ctx.fill(CGRect(x: size.width * 0.55, y: size.height * 0.25, width: 3, height: size.height * 0.5))
        } else {
            // Play triangle
            ctx.beginPath()
            ctx.move(to: CGPoint(x: size.width * 0.35, y: size.height * 0.25))
            ctx.addLine(to: CGPoint(x: size.width * 0.35, y: size.height * 0.75))
            ctx.addLine(to: CGPoint(x: size.width * 0.65, y: size.height * 0.5))
            ctx.closePath()
            ctx.fillPath()
        }
        return ctx.makeImage()!
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
            let f = fraction(x: point.x, in: model.layout.brightness.insetBy(dx: 8, dy: 8))
            onBrightnessChange?(f)
            return
        }
        if model.layout.volume.contains(point) && model.volumeAvailable {
            let f = fraction(x: point.x, in: model.layout.volume.insetBy(dx: 8, dy: 8))
            onVolumeChange?(f)
            return
        }
    }

    func handleDrag(at point: CGPoint) {
        guard let model = currentModel else { return }
        if model.layout.brightness.contains(point) && model.brightnessAvailable {
            let f = fraction(x: point.x, in: model.layout.brightness.insetBy(dx: 8, dy: 8))
            onBrightnessChange?(f)
            return
        }
        if model.layout.volume.contains(point) && model.volumeAvailable {
            let f = fraction(x: point.x, in: model.layout.volume.insetBy(dx: 8, dy: 8))
            onVolumeChange?(f)
            return
        }
    }

    private func fraction(x: CGFloat, in rect: CGRect) -> Double {
        Double(min(1.0, max(0.0, (x - rect.minX) / max(1e-6, rect.width))))
    }
}
