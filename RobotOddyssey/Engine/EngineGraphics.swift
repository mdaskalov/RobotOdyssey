import Foundation

/// Native versions of the engine's drawing primitives ($9500-$B7D6, the same in
/// every world, v1.0 and v1.1).  They take their parameters where the 6502
/// routines do, draw on the page the engine draws on (line address tables
/// $9839 and ($16), set by FLIP_PAGE), use the engine's own mask tables and
/// leave every temporary the original leaves, so memory ends up identical byte
/// for byte (checked by Data/native_check.swift).  Like the original they do
/// not clip at the right edge of a line.
extension RAM {
    static let lineLowBytes = 0x9839    // LINE_LO_TABLE, by y counted from the bottom
    static let xByte = 0x9B05           // X_BYTE_TABLE: byte column of x
    static let xShift = 0x9A79          // X_SHIFT_TABLE: (2x) mod 7
    static let colourEven = 0x9B91      // COLOR_PAT0/1: sprite patterns for even/odd byte columns
    static let colourOdd = 0x9BB1

    /// Sets $11/$12 to hi-res line y of the page being drawn and returns it.
    mutating func selectLine(_ y: UInt8) -> Int {
        bytes[RAM.linePointer] = bytes[RAM.lineLowBytes + Int(y)]
        bytes[RAM.linePointer + 1] = bytes[(word(RAM.lineHiTable) + Int(y)) & 0xFFFF]
        return word(RAM.linePointer)
    }

    /// screen = (screen AND keep) OR set, the engine's way of changing pixels.
    private mutating func merge(_ a: Int, keep: UInt8, set: UInt8) {
        bytes[a & 0xFFFF] = (bytes[a & 0xFFFF] & keep) | set
    }

    // MARK: sprites

    /// The 7 pre-shifted sprite routines (table at $AF4C, one per (2x) mod 7):
    /// for each byte a sprite row covers, which sprite bits land in it and the
    /// table that turns them into the mask of covered pixels (bit 7 included).
    /// Shift 0 covers 2 bytes and treats a third one separately.
    private static let spriteMasks: [[(bits: UInt8, table: Int)]] = [
        [(0x78, 0xB2A5), (0x0F, 0xB37C)],                       // $AF5A
        [(0x70, 0xB2AA), (0x0F, 0xB36C), (0x01, 0xB3A4)],       // $B13B
        [(0x70, 0xB2A6), (0x1E, 0xB34D), (0x01, 0xB3A6)],       // $AFD3
        [(0x60, 0xB2BE), (0x1E, 0xB34C), (0x03, 0xB39C)],       // $B1B3
        [(0x60, 0xB2AE), (0x3C, 0xB2A3), (0x03, 0xB3A0)],       // $B04B
        [(0x40, 0xB2C2), (0x3C, 0xB2A4), (0x07, 0xB38C)],       // $B22B
        [(0x40, 0xB2B2), (0x78, 0xB2A9), (0x07, 0xB394)],       // $B0C3
    ]

    /// DRAW_SPRITE_COLOR ($9CC3): the sprite at ($0D) in colour `c` at ($18, $14).
    mutating func drawSprite(colour c: UInt8) {
        bytes[RAM.patternEven] = bytes[RAM.colourEven + Int(c)]
        bytes[RAM.patternOdd] = bytes[RAM.colourOdd + Int(c)]
        drawSprite()
    }

    /// DRAW_SPRITE ($AF1F): 16 rows from ($0D), row 0 at the bottom, with the
    /// patterns in $0F/$10.  Off-screen positions (x >= $86, y >= $B1) draw nothing.
    mutating func drawSprite() {
        let x = Int(self.x), y = self.y
        guard x < 0x86, y < 0xB1 else { return }
        let firstColumn = Int(bytes[RAM.xByte + x]), shift = Int(bytes[RAM.xShift + x])
        bytes[0xAEE8] = UInt8(firstColumn)
        bytes[0xAEEA] = UInt8(shift)
        bytes[RAM.jumpVector] = bytes[0xAF4C + 2 * shift]
        bytes[RAM.jumpVector + 1] = bytes[0xAF4D + 2 * shift]
        bytes[0xAEE9] = y &- 1
        let rows = sprite
        for r in 0 ..< 16 {
            bytes[0xAEE7] = UInt8(r + 1)
            bytes[0xAEE9] &+= 1
            let bits = bytes[(rows + r) & 0xFFFF]
            guard bits != 0 else { continue }
            bytes[RAM.spriteBits] = bits
            let line = selectLine(bytes[0xAEE9])
            var column = firstColumn
            for part in RAM.spriteMasks[shift] {
                let mask = bytes[part.table + Int(bits & part.bits)]
                bytes[RAM.maskTemp] = mask & bytes[column & 1 == 0 ? RAM.patternEven : RAM.patternOdd]
                merge(line + column, keep: ~mask, set: bytes[RAM.maskTemp])
                column += 1
            }
            // Shift 0 gives an empty third byte the pattern's palette bit.
            if shift == 0, column < 0x28, bytes[line + column] == 0 {
                bytes[RAM.maskTemp] = 0x80 & bytes[RAM.patternEven]
                merge(line + column, keep: 0x7F, set: bytes[RAM.maskTemp])
            }
        }
    }

