import CoreGraphics
import Foundation

/// Converts a hi-res screen to an RGBA image; scale 2 gives 560x384 (each Apple pixel doubled).
nonisolated enum HiresImage {
    enum Mode: String, CaseIterable, Identifiable {
        case color = "Color", monochrome = "Mono"
        var id: String { rawValue }
    }

    struct RGB: Equatable {
        let r, g, b: UInt8
    }

    static let whiteRGB = RGB(r: 255, g: 255, b: 255)
    /// The monochrome screen's green.
    static let monoRGB = RGB(r: 20, g: 245, b: 60)
    /// [palette bit * 2 + pixel column parity]: purple, green, blue, orange.
    static let paletteRGB = [RGB(r: 255, g: 68, b: 253), RGB(r: 20, g: 245, b: 60),
                             RGB(r: 20, g: 207, b: 253), RGB(r: 255, g: 106, b: 60)]

    /// The colour a pair of patterns (even and odd byte columns, as the
    /// sprites and big text take them) shows filled in: white where pixels of
    /// both column parities are on, a palette colour where only one; nil:
    /// black.
    static func colour(patternEven: UInt8, patternOdd: UInt8) -> RGB? {
        var parities = Set<Int>()
        for (column, pattern) in [patternEven, patternOdd].enumerated() {
            for bit in 0 ..< 7 where pattern >> bit & 1 != 0 { parities.insert((column * 7 + bit) & 1) }
        }
        guard let parity = parities.first else { return nil }
        return parities.count == 2 ? whiteRGB : paletteRGB[Int(patternEven >> 6 & 2) + parity]
    }

    /// RGBA pixels as they lie in memory (R first), opaque.
    private static func rgba(_ c: RGB) -> UInt32 {
        UInt32(c.r) | UInt32(c.g) << 8 | UInt32(c.b) << 16 | 0xFF00_0000
    }

    private static let black = rgba(RGB(r: 0, g: 0, b: 0)), white = rgba(whiteRGB)
    private static let green = rgba(monoRGB)
    private static let palette = paletteRGB.map(rgba)

    /// Runs on every frame the viewer shows, so on pointers: a Debug build's
    /// array checks made it take 40 ms.
    static func make(_ screen: HiresScreen, mode: Mode = .color, scale: Int = 2) -> CGImage? {
        let w = HiresScreen.width * scale, h = HiresScreen.height * scale
        var pixels = [UInt32](repeating: 0, count: w * h)
        pixels.withUnsafeMutableBufferPointer { buffer in
            let out = buffer.baseAddress!
            screen.bytes.withUnsafeBufferPointer { bytes in
                let screen = bytes.baseAddress!
                // A line's pixels, with a blank one on either side: bit 0 on, bit 1 the palette bit.
                withUnsafeTemporaryAllocation(of: UInt8.self, capacity: HiresScreen.width + 2) { line in
                    let px = line.baseAddress!
                    px[0] = 0
                    px[HiresScreen.width + 1] = 0
                    for y in 0 ..< HiresScreen.height {
                        for b in 0 ..< 40 {
                            let v = screen[y * 40 + b], pal = v >> 6 & 2
                            for i in 0 ..< 7 { px[1 + b * 7 + i] = v >> i & 1 | pal }
                        }
                        let row = out + y * scale * w
                        var o = row
                        for x in 0 ..< HiresScreen.width {
                            let p = px[x + 1], left = px[x], right = px[x + 2]
                            var c = black
                            if mode == .monochrome {
                                if p & 1 != 0 { c = green }
                            } else if p & 1 != 0 {
                                c = (left | right) & 1 != 0 ? white : palette[Int(p & 2) + (x & 1)]
                            } else if left & right & 1 != 0 {
                                c = palette[Int(p & 2) + ((x - 1) & 1)]
                            }
                            o.pointee = c
                            if scale == 2 {
                                o[1] = c
                            } else {
                                for d in 1 ..< scale { o[d] = c }
                            }
                            o += scale
                        }
                        for dy in 1 ..< scale { (row + dy * w).update(from: row, count: w) }
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: pixels.withUnsafeBytes { Data($0) } as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
