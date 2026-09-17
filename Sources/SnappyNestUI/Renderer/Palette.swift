import AppKit
import CoreGraphics

/// Color tokens. Kept as `CGColor` (not NSColor) so the renderer can pass
/// them straight into CALayer without extra bridging.
public enum Palette {
    public static let tangerine = CGColor(red: 0xF2/255, green: 0x7E/255, blue: 0x1C/255, alpha: 1)
    public static let golden    = CGColor(red: 0xF5/255, green: 0xB5/255, blue: 0x31/255, alpha: 1)
    public static let cream     = CGColor(red: 0xFB/255, green: 0xE7/255, blue: 0xC0/255, alpha: 1)
    public static let cyan      = CGColor(red: 0x5F/255, green: 0xD9/255, blue: 0xE5/255, alpha: 1)
    public static let brown     = CGColor(red: 0x4A/255, green: 0x25/255, blue: 0x10/255, alpha: 1)

    // Sky bands sampled at every 3-hour tick — 8 stops interpolated across
    // the 24-hour panorama.
    public static let sky24: [CGColor] = [
        CGColor(red: 0x0B/255, green: 0x11/255, blue: 0x2A/255, alpha: 1), //  0
        CGColor(red: 0x15/255, green: 0x22/255, blue: 0x40/255, alpha: 1), //  3
        CGColor(red: 0x62/255, green: 0x3D/255, blue: 0x2E/255, alpha: 1), //  6 dawn
        CGColor(red: 0x3E/255, green: 0x74/255, blue: 0xA6/255, alpha: 1), //  9
        CGColor(red: 0x59/255, green: 0xB1/255, blue: 0xD1/255, alpha: 1), // 12 noon
        CGColor(red: 0x3E/255, green: 0x74/255, blue: 0xA6/255, alpha: 1), // 15
        CGColor(red: 0x62/255, green: 0x3D/255, blue: 0x2E/255, alpha: 1), // 18 dusk
        CGColor(red: 0x15/255, green: 0x22/255, blue: 0x40/255, alpha: 1)  // 21
    ]

    public static let ground     = CGColor(red: 0x2A/255, green: 0x1B/255, blue: 0x14/255, alpha: 1)
    public static let terrain    = CGColor(red: 0x4A/255, green: 0x31/255, blue: 0x20/255, alpha: 1)
    public static let controlBg  = CGColor(red: 0x18/255, green: 0x14/255, blue: 0x0F/255, alpha: 0.55)

    public static let batteryFill    = CGColor(red: 0x5D/255, green: 0xE0/255, blue: 0x8A/255, alpha: 1)
    public static let batteryEmpty   = CGColor(red: 0x24/255, green: 0x2A/255, blue: 0x24/255, alpha: 1)
    public static let batteryLow     = CGColor(red: 0xE0/255, green: 0x62/255, blue: 0x30/255, alpha: 1)
    public static let unavailableTint = CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
}
