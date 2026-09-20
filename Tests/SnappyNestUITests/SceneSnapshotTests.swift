import AppKit
import SnappyNestCore
import XCTest
@testable import SnappyNestUI

/// Visual-inspection aid. Skipped unless `SNAPPY_SNAPSHOT_DIR` is set, in
/// which case it writes PNGs of the composed strip at several hours and of
/// every pet clip so the artwork can be reviewed as images.
final class SceneSnapshotTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1004, height: 30)
    private let scale: CGFloat = 2

    private var outputDir: URL? {
        guard let dir = ProcessInfo.processInfo.environment["SNAPPY_SNAPSHOT_DIR"], !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: dir, isDirectory: true)
    }

    func testWritePetClipSheet() throws {
        guard let dir = outputDir else { throw XCTSkip("SNAPPY_SNAPSHOT_DIR not set") }
        for species in PetSpecies.allCases {
            try writePetClipSheet(species, to: dir)
        }
    }

    private func writePetClipSheet(_ species: PetSpecies, to dir: URL) throws {
        let cell = PetSprites.cellSize
        let actions = PetAction.allCases
        let maxFrames = actions.map(\.frameCount).max() ?? 1
        let columns = maxFrames * 2 // right-facing then left-facing
        let sheetSize = CGSize(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(actions.count))
        let image = PetSprites.render(size: sheetSize, scale: scale * 4) { ctx in
            ctx.setFillColor(CGColor(gray: 0.35, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: sheetSize))
            for (row, action) in actions.enumerated() {
                for frame in 0..<action.frameCount {
                    for (side, facing) in [PetFacing.right, .left].enumerated() {
                        let img = PetSprites.image(species: species, action: action, frame: frame, facing: facing, scale: scale)
                        let x = cell.width * CGFloat(frame + side * maxFrames)
                        let y = cell.height * CGFloat(row)
                        ctx.saveGState()
                        ctx.translateBy(x: x, y: y + cell.height)
                        ctx.scaleBy(x: 1, y: -1)
                        ctx.draw(img, in: CGRect(origin: .zero, size: cell))
                        ctx.restoreGState()
                    }
                }
            }
        }
        try write(image, to: dir.appendingPathComponent("pet-clips-\(species.rawValue).png"))
    }

    func testWriteGlyphSheet() throws {
        guard let dir = outputDir else { throw XCTSkip("SNAPPY_SNAPSHOT_DIR not set") }
        let batteries: [BatterySnapshot] = [
            BatterySnapshot(isPresent: true, percentage: 0.0, isCharging: false),
            BatterySnapshot(isPresent: true, percentage: 0.12, isCharging: false),
            BatterySnapshot(isPresent: true, percentage: 0.3, isCharging: true),
            BatterySnapshot(isPresent: true, percentage: 0.5, isCharging: false),
            BatterySnapshot(isPresent: true, percentage: 1.0, isCharging: true),
            .unavailable
        ]
        let controls: [CGImage] = [
            ControlGlyphs.brightness(available: true, scale: scale),
            ControlGlyphs.brightness(available: false, scale: scale),
            ControlGlyphs.volume(level: 0, muted: false, available: true, scale: scale),
            ControlGlyphs.volume(level: 0.3, muted: false, available: true, scale: scale),
            ControlGlyphs.volume(level: 0.8, muted: false, available: true, scale: scale),
            ControlGlyphs.volume(level: 0.8, muted: true, available: true, scale: scale),
            ControlGlyphs.volume(level: 0.8, muted: false, available: false, scale: scale),
            SignpostGlyphs.image(.previous, available: true, scale: scale),
            SignpostGlyphs.image(.playPause, isPlaying: true, available: true, scale: scale),
            SignpostGlyphs.image(.playPause, isPlaying: false, available: true, scale: scale),
            SignpostGlyphs.image(.next, available: true, scale: scale),
            SignpostGlyphs.image(.next, available: false, scale: scale)
        ]
        let banners = [
            TitleBannerGlyph.image(width: 120, available: true, scale: scale),
            TitleBannerGlyph.image(width: 120, available: false, scale: scale)
        ]
        let sheet = CGSize(width: 32 * CGFloat(max(batteries.count, controls.count)), height: 100)
        let image = PetSprites.render(size: sheet, scale: scale * 3) { ctx in
            ctx.setFillColor(CGColor(gray: 0.25, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: sheet))
            func blit(_ img: CGImage, at origin: CGPoint) {
                let size = CGSize(width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
                ctx.saveGState()
                ctx.translateBy(x: origin.x, y: origin.y + size.height)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(img, in: CGRect(origin: .zero, size: size))
                ctx.restoreGState()
            }
            for (i, b) in batteries.enumerated() {
                blit(BatteryGlyph.image(snapshot: b, scale: scale), at: CGPoint(x: 2 + 32 * CGFloat(i), y: 8))
            }
            for (i, c) in controls.enumerated() {
                blit(c, at: CGPoint(x: 2 + 32 * CGFloat(i), y: 36))
            }
            for (i, b) in banners.enumerated() {
                blit(b, at: CGPoint(x: 2 + 130 * CGFloat(i), y: 66))
            }
        }
        try write(image, to: dir.appendingPathComponent("glyphs.png"))
    }

    func testWriteSceneAtSeveralHours() throws {
        guard let dir = outputDir else { throw XCTSkip("SNAPPY_SNAPSHOT_DIR not set") }
        let layout = LayoutEngine(bounds: bounds, backingScale: scale)
        let composer = SceneComposer(layout: layout)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let renderer = SceneRenderer(frame: bounds)
        let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = renderer

        for (hour, minute) in [(3, 0), (6, 0), (7, 30), (9, 0), (12, 0), (17, 30), (18, 0), (21, 0)] {
            var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 21
            comps.hour = hour; comps.minute = minute
            let now = cal.date(from: comps)!
            let pet = PetState(action: .idle, facing: .right,
                               position: CGPoint(x: layout.regions.middle.midX - 60, y: layout.regions.middle.maxY - 4),
                               frameIndex: 0)
            let media = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 40, duration: 120,
                                      elapsedAt: now, rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
            let model = composer.compose(
                now: now, calendar: cal, pet: pet,
                battery: BatterySnapshot(isPresent: true, percentage: hour == 3 ? 0.12 : 0.87, isCharging: hour == 9),
                brightness: (0.6, true), volume: (0.35, hour == 21, true), media: media
            )
            renderer.update(model: model)
            let image = try snapshot(renderer)
            try write(image, to: dir.appendingPathComponent(String(format: "scene-%02d%02d.png", hour, minute)))
        }

        // The controls page at noon and at night, with the hard-hat pet beside the cluster.
        for hour in [12, 22] {
            var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 21; comps.hour = hour
            let now = cal.date(from: comps)!
            let controls = SceneComposer(layout: layout.with(page: .controls))
            let pet = PetState(action: .tinker, facing: .right,
                               position: CGPoint(x: controls.layout.regions.brightness.minX - PetController.workshopGap,
                                                 y: bounds.maxY - 4),
                               frameIndex: hour == 12 ? 1 : 0)
            let model = controls.compose(
                now: now, calendar: cal, pet: pet,
                battery: BatterySnapshot(isPresent: true, percentage: 0.64, isCharging: hour == 22),
                brightness: (0.6, true), volume: (0.35, false, true),
                media: MediaSnapshot(identity: "spotify", state: .playing, elapsed: 40, duration: 120,
                                     elapsedAt: now, rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
            )
            renderer.update(model: model)
            try write(try snapshot(renderer), to: dir.appendingPathComponent(String(format: "controls-%02d00.png", hour)))
        }

        // The playback page: following a track by day (short title), a long
        // browser title in the evening, and nothing playing at night.
        let titles = [12: "passport", 17: "honestav & mgk - Crash First (OFFICIAL MUSIC VIDEO) [4K Remaster]"]
        for (hour, playing) in [(12, true), (17, true), (21, false)] {
            var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 21; comps.hour = hour
            let now = cal.date(from: comps)!
            let playback = SceneComposer(layout: layout.with(page: .playback))
            let media = playing
                ? MediaSnapshot(identity: "spotify", state: .playing, elapsed: 83, duration: 214, elapsedAt: now, rate: 1,
                                title: titles[hour],
                                canPlayPause: true, canReadPosition: true, canReadDuration: true, canSeek: true, canSkip: true)
                : MediaSnapshot(identity: "spotify", state: .stopped, canPlayPause: true)
            let x = playing ? layout.trailX(fraction: 83.0 / 214.0, spriteHalfWidth: 12)
                            : layout.trailX(fraction: 0, spriteHalfWidth: 12)
            let pet = PetState(action: playing ? .progressFollow : .sleep, facing: .right,
                               position: CGPoint(x: x, y: bounds.maxY - 4), frameIndex: 1)
            let model = playback.compose(
                now: now, calendar: cal, pet: pet,
                battery: BatterySnapshot(isPresent: true, percentage: 0.64, isCharging: false),
                brightness: (0.6, true), volume: (0.35, false, true), media: media
            )
            renderer.update(model: model)
            try write(try snapshot(renderer), to: dir.appendingPathComponent(String(format: "playback-%02d00.png", hour)))
        }
    }

    /// The world page with keep-away in progress: the ball rolled out of the
    /// nook, the pet mid-chase and the round pill up; then the loss.
    func testWriteKeepAwayScene() throws {
        guard let dir = outputDir else { throw XCTSkip("SNAPPY_SNAPSHOT_DIR not set") }
        let layout = LayoutEngine(bounds: bounds, backingScale: scale)
        let composer = SceneComposer(layout: layout)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let renderer = SceneRenderer(frame: bounds)
        let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = renderer
        var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 21; comps.hour = 15
        let now = cal.date(from: comps)!
        renderer.now = { now.addingTimeInterval(4) }

        let middle = layout.regions.middle
        var game = KeepAwayGame(arena: middle, nookX: SceneLayout.nookX(inside: middle), now: now)
        for i in 0...10 {
            _ = game.tick(dt: 0.125, now: now.addingTimeInterval(1 + 0.125 * Double(i)), petX: middle.midX + 100)
        }
        let chasing = PetState(action: .dash, facing: .left,
                               position: CGPoint(x: game.ballX + 70, y: middle.maxY - 4), frameIndex: 1)
        let mid = composer.compose(
            now: now, calendar: cal, pet: chasing,
            battery: BatterySnapshot(isPresent: true, percentage: 0.64, isCharging: false),
            brightness: (0.6, true), volume: (0.35, false, true), media: .unknown,
            game: game, gameBestRounds: 2
        )
        renderer.update(model: mid)
        try write(try snapshot(renderer), to: dir.appendingPathComponent("keepaway-chase.png"))

        var lost = game
        let landing = lost.ballX + lost.ballVX * 0.125
        XCTAssertEqual(lost.tick(dt: 0.125, now: now.addingTimeInterval(3), petX: landing), .caught)
        let caught = PetState(action: .celebrate, facing: .left,
                              position: CGPoint(x: lost.ballX + 4, y: middle.maxY - 4), frameIndex: 1)
        let over = composer.compose(
            now: now, calendar: cal, pet: caught,
            battery: BatterySnapshot(isPresent: true, percentage: 0.64, isCharging: false),
            brightness: (0.6, true), volume: (0.35, false, true), media: .unknown,
            game: lost, gameBestRounds: 2
        )
        renderer.update(model: over)
        try write(try snapshot(renderer), to: dir.appendingPathComponent("keepaway-caught.png"))
    }

    private func snapshot(_ view: NSView) throws -> CGImage {
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 4 * w,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // The view is flipped; CALayer.render(in:) applies that flip, so undo
        // it here to capture what the Touch Bar actually shows.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        view.layer!.render(in: ctx)
        return try XCTUnwrap(ctx.makeImage())
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
        print("[snapshot] wrote \(url.path)")
    }
}
