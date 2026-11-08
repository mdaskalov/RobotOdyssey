import Apple2Kit
import Foundation

/// Layers 2 and 3 of a page as the Apple's pixels, for the one function that
/// colours them (`Screen.image`): a drawing looks the same on layer 3 as with
/// its routine switched off, and nothing drawn before another lies over it.
///
/// Layer 2 as it was where the first drawing on layer 3 came
/// (`PageFrame.start`) with layer 3's sprites, plots and lines drawn on it
/// byte for byte as their routines draw them – the pixels they cover lit
/// where their colour's patterns light them, and the palette bit of every
/// byte they touch (DRAW_SPRITE's masks, PLOT's tables and HORIZONTAL_LINE's
/// masks rewrite it even where they cover no pixel) – and with the writes
/// between them (`PageWrites`), in the order drawn: so a drawing that reads
/// a byte (DRAW_SPRITE's third byte, given the palette bit where it is 0)
/// finds it as it was then.  (Drawn on layer 2 as it ends, it found the
/// writes after it there: with VERTICAL_LINE switched off a robot's lit
/// bumper next to a sprite lost the palette bit and showed green, the user
/// saw, 2026-11-05.)  The texts are left out: the
/// canvas draws them in its font (`NativeLayer`), and the pixels drawn after
/// a text again over it (`afterTexts`).  So it is the page but for the
/// letters' cells (Data/layer_check.swift).
nonisolated struct LayerPixels {
    /// The page, top line first.
    let screen: HiresScreen
    /// By dot of the screen (`HiresScreen.dots`, top line first): how many
    /// texts came before the last drawing that covered its pixel, which it
    /// lies over.  Empty where no drawing comes after a text.
    let afterTexts: [UInt8]

    init(_ frame: PageFrame) {
        guard !frame.items.isEmpty else {
            screen = frame.apple
            afterTexts = []
            return
        }
        var raster = Raster(frame.start)
        for item in frame.items { raster.draw(item) }
        screen = HiresScreen(raster.page, base: 0)
        afterTexts = raster.afterTexts.isEmpty ? [] : LayerPixels.dots(raster.afterTexts, on: screen)
    }

    /// Values by pixel as by dot: each dot its pixel's (half a pixel to the
    /// right in a byte with the palette bit set), 0 where it shows none.
    private static func dots(_ byPixel: [UInt8], on screen: HiresScreen) -> [UInt8] {
        let w = HiresScreen.dotsPerLine
        var byDot = [UInt8](repeating: 0, count: w * HiresScreen.height)
        screen.bytes.withUnsafeBufferPointer { bytes in
            withUnsafeTemporaryAllocation(of: Int16.self, capacity: w) { dots in
                for line in 0 ..< HiresScreen.height {
                    HiresScreen.dots(of: bytes.baseAddress! + line * HiresScreen.bytesPerLine, into: dots.baseAddress!)
                    for d in 0 ..< w where dots[d] >= 0 {
                        byDot[line * w + d] = byPixel[line * HiresScreen.width + Int(dots[d])]
                    }
                }
            }
        }
        return byDot
    }
}

