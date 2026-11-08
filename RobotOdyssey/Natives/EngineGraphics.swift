import Foundation

/// Native versions of the engine's drawing primitives (engine main, the same
/// in every world and version), for the native routines that draw.  They take
/// their parameters where the 6502 routines do, draw on the page the engine
/// draws on (LINE_LOW_TABLE and LINE_HIGH_TABLE, set by FLIP_PAGE), use the
/// engine's own mask tables and leave every temporary the original leaves, so
/// memory ends up identical byte for byte (Data/native_check.swift).  Like the
/// original they do not clip at the right edge of a line.
nonisolated extension Engine {
    /// Sets LINE_POINTER to hi-res line y of the page being drawn and returns it.
    func selectLine(_ y: UInt8) -> Int {
        m.linePointer = Int(m.lineLowTable[y]) | Int(m[m.lineHighTable + Int(y)]) << 8
        return m.linePointer
    }

    /// screen = (screen AND keep) OR set, the engine's way of changing pixels.
    private func merge(_ a: Int, keep: UInt8, set: UInt8) {
        m[a] = (m[a] & keep) | set
    }

    // MARK: sprites

    /// The 7 pre-shifted sprite routines (SHIFTED_SPRITE_ROUTINES, one per
    /// (2x) mod 7): for each byte a sprite row covers, which sprite bits land
    /// in it and where in SPRITE_MASKS the table is that turns them into the
    /// mask of covered pixels (bit 7 included).  Shift 0 covers 2 bytes and
    /// treats a third one separately.
    private static let spriteMasks: [[(bits: UInt8, table: Int)]] = [
        [(0x78, 0x02), (0x0F, 0xD9)],                           // $AF5A
        [(0x70, 0x07), (0x0F, 0xC9), (0x01, 0x101)],            // $B13B
        [(0x70, 0x03), (0x1E, 0xAA), (0x01, 0x103)],            // $AFD3
        [(0x60, 0x1B), (0x1E, 0xA9), (0x03, 0xF9)],             // $B1B3
        [(0x60, 0x0B), (0x3C, 0x00), (0x03, 0xFD)],             // $B04B
        [(0x40, 0x1F), (0x3C, 0x01), (0x07, 0xE9)],             // $B22B
        [(0x40, 0x0F), (0x78, 0x06), (0x07, 0xF1)],             // $B0C3
    ]

    /// DRAW_SPRITE_COLOUR ($9CC3): the sprite at SPRITE_POINTER in colour `c`
    /// at (DRAW_X, DRAW_Y).
    func drawSprite(colour c: UInt8) {
        m.patternEven = m.colourPattern0[c]
        m.patternOdd = m.colourPattern1[c]
        drawSprite()
    }

    /// DRAW_SPRITE ($AF1F): 16 rows from SPRITE_POINTER, row 0 at the bottom,
    /// with the patterns in PATTERN_EVEN/ODD.  Off-screen positions (x >= $86,
    /// y >= $B1) draw nothing.  A drawing on layer 3 (`PageLayers`).
    func drawSprite() {
        let x = Int(m.drawX), y = m.drawY
        guard x < 0x86, y < 0xB1 else { return }
        m.drawingOnLayer(\.drawSprite, {
            let rows = m.spritePointer
            return .sprite(LayerSprite(rows: (0 ..< 16).map { m[rows + $0] }, x: x, y: Int(y),
                                       patternEven: m.patternEven, patternOdd: m.patternOdd))
        }) { drawSprite(x: x, y: y) }
    }

    private func drawSprite(x: Int, y: UInt8) {
        let firstColumn = Int(m.xByteTable[x]), shift = Int(m.xShiftTable[x])
        m.spriteColumn = UInt8(firstColumn)
        m.spriteShift = UInt8(shift)
        m.jumpVector = m.shiftedSpriteRoutines.word(2 * shift)
        m.spriteLine = y &- 1
        let rows = m.spritePointer
        for r in 0 ..< 16 {
            m.spriteRow = UInt8(r + 1)
            m.spriteLine &+= 1
            let bits = m[rows + r]
            guard bits != 0 else { continue }
            m.spriteBits = bits
            let line = selectLine(m.spriteLine)
            var column = firstColumn
            for part in Engine.spriteMasks[shift] {
                let mask = m.spriteMasks[part.table + Int(bits & part.bits)]
                m.maskTemp = mask & (column & 1 == 0 ? m.patternEven : m.patternOdd)
                merge(line + column, keep: ~mask, set: m.maskTemp)
                column += 1
            }
            // Shift 0 gives an empty third byte the pattern's palette bit.
            if shift == 0, column < 0x28, m[line + column] == 0 {
                m.maskTemp = 0x80 & m.patternEven
                merge(line + column, keep: 0x7F, set: m.maskTemp)
            }
        }
    }

    // MARK: pixels and lines

    /// PLOT ($A14D): one colour pixel at (DRAW_X, DRAW_Y), with PLOT's masks
    /// for this byte and the next one.  A drawing on layer 3 (`PageLayers`).
    func plot(colour: UInt8) {
        m.drawingOnLayer(\.plot, {
            LayerLine.plot(x: m.drawX, y: m.drawY, colour: colour, m.lineColourPatterns).map(LayerItem.line)
        }) { plotPixel(colour: colour) }
    }

    private func plotPixel(colour: UInt8) {
        m.plotColour = colour
        let line = selectLine(m.drawY)
        let x = m.drawX
        let column = line + Int(m.xByteTable[x])
        let i = Int(colour << 3 | m.xShiftTable[x])
        merge(column, keep: m.plotKeep[i], set: m.plotSet[i])
        merge(column + 1, keep: m.plotKeepNext[i], set: m.plotSetNext[i])
    }

    /// x as the line routines clamp it (CLAMP_X).
    static func clampX(_ v: UInt8) -> Int { v < 0x8B ? Int(v) : (v < 0xCF ? 0x8A : 0) }

    /// y as the line routines clamp it (CLAMP_Y).
    static func clampY(_ v: UInt8) -> Int { v < 0xC0 ? Int(v) : (v < 0xDF ? 0xBF : 0) }

    /// HORIZONTAL_LINE ($A04C): from LINE_X1 to LINE_X2 at DRAW_Y in
    /// LINE_COLOUR.  Shorter than 4 units it plots pixels and leaves DRAW_X at
    /// max(x1, x2) + 1; otherwise it fills bytes with the colour's patterns,
    /// masking the first and the last byte.  A drawing on layer 3 (`PageLayers`).
    func horizontalLine() {
        m.drawingOnLayer(\.horizontalLine, {
            LayerLine.horizontal(x1: m.lineX1, x2: m.lineX2, y: m.drawY, colour: m.lineColour, m.lineColourPatterns).map(LayerItem.line)
        }) { horizontalLinePixels() }
    }

    private func horizontalLinePixels() {
        let y = m.drawY
        guard y < 0xC0 else { return }
        let c = Int(m.lineColour)
        m.linePatterns[1] = m.linePatternsOdd[c]
        m.linePatterns[0] = m.linePatternsEven[c]
        let line = selectLine(y)
        let a = Engine.clampX(m.lineX1), b = Engine.clampX(m.lineX2)
        let low = min(a, b), end = max(a, b) + 1
        m.lineLow = UInt8(low)
        m.lineEnd = UInt8(end)
        if end - low < 4 {
            m.drawX = UInt8(low)
            repeat {
                plot(colour: m.lineColour)
                m.drawX &+= 1
            } while Int(m.drawX) < end
            return
        }
        let first = Int(m.xByteTable[low]), last = Int(m.xByteTable[end])
        m.lineFirstColumn = UInt8(first)
        m.lineLastColumn = UInt8(last)
        m.lineMask = m.lineStartMasks[m.xShiftTable[low]]
        m.linePixels = ~m.lineMask & m.linePatterns[first & 1]
        merge(line + first, keep: m.lineMask, set: m.linePixels)
        var column = first + 1
        while column < last {
            m[line + column] = m.linePatterns[column & 1]
            column += 1
        }
        m.lineMask = m.lineEndMasks[m.xShiftTable[end]]
        m.linePixels = ~m.lineMask & m.linePatterns[last & 1]
        merge(line + column, keep: m.lineMask, set: m.linePixels)
    }

    /// VERTICAL_LINE ($9FC4): from LINE_Y1 to LINE_Y2 at DRAW_X in
    /// LINE_COLOUR, pixel by pixel; leaves DRAW_Y at max(y1, y2) + 1.  A
    /// drawing on layer 3 (`PageLayers`).
    func verticalLine() {
        m.drawingOnLayer(\.verticalLine, {
            LayerLine.vertical(x: m.drawX, y1: m.lineY1, y2: m.lineY2, colour: m.lineColour, m.lineColourPatterns).map(LayerItem.line)
        }) { verticalLinePixels() }
    }

    private func verticalLinePixels() {
        let x = Int(m.drawX)
        guard x < 0x8B else { return }
        m.verticalLineColumn = m.xByteTable[x]
        m.verticalLinePlot = m.lineColour << 3 | m.xShiftTable[x]
        let a = Engine.clampY(m.lineY1), b = Engine.clampY(m.lineY2)
        m.verticalLineEnd = UInt8(max(a, b) + 1)
        m.drawY = UInt8(min(a, b))
        repeat {
            let column = selectLine(m.drawY) + Int(m.verticalLineColumn)
            let i = Int(m.verticalLinePlot)
            merge(column, keep: m.plotKeep[i], set: m.plotSet[i])
            merge(column + 1, keep: m.plotKeepNext[i], set: m.plotSetNext[i])
            m.drawY &+= 1
        } while m.drawY < m.verticalLineEnd
    }

    /// DRAW_BOX ($A281): the outline of the rectangle (LINE_X1, LINE_Y1)-(LINE_X2, LINE_Y2).
    func drawBox() {
        m.drawY = m.lineY1
        horizontalLine()
        m.drawY = m.lineY2
        horizontalLine()
        m.drawX = m.lineX1
        verticalLine()
        m.drawX = m.lineX2
        verticalLine()
    }
}
