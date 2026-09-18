import AppKit
import SnappyNestCore
import XCTest
@testable import SnappyNestUI

final class SpriteRenderTests: XCTestCase {
    private let scale: CGFloat = 2

    private func isNonEmpty(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data as Data? else { return false }
        // Any non-zero alpha byte means something was drawn.
        return data.enumerated().contains { idx, byte in idx % 4 == 3 && byte != 0 }
    }

    func testEveryPetClipFrameRendersInsideTheCell() {
        for action in PetAction.allCases {
            for frame in 0..<action.frameCount {
                for facing in [PetFacing.left, .right] {
                    let img = PetSprites.image(action: action, frame: frame, facing: facing, scale: scale)
                    XCTAssertEqual(CGFloat(img.width), PetSprites.cellSize.width * scale, "\(action) frame \(frame)")
                    XCTAssertEqual(CGFloat(img.height), PetSprites.cellSize.height * scale)
                    XCTAssertTrue(isNonEmpty(img), "\(action) frame \(frame) \(facing) drew nothing")
                    XCTAssertGreaterThanOrEqual(PetSprites.lift(action: action, frame: frame), 0)
                }
            }
        }
    }

    func testPetImagesAreCachedPerFrame() {
        let a = PetSprites.image(action: .walk, frame: 0, facing: .right, scale: scale)
        let b = PetSprites.image(action: .walk, frame: 2, facing: .right, scale: scale)  // 2 % frameCount == 0
        XCTAssertTrue(a === b)
        let c = PetSprites.image(action: .walk, frame: 1, facing: .right, scale: scale)
        XCTAssertFalse(a === c)
    }

    func testBatteryGlyphStates() {
        for snap in [
            BatterySnapshot(isPresent: true, percentage: 0, isCharging: false),
            BatterySnapshot(isPresent: true, percentage: 0.15, isCharging: false),
            BatterySnapshot(isPresent: true, percentage: 0.5, isCharging: true),
            BatterySnapshot(isPresent: true, percentage: 1, isCharging: false),
            .unavailable
        ] {
            let img = BatteryGlyph.image(snapshot: snap, scale: scale)
            XCTAssertEqual(CGFloat(img.width), BatteryGlyph.size.width * scale)
            XCTAssertTrue(isNonEmpty(img))
        }
        XCTAssertEqual(BatteryGlyph.fillColor(percentage: 0.1), Palette.batteryLow)
        XCTAssertEqual(BatteryGlyph.fillColor(percentage: 0.2), Palette.golden)
        XCTAssertEqual(BatteryGlyph.fillColor(percentage: 0.9), Palette.batteryFill)
    }

    func testControlGlyphStates() {
        let images = [
            ControlGlyphs.brightness(available: true, scale: scale),
            ControlGlyphs.brightness(available: false, scale: scale),
            ControlGlyphs.volume(level: 0, muted: false, available: true, scale: scale),
            ControlGlyphs.volume(level: 0.3, muted: false, available: true, scale: scale),
            ControlGlyphs.volume(level: 0.8, muted: false, available: true, scale: scale),
            ControlGlyphs.volume(level: 0.8, muted: true, available: true, scale: scale),
            ControlGlyphs.volume(level: 0.8, muted: false, available: false, scale: scale)
        ]
        for img in images { XCTAssertTrue(isNonEmpty(img)) }
        // Level buckets share one cached image; different buckets do not.
        XCTAssertTrue(ControlGlyphs.volume(level: 0.3, muted: false, available: true, scale: scale)
                      === ControlGlyphs.volume(level: 0.45, muted: false, available: true, scale: scale))
        XCTAssertFalse(ControlGlyphs.volume(level: 0.3, muted: false, available: true, scale: scale)
                       === ControlGlyphs.volume(level: 0.8, muted: false, available: true, scale: scale))
    }

    func testSignpostGlyphStates() {
        for available in [true, false] {
            XCTAssertTrue(isNonEmpty(SignpostGlyphs.image(.previous, available: available, scale: scale)))
            XCTAssertTrue(isNonEmpty(SignpostGlyphs.image(.next, available: available, scale: scale)))
            XCTAssertTrue(isNonEmpty(SignpostGlyphs.image(.playPause, isPlaying: true, available: available, scale: scale)))
            XCTAssertTrue(isNonEmpty(SignpostGlyphs.image(.playPause, isPlaying: false, available: available, scale: scale)))
        }
        XCTAssertTrue(SignpostGlyphs.image(.next, available: true, scale: scale)
                      === SignpostGlyphs.image(.next, available: true, scale: scale), "cached")
    }

    func testHardHatClipsDifferFromTheBareClips() {
        let bare = PetSprites.image(action: .idle, frame: 0, facing: .right, scale: scale)
        let hat = PetSprites.image(action: .tinker, frame: 0, facing: .right, scale: scale)
        XCTAssertNotEqual(bare.dataProvider?.data as Data?, hat.dataProvider?.data as Data?)
        // The hat lands over four frames: the last suit-up frame is the tinker pose's hat height.
        XCTAssertTrue(isNonEmpty(PetSprites.image(action: .suitUp, frame: 3, facing: .left, scale: scale)))
    }

    func testTimeStringFormatsMinutesAndSeconds() {
        XCTAssertEqual(SceneRenderer.timeString(0), "0:00")
        XCTAssertEqual(SceneRenderer.timeString(65.9), "1:05")
        XCTAssertEqual(SceneRenderer.timeString(3599), "59:59")
        XCTAssertEqual(SceneRenderer.timeString(nil), "–:––")
        XCTAssertEqual(SceneRenderer.timeString(-1), "–:––")
    }

    func testSkyImageMatchesBoundsAndKeyChangesPerMinute() {
        let regions = LayoutEngine(bounds: CGRect(x: 0, y: 0, width: 1004, height: 30), backingScale: scale).regions
        let noon = WorldTime(hour: 12, minute: 0, second: 0)
        let img = SkyPainter.sky(size: regions.full.size, time: noon, scale: scale)
        XCTAssertEqual(img.width, 2008)
        XCTAssertEqual(img.height, 60)
        let terrain = SkyPainter.terrain(size: regions.middle.size, time: noon, scale: scale)
        XCTAssertEqual(CGFloat(terrain.width), regions.middle.width * scale)
        XCTAssertTrue(isNonEmpty(terrain))
        let k1 = SkyPainter.Key(time: noon, size: regions.full.size, scale: scale)
        let k2 = SkyPainter.Key(time: WorldTime(hour: 12, minute: 0, second: 30), size: regions.full.size, scale: scale)
        let k3 = SkyPainter.Key(time: WorldTime(hour: 12, minute: 1, second: 0), size: regions.full.size, scale: scale)
        XCTAssertEqual(k1, k2)
        XCTAssertNotEqual(k1, k3)
    }
}