/// The drawing of `LayerPixels`, on a page's 8K as they lie in memory (a
/// drawing at the right edge of a line runs on into the next 40 bytes there,
/// as the routines' does: they don't clip).
private nonisolated struct Raster {
    var page = [UInt8](repeating: 0, count: PageLayers.pageSize)
    /// The texts drawn so far.
    var texts = 0
    var afterTexts: [UInt8] = []

    /// Where each byte of a page is on the screen (line × 40 + column), -1
    /// in the holes.
    static let screenIndex: [Int] = {
        var index = [Int](repeating: -1, count: PageLayers.pageSize)
        for line in 0 ..< HiresScreen.height {
            for column in 0 ..< HiresScreen.bytesPerLine {
                index[HiresScreen.lineOffset[line] + column] = line * HiresScreen.bytesPerLine + column
            }
        }
        return index
    }()

    init(_ screen: HiresScreen) {
        for line in 0 ..< HiresScreen.height {
            let offset = HiresScreen.lineOffset[line], row = line * HiresScreen.bytesPerLine
            page.replaceSubrange(offset ..< offset + HiresScreen.bytesPerLine,
                                 with: screen.bytes[row ..< row + HiresScreen.bytesPerLine])
        }
    }

    mutating func draw(_ item: LayerItem) {
        switch item {
        case .text: texts += 1
        case .sprite(let sprite): draw(sprite)
        case .line(let line): draw(line)
        case .writes(let writes): writes.forEach { merge($0, keep: ~$1, set: $2 & $1) }
        }
    }

    /// The byte at `offset` = (byte AND keep) OR set, the engine's way of
    /// changing pixels; the pixels changed covered.
    private mutating func merge(_ offset: Int, keep: UInt8, set: UInt8) {
        guard offset < page.count else { return }
        page[offset] = page[offset] & keep | set
        if texts > 0 { cover(offset, ~keep & 0x7F) }
    }

    /// The pixels of `bits` in the byte at `offset` drawn after `texts` texts.
    private mutating func cover(_ offset: Int, _ bits: UInt8) {
        let i = Raster.screenIndex[offset]
        guard i >= 0, bits != 0 else { return }
        if afterTexts.isEmpty { afterTexts = [UInt8](repeating: 0, count: HiresScreen.width * HiresScreen.height) }
        let first = i / HiresScreen.bytesPerLine * HiresScreen.width + i % HiresScreen.bytesPerLine * 7
        for b in 0 ..< 7 where bits >> b & 1 != 0 { afterTexts[first + b] = UInt8(min(texts, 255)) }
    }

    /// The offset of line `y` (from the bottom of the screen) in the page.
    private func line(_ y: Int) -> Int { HiresScreen.lineOffset[HiresScreen.height - 1 - y] }

    /// DRAW_SPRITE: on each row's line, the bytes from x's byte column on (2
    /// at shift 0, else 3): the pixels its bits cover (2 a bit, bit 6 on the
    /// left) lit as the column's pattern lights them, and the byte's palette
    /// bit the pattern's (SPRITE_MASKS: every byte, covered or not); at
    /// shift 0 a third byte that is 0 takes PATTERN_EVEN's palette bit.
    private mutating func draw(_ sprite: LayerSprite) {
        let first = 2 * sprite.x / 7, shift = 2 * sprite.x % 7
        for (r, bits) in sprite.rows.enumerated() where bits != 0 {
            let start = line(sprite.y + r) + first
            var covered = 0
            for k in 0 ..< 7 where bits >> k & 1 != 0 { covered |= 3 << (shift + 2 * (6 - k)) }
            for j in 0 ..< (shift == 0 ? 2 : 3) {
                let mask = UInt8(covered >> (7 * j) & 0x7F) | 0x80
                merge(start + j, keep: ~mask, set: mask & ((first + j) & 1 == 0 ? sprite.patternEven : sprite.patternOdd))
            }
            if shift == 0, first + 2 < HiresScreen.bytesPerLine, page[start + 2] == 0 {
                merge(start + 2, keep: 0x7F, set: 0x80 & sprite.patternEven)
            }
        }
    }

    /// PLOT, VERTICAL_LINE and HORIZONTAL_LINE: under 4 units across, a plot
    /// a unit on each line; otherwise (HORIZONTAL_LINE) the bytes from its
    /// first pixel's to the byte of the pixel after its last: the first from
    /// that pixel on (LINE_START_MASKS), the last up to it (LINE_END_MASKS:
    /// at its byte's first pixel only the palette bit), those between whole,
    /// in the column's pattern.
    private mutating func draw(_ l: LayerLine) {
        for y in l.y ..< l.y + l.height {
            let start = line(y)
            guard l.width >= 8 else {
                for x in stride(from: l.x, to: l.x + l.width, by: 2) { plot(start, x, l) }
                continue
            }
            let end = l.x + l.width
            let first = l.x / 7, last = end / 7
            let before = UInt8(1 << (l.x % 7) - 1), after = 0x7F & ~UInt8(1 << (end % 7) - 1)
            merge(start + first, keep: before, set: ~before & pattern(first, l))
            for column in first + 1 ..< max(last, first + 1) { merge(start + column, keep: 0, set: pattern(column, l)) }
            merge(start + last, keep: after, set: ~after & pattern(last, l))
        }
    }

    /// PLOT at pixel x (even): its two pixels in the column's pattern and the
    /// byte's palette bit (PLOT_SET/KEEP); from shift 5 on also the next
    /// byte's palette bit (PLOT_SET/KEEP_NEXT), at shift 6 with its first pixel.
    private mutating func plot(_ start: Int, _ x: Int, _ l: LayerLine) {
        let column = x / 7, covered = 3 << (x % 7)
        let mask = UInt8(covered & 0x7F) | 0x80
        merge(start + column, keep: ~mask, set: mask & pattern(column, l))
        if x % 7 >= 5 {
            let next = UInt8(covered >> 7 & 0x7F) | 0x80
            merge(start + column + 1, keep: ~next, set: next & pattern(column + 1, l))
        }
    }

    private func pattern(_ column: Int, _ l: LayerLine) -> UInt8 {
        column & 1 == 0 ? l.patternEven : l.patternOdd
    }
}
