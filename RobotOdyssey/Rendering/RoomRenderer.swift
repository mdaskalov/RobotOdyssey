import Apple2Kit
import Foundation

/// Draws a room exactly like the Apple II engine: identical, byte for byte, to
/// the original drawing routines run on the emulator (Data/ro_verify.py).
/// Mirrors Data/ro_render.py.
nonisolated struct RoomRenderer {
    /// Row r of character c: FONT_BASE + r × $60 + c.
    static let font = GameSymbols.address(\.fontBase)
    /// 4 pattern bytes per colour.
    static let colorTables: [KeyPath<GameSymbols, Table>] = [\.colourPattern0, \.colourPattern1, \.colourPattern2, \.colourPattern3]
    /// Colours of big (style 2) text, from the engine's BIG_TEXT_PATTERN_EVEN/ODD.
    static let bigTextColors: [(UInt8, UInt8)] = [(0x00, 0x00), (0x2A, 0x55), (0x55, 0x2A), (0x7F, 0x7F),
                                                   (0x80, 0x80), (0xAA, 0xD5), (0xD5, 0xAA), (0xFF, 0xFF)]

    let world: World

    func colour(_ c: Int) -> [UInt8] {
        RoomRenderer.colorTables.map { world.mem[$0, c & 0x1F] }
    }

    func spritePattern(_ c: Int) -> (UInt8, UInt8) {
        let p = colour(c)
        return (p[0], p[1])
    }

    func render(room: Int) -> HiresScreen {
        var screen = HiresScreen()
        let mem = world.mem
        drawTiles(&screen, world.room(room))                              // DRAW_ROOM_TILES
        for t in world.textsInRoom(room) {                                // DRAW_ROOM_TEXTS
            drawText(&screen, world.text(t))
        }
        let objects = world.drawList(room)
        for o in objects {                                                // DRAW_ROOM_OBJECTS
            let ob = world.object(o)
            drawSprite(&screen, Array(world.sprite(ob.sprite)), x: ob.x, y: ob.y, spritePattern(ob.color))
        }
        for o in objects {                                                // DRAW_WIRES
            if let w = world.wire(o) {
                drawWire(&screen, w.ax, w.ay, w.bx, w.by, colour: Int(mem[\.objColour, o]))
            }
        }
        for o in 0xD1 ..< 0xE0 where Int(mem[\.objRoom, o]) == room {    // loose wires
            if let w = world.looseWire(o) {
                drawWire(&screen, w.ax, w.ay, w.bx, w.by, colour: Int(mem[\.objColour, o]))
            }
        }
        return screen
    }

    /// 20x12 tiles of 14x16 pixels; even lines use pattern[b % 4], odd lines pattern[(b + 2) % 4].
    func drawTiles(_ s: inout HiresScreen, _ room: Room) {
        let floor = colour(room.floorColor), wall = colour(room.wallColor)
        for r in 0 ..< 12 {
            for c in 0 ..< 20 {
                let pat = room.walls[r][c] ? wall : floor
                if pat[0] == 0xF0 { continue }                     // colour $14: leave untouched
                for i in 0 ..< 16 {
                    let line = r * 16 + i
                    for b in [2 * c, 2 * c + 1] {
                        s.bytes[line * 40 + b] = pat[(b + (i & 1 == 1 ? 2 : 0)) % 4]
                    }
                }
            }
        }
    }

    /// 16 rows, row 0 at the bottom; bit 6 is the leftmost pixel.
    ///
    /// Like the engine's 7 pre-shifted routines (DRAW_SPRITE): every row with pixels
    /// rewrites all bytes it spans (2 for shift 0, else 3) with mask = pixels | $80,
    /// so those bytes take the pattern's palette bit; shift 0 also sets the
    /// palette bit of the third byte if that byte is empty.
    func drawSprite(_ s: inout HiresScreen, _ rows: [UInt8], x: Int, y: Int, _ pattern: (UInt8, UInt8)) {
        guard x < 0x86, y < 0xB1 else { return }
        let b0 = 2 * x / 7, shift = 2 * x % 7
        let span = shift == 0 ? 2 : 3
        for (r, bits) in rows.enumerated() where bits != 0 {
            let line = (191 - (y + r)) * 40
            var masks = [UInt8](repeating: 0x80, count: span)
            for i in 0 ..< 7 where bits & (0x40 >> i) != 0 {
                for q in [shift + 2 * i, shift + 2 * i + 1] {
                    masks[q / 7] |= 1 << (q % 7)
                }
            }
            for (k, mask) in masks.enumerated() {
                let b = b0 + k
                let pat = b & 1 == 0 ? pattern.0 : pattern.1
                s.bytes[line + b] = (s.bytes[line + b] & ~mask) | (mask & pat)
            }
            if shift == 0, b0 + 2 < 40, s.bytes[line + b0 + 2] == 0 {
                s.bytes[line + b0 + 2] = 0x80 & pattern.0
            }
        }
    }

    /// One colour pixel with the engine's tables (PLOT): AND/OR masks per
    /// (colour, shift) for the byte and the next one; the palette bit is ORed.
    func plotWire(_ s: inout HiresScreen, _ x: Int, _ y: Int, _ c: Int) {
        let mem = world.mem
        let i = (191 - y) * 40 + Int(mem[\.xByteTable, x])
        let idx = (c << 3 | Int(mem[\.xShiftTable, x])) & 0xFF
        s.bytes[i] = (s.bytes[i] & mem[\.plotKeep, idx]) | mem[\.plotSet, idx]
        if Int(mem[\.xByteTable, x]) + 1 < 40 {
            s.bytes[i + 1] = (s.bytes[i + 1] & mem[\.plotKeepNext, idx]) | mem[\.plotSetNext, idx]
        }
    }

    /// Wires are L-shaped: horizontal at A's y from ax to bx (HORIZONTAL_LINE), then
    /// vertical at B's x from ay to by (VERTICAL_LINE), corner at (bx, ay).  If the horizontal part
    /// is shorter than 4 units the vertical one ends up at max(ax, bx) + 1, as in
    /// the original (its loop leaves the x variable there).
    func drawWire(_ s: inout HiresScreen, _ ax: Int, _ ay: Int, _ bx: Int, _ by: Int, colour c: Int) {
        let mem = world.mem
        func clampX(_ v: Int) -> Int { v < 0x8B ? v : (v < 0xCF ? 0x8A : 0) }
        func clampY(_ v: Int) -> Int { v < 0xC0 ? v : (v < 0xDF ? 0xBF : 0) }
        var vx = bx
        if ay < 0xC0 {
            let lo = min(clampX(ax), clampX(bx)), end = max(clampX(ax), clampX(bx)) + 1
            if end - lo < 4 {
                for x in lo ..< end { plotWire(&s, x, ay, c) }
                vx = end
            } else {                                        // byte-wise fill with end masks
                let line = (191 - ay) * 40
                let pat = [mem[\.linePatternsEven, c], mem[\.linePatternsOdd, c]]   // even / odd byte columns
                var b = Int(mem[\.xByteTable, lo])
                let last = Int(mem[\.xByteTable, end])
                var keep = mem[\.lineStartMasks, Int(mem[\.xShiftTable, lo])]
                s.bytes[line + b] = (s.bytes[line + b] & keep) | (~keep & pat[b & 1])
                b += 1
                while b < last {
                    s.bytes[line + b] = pat[b & 1]
                    b += 1
                }
                keep = mem[\.lineEndMasks, Int(mem[\.xShiftTable, end])]
                if b < 40 { s.bytes[line + b] = (s.bytes[line + b] & keep) | (~keep & pat[b & 1]) }
            }
        }
        if vx < 0x8B {
            let lo = min(clampY(ay), clampY(by)), hi = max(clampY(ay), clampY(by))
            for y in lo ... hi { plotWire(&s, vx, y, c) }
        }
    }

    func drawText(_ s: inout HiresScreen, _ t: RoomText) {
        if t.style == 2 { return drawBigText(&s, t) }
        let col0 = t.x < 0x8C ? (2 * t.x) / 7 : -((2 * ((-t.x) & 0xFF)) / 7)
        var col = col0, y = t.y
        for c in t.bytes {
            if c == 0xA0 {
                col += 1
            } else if c > 0xA0 {
                if (0 ..< 40).contains(col), y < 0xB9 {
                    for r in 0 ..< 8 {
                        let line = 191 - (y + r)
                        if (0 ..< 192).contains(line) {
                            s.bytes[line * 40 + col] |= world.mem[RoomRenderer.font + r * 0x60 + Int(c)]
                        }
                    }
                }
                col += 1
            } else {                                            // carriage return
                y = (y - 9) & 0xFF
                col = col0
            }
        }
    }

    /// Style 2: glyphs doubled vertically and drawn as coloured sprites, 7 units apart.
    func drawBigText(_ s: inout HiresScreen, _ t: RoomText) {
        let pattern = RoomRenderer.bigTextColors[t.color & 7]
        var x = t.x, y = t.y
        for c in t.bytes {
            if c == 0x8D {
                x = t.x
                y = (y - 0x12) & 0xFF
                continue
            }
            if c != 0xA0, x < 0x86, y < 0xB1 {
                var rows: [UInt8] = []
                for r in 0 ..< 8 {
                    let f = world.mem[RoomRenderer.font + r * 0x60 + Int(c)]
                    let reversed = UInt8(f.bitReversed >> 1)        // font bit 0 = left, sprite bit 6 = left
                    rows += [reversed, reversed]
                }
                drawSprite(&s, rows, x: x, y: y, pattern)
            }
            x += 7
        }
    }
}

nonisolated private extension UInt8 {
    var bitReversed: UInt8 {
        var v = self, r: UInt8 = 0
        for _ in 0 ..< 8 {
            r = (r << 1) | (v & 1)
            v >>= 1
        }
        return r
    }
}
