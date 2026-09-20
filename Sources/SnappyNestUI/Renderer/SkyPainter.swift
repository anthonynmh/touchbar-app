import AppKit
import CoreGraphics
import SnappyNestCore

/// Paints the live environment for a given wall-clock time: a vertical sky
/// gradient keyed by hour with stars that fade with daylight and a warm
/// horizon glow at dawn/dusk (`sky`), plus hill silhouettes and grassy ground
/// for the world's middle region (`terrain`).
///
/// Both change at most once per minute, so the renderer caches them by
/// `SkyPainter.Key`.
public enum SkyPainter {
    public struct Key: Hashable {
        public let minuteOfDay: Int
        public let sunriseMinute: Int
        public let sunsetMinute: Int
        public let width: Int
        public let height: Int
        public let scale: CGFloat
        public init(time: WorldTime, size: CGSize, scale: CGFloat) {
            minuteOfDay = time.hour * 60 + time.minute
            sunriseMinute = Int(time.schedule.sunriseMinutes.rounded())
            sunsetMinute = Int(time.schedule.sunsetMinutes.rounded())
            width = Int(size.width.rounded())
            height = Int(size.height.rounded())
            self.scale = scale
        }
    }

    /// RGB triple in 0…1.
    private struct RGB {
        var r: Double, g: Double, b: Double
        init(_ hex: UInt32) {
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
        }
        init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
        func mix(_ o: RGB, _ t: Double) -> RGB {
            RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
        }
        func scaled(_ k: Double) -> RGB { RGB(r: r * k, g: g * k, b: b * k) }
        func cg(alpha: Double = 1) -> CGColor {
            CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(alpha))
        }
    }

    /// Where a colour keyframe sits relative to the day's schedule.
    private enum Anchor {
        case midnight, sunrise(Double), noon, sunset(Double), endOfDay

        /// Hour of day for `schedule`. Offsets are clamped so the keyframes
        /// stay ordered even on very short days or nights.
        func hour(in schedule: SolarSchedule) -> Double {
            let rise = schedule.sunriseMinutes / 60
            let set = schedule.sunsetMinutes / 60
            let noon = schedule.solarNoonMinutes / 60
            let halfDay = (set - rise) / 2
            switch self {
            case .midnight: return 0
            case .endOfDay: return 24
            case .noon: return noon
            case .sunrise(let offset):
                if offset >= 0 { return rise + min(offset, halfDay * 0.9) }
                return max(rise + offset, rise / 2)
            case .sunset(let offset):
                if offset <= 0 { return set + max(offset, -halfDay * 0.9) }
                return min(set + offset, set + (24 - set) / 2)
            }
        }
    }

    /// Colour keyframes anchored to sunrise/sunset; interpolated linearly.
    /// With `.stylized` (06:00 / 18:00) these fall at 0, 4, 5.5, 6.5, 8, 12,
    /// 16, 17.5, 18.5, 20 and 24 hours.
    private static let keyframes: [(anchor: Anchor, zenith: RGB, horizon: RGB)] = [
        (.midnight,      RGB(0x070B1E), RGB(0x141C3A)),
        (.sunrise(-2.0), RGB(0x0B1230), RGB(0x1E2A4E)),
        (.sunrise(-0.5), RGB(0x1B2A55), RGB(0x6B4B5A)),
        (.sunrise(0.5),  RGB(0x4A78B5), RGB(0xF2A65A)),
        (.sunrise(2.0),  RGB(0x5FA3DB), RGB(0xBFE0F2)),
        (.noon,          RGB(0x3D8BD9), RGB(0xA8D8F0)),
        (.sunset(-2.0),  RGB(0x4A8FCF), RGB(0xD7C79A)),
        (.sunset(-0.5),  RGB(0x4C6FA8), RGB(0xF28C4A)),
        (.sunset(0.5),   RGB(0x202C5C), RGB(0x7A4A62)),
        (.sunset(2.0),   RGB(0x0D1637), RGB(0x2A3560)),
        (.endOfDay,      RGB(0x070B1E), RGB(0x141C3A))
    ]

    private static func skyColors(at time: WorldTime) -> (zenith: RGB, horizon: RGB) {
        let keyframes = Self.keyframes.map { (hour: $0.anchor.hour(in: time.schedule), zenith: $0.zenith, horizon: $0.horizon) }
        let h = time.minutesOfDay / 60
        var i = 0
        while i + 1 < keyframes.count && keyframes[i + 1].hour < h { i += 1 }
        let a = keyframes[i], b = keyframes[min(i + 1, keyframes.count - 1)]
        let span = max(1e-6, b.hour - a.hour)
        let t = min(1, max(0, (h - a.hour) / span))
        return (a.zenith.mix(b.zenith, t), a.horizon.mix(b.horizon, t))
    }

    /// Vertical position of the horizon (top of the far hills) in points.
    public static let horizonY: CGFloat = 17
    /// Top of the ground band in points; the pet's feet sit at `maxY - 4`.
    public static let groundY: CGFloat = 23

    /// Sky backdrop for the full strip: gradient, stars, and twilight glow.
    public static func sky(size: CGSize, time: WorldTime, scale: CGFloat) -> CGImage {
        PetSprites.render(size: size, scale: scale) { ctx in
            ctx.setShouldAntialias(true)
            let full = CGRect(origin: .zero, size: size)
            let (zenith, horizon) = skyColors(at: time)
            let daylight = time.daylight
            let twilight = time.twilight

            drawVerticalGradient(ctx, in: full, top: zenith.cg(), bottom: horizon.cg())

            // Stars, fading with daylight. Seeded so they never jitter.
            if daylight < 0.98 {
                var rng = SeededRandom(seed: 0x5EED_5747)
                let starAlpha = 1 - daylight
                for i in 0..<70 {
                    let x = CGFloat(rng.nextDouble()) * full.width
                    let y = CGFloat(rng.nextDouble()) * (horizonY - 2)
                    let twinkle = (i + time.minute) % 7 == 0 ? 0.35 : 1.0
                    let bright = rng.nextDouble() < 0.25
                    ctx.setFillColor(CGColor(gray: 1, alpha: CGFloat(starAlpha * twinkle * (bright ? 0.95 : 0.55))))
                    let s: CGFloat = bright ? 1.5 : 1
                    ctx.fill(CGRect(x: x, y: y, width: s, height: s))
                }
            }

            // Warm glow hugging the horizon at dawn/dusk.
            if twilight > 0.01 {
                let glow = RGB(0xFFB15E)
                drawVerticalGradient(ctx, in: CGRect(x: 0, y: horizonY - 9, width: full.width, height: 10),
                                     top: glow.cg(alpha: 0), bottom: glow.cg(alpha: 0.55 * twilight))
            }
        }
    }

    /// Hills and grass for the world's middle region, drawn at the origin of
    /// a bitmap `size` wide (the layer is placed at the region's frame).
    ///
    /// `xOffset` shifts the hill phase and the tuft seed so a second terrain
    /// placed to the right continues the ridge line instead of repeating it.
    public static func terrain(size: CGSize, time: WorldTime, scale: CGFloat, xOffset: CGFloat = 0) -> CGImage {
        PetSprites.render(size: size, scale: scale) { ctx in
            ctx.setShouldAntialias(true)
            let m = CGRect(origin: .zero, size: size)
            ctx.saveGState()
            ctx.translateBy(x: -xOffset, y: 0)
            let shifted = m.offsetBy(dx: xOffset, dy: 0)
            let (_, horizon) = skyColors(at: time)
            let night = 1 - time.daylight

            let farHill = horizon.mix(RGB(0x2F6B3A), 0.45).scaled(0.75 - 0.35 * night)
            let nearHill = horizon.mix(RGB(0x2A5A32), 0.6).scaled(0.6 - 0.3 * night)
            drawHills(ctx, in: shifted, baseY: groundY + 2, crest: horizonY, amplitude: 3.5, frequency: 0.045, phase: 0.8, color: farHill.cg())
            drawHills(ctx, in: shifted, baseY: groundY + 2, crest: horizonY + 3, amplitude: 2.5, frequency: 0.08, phase: 2.9, color: nearHill.cg())
            ctx.restoreGState()

            // Ground: grass gradient with a darker soil line at the bottom.
            let grassTop = RGB(0x5E9C43).mix(RGB(0x1F3526), night)
            let grassBottom = RGB(0x3D6E2F).mix(RGB(0x152419), night)
            let ground = CGRect(x: 0, y: groundY, width: m.width, height: m.maxY - groundY)
            drawVerticalGradient(ctx, in: ground, top: grassTop.cg(), bottom: grassBottom.cg())
            ctx.setFillColor(RGB(0x3B2A1C).mix(RGB(0x120D08), night).cg())
            ctx.fill(CGRect(x: 0, y: m.maxY - 2, width: m.width, height: 2))

            // Grass tufts, seeded.
            var tufts = SeededRandom(seed: 0x6A55 &+ UInt64(max(0, xOffset)))
            ctx.setFillColor(grassTop.scaled(1.25).cg())
            for _ in 0..<Int(m.width / 14) {
                let x = CGFloat(tufts.nextDouble()) * m.width
                let h: CGFloat = 1 + CGFloat(tufts.nextInt(in: 0..<2))
                ctx.fill(CGRect(x: x, y: groundY - h, width: 1, height: h + 1))
                ctx.fill(CGRect(x: x + 2, y: groundY - h + 1, width: 1, height: h))
            }
        }
    }

    private static func drawVerticalGradient(_ ctx: CGContext, in rect: CGRect, top: CGColor, bottom: CGColor) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [top, bottom] as CFArray, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                               end: CGPoint(x: rect.minX, y: rect.maxY), options: [])
        ctx.restoreGState()
    }

    private static func drawHills(_ ctx: CGContext, in m: CGRect, baseY: CGFloat, crest: CGFloat,
                                  amplitude: CGFloat, frequency: CGFloat, phase: CGFloat, color: CGColor) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: m.minX, y: baseY))
        var x = m.minX
        while x <= m.maxX {
            let wave = sin(x * frequency + phase) * 0.6 + sin(x * frequency * 2.3 + phase * 1.7) * 0.4
            path.addLine(to: CGPoint(x: x, y: crest + amplitude * (1 - wave) / 2))
            x += 2
        }
        path.addLine(to: CGPoint(x: m.maxX, y: baseY))
        path.closeSubpath()
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }
}
