import CoreGraphics
import Foundation

/// Converts a hi-res screen to an RGBA image; scale 2 gives 560x384 (each Apple pixel doubled).
enum HiresImage {
    enum Mode: String, CaseIterable, Identifiable {
        case color = "Color", monochrome = "Mono"
        var id: String { rawValue }
    }

    private typealias RGB = (UInt8, UInt8, UInt8)
    private static let black: RGB = (0, 0, 0), white: RGB = (255, 255, 255)
    private static let green: RGB = (20, 245, 60)
    /// [palette bit][pixel column parity]
    private static let palette: [[RGB]] = [[(255, 68, 253), (20, 245, 60)],     // purple, green
                                           [(20, 207, 253), (255, 106, 60)]]    // blue, orange

    static func make(_ screen: HiresScreen, mode: Mode = .color, scale: Int = 2) -> CGImage? {
        let w = HiresScreen.width * scale, h = HiresScreen.height * scale
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        var bits = [Bool](repeating: false, count: 280)
        var pal = [Int](repeating: 0, count: 280)
        for line in 0 ..< 192 {
            for b in 0 ..< 40 {
                let v = screen.bytes[line * 40 + b]
                for i in 0 ..< 7 {
                    bits[b * 7 + i] = v >> i & 1 != 0
                    pal[b * 7 + i] = Int(v >> 7)
                }
            }
            for x in 0 ..< 280 {
                let c: RGB
                let left = x > 0 && bits[x - 1], right = x < 279 && bits[x + 1]
                switch mode {
                case .monochrome:
                    c = bits[x] ? green : black
                case .color:
                    if bits[x] {
                        c = left || right ? white : palette[pal[x]][x & 1]
                    } else if left && right {
                        c = palette[pal[x]][(x - 1) & 1]
                    } else {
                        c = black
                    }
                }
                for dy in 0 ..< scale {
                    for dx in 0 ..< scale {
                        let o = ((line * scale + dy) * w + x * scale + dx) * 4
                        rgba[o] = c.0
                        rgba[o + 1] = c.1
                        rgba[o + 2] = c.2
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
