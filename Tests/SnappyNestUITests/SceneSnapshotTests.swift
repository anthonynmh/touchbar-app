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
                        let img = PetSprites.image(action: action, frame: frame, facing: facing, scale: scale)
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
        try write(image, to: dir.appendingPathComponent("pet-clips.png"))
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
    }

    private func snapshot(_ view: NSView) throws -> CGImage {
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 4 * w,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
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