    // MARK: pixels and lines

    /// PLOT ($A14D): one colour pixel at ($18, $14), using the AND/OR tables
    /// at $A201/$A181 (this byte) and $A241/$A1C1 (the next one).
    mutating func plot(colour: UInt8) {
        bytes[0xA14C] = colour
        let line = selectLine(y)
        let x = Int(self.x)
        let column = line + Int(bytes[RAM.xByte + x])
        let i = Int((colour << 3) | bytes[RAM.xShift + x])
        merge(column, keep: bytes[0xA201 + i], set: bytes[0xA181 + i])
        merge(column + 1, keep: bytes[0xA241 + i], set: bytes[0xA1C1 + i])
    }

    /// x as the line routines clamp it ($A036).
    static func clampX(_ v: UInt8) -> Int { v < 0x8B ? Int(v) : (v < 0xCF ? 0x8A : 0) }

    /// y as the line routines clamp it ($A02B).
    static func clampY(_ v: UInt8) -> Int { v < 0xC0 ? Int(v) : (v < 0xDF ? 0xBF : 0) }

    /// HLINE ($A04C): from x1 to x2 ($9C35/$9C37) at y ($14) in colour $9C34.
    /// Shorter than 4 units it plots pixels and leaves $18 at max(x1, x2) + 1;
    /// otherwise it fills bytes with the patterns $A144/$A13C and end masks
    /// $A135/$A12E.  Its temporaries are $A044-$A04B.
    mutating func horizontalLine() {
        let y = self.y
        guard y < 0xC0 else { return }
        let c = Int(bytes[RAM.lineColour])
        bytes[0xA04B] = bytes[0xA13C + c]                       // odd byte columns
        bytes[0xA04A] = bytes[0xA144 + c]                       // even byte columns
        let line = selectLine(y)
        let a = RAM.clampX(bytes[RAM.lineX1]), b = RAM.clampX(bytes[RAM.lineX2])
        let low = min(a, b), end = max(a, b) + 1
        bytes[0xA044] = UInt8(low)
        bytes[0xA045] = UInt8(end)
        if end - low < 4 {
            x = UInt8(low)
            repeat {
                plot(colour: bytes[RAM.lineColour])
                x &+= 1
            } while Int(x) < end
            return
        }
        let first = Int(bytes[RAM.xByte + low]), last = Int(bytes[RAM.xByte + end])
        bytes[0xA046] = UInt8(first)
        bytes[0xA047] = UInt8(last)
        bytes[0xA048] = bytes[0xA135 + Int(bytes[RAM.xShift + low])]
        bytes[0xA049] = ~bytes[0xA048] & bytes[0xA04A + (first & 1)]
        merge(line + first, keep: bytes[0xA048], set: bytes[0xA049])
        var column = first + 1
        while column < last {
            bytes[(line + column) & 0xFFFF] = bytes[0xA04A + (column & 1)]
            column += 1
        }
        bytes[0xA048] = bytes[0xA12E + Int(bytes[RAM.xShift + end])]
        bytes[0xA049] = ~bytes[0xA048] & bytes[0xA04A + (last & 1)]
        merge(line + column, keep: bytes[0xA048], set: bytes[0xA049])
    }

    /// VLINE ($9FC4): from y1 to y2 ($9C36/$9C38) at x ($18) in colour $9C34,
    /// pixel by pixel; leaves $14 at max(y1, y2) + 1.  Temporaries $9FC1-$9FC3.
    mutating func verticalLine() {
        let x = Int(self.x)
        guard x < 0x8B else { return }
        bytes[0x9FC1] = bytes[RAM.xByte + x]
        bytes[0x9FC2] = (bytes[RAM.lineColour] << 3) | bytes[RAM.xShift + x]
        let a = RAM.clampY(bytes[RAM.lineY1]), b = RAM.clampY(bytes[RAM.lineY2])
        bytes[0x9FC3] = UInt8(max(a, b) + 1)
        y = UInt8(min(a, b))
        repeat {
            let column = selectLine(y) + Int(bytes[0x9FC1])
            let i = Int(bytes[0x9FC2])
            merge(column, keep: bytes[0xA201 + i], set: bytes[0xA181 + i])
            merge(column + 1, keep: bytes[0xA241 + i], set: bytes[0xA1C1 + i])
            y &+= 1
        } while y < bytes[0x9FC3]
    }

    /// BOX ($A281): the outline of the rectangle ($9C35, $9C36)-($9C37, $9C38).
    mutating func drawBox() {
        y = bytes[RAM.lineY1]
        horizontalLine()
        y = bytes[RAM.lineY2]
        horizontalLine()
        x = bytes[RAM.lineX1]
        verticalLine()
        x = bytes[RAM.lineX2]
        verticalLine()
    }
}
