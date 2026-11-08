import Apple2Kit
import Foundation

/// The canvas's layers of the two hi-res pages (Frontends.md "The native
/// layer"), kept by the machine while a world runs (`Machine.layers`):
///
/// 1. the page in memory, as the game drew it: byte for byte the original's;
/// 2. the page as drawn without the drawings on layer 3 (`Page.apple`);
/// 3. those drawings as what they draw (`Page.items`), drawn by the Mac
///    over layer 2 in the order drawn, with what was written to the page
///    between them (`PageWrites`), so that it lies over the drawings made
///    before it.
///
/// The routines that draw on layer 3 (the natives that do,
/// `Native.Flags.drawsOnLayer3`: the texts, sprites, plots and lines;
/// `Machine` follows them as 6502 code, the Swift ones themselves) draw on
/// the page as ever, and nothing they write goes to layer 2.  Everything else written to a page goes to layer 2 too, the 6502
/// code's (the CPU's `onWrite`) and the natives' (`RAM`): the bits the write
/// changed only; after a drawing on layer 3 also to the writes between the
/// drawings.  A byte the 6502 code reads from the page and writes back with
/// its own pixels has layer 3's pixels in it too, which it doesn't change:
/// they stay out of layer 2.  A routine switched off (by its name in
/// `Machine.switchedOff`) draws on layers 1 and 2 only, in its place among
/// the drawings.
///
/// A page's layer 3 is emptied where its drawing starts (DRAW_ROOM_TILES draws
/// all of it).  Layer 2 is the page until the first drawing on layer 3 (taken
/// from the page there), and follows it from there on.  The page as it was
/// there is kept too (`Page.start`): the canvas draws layer 3's drawings and
/// the writes between them on it again, in order (`LayerPixels`).
nonisolated final class PageLayers {
    /// One page's layers 2 and 3.
    struct Page {
        /// Layer 2: the page's 8K as they lie in memory, without layer 3's
        /// drawings (while it has none, not kept up: the page is layer 2).
        var apple: [UInt8]
        /// Layer 2 where the first drawing on layer 3 came: the page then.
        var start: [UInt8]
        /// Layer 3, in the order drawn, with the writes between its drawings.
        var items: [LayerItem] = []
        /// What was written to the page since the last drawing on layer 3.
        var writes = PageWrites()

        /// Layer 3 as drawn so far: `items` and the writes after the last.
        var drawn: [LayerItem] { writes.isEmpty ? items : items + [.writes(writes)] }
    }

    static let pageSize = 0x2000

    /// Page 1 ($2000) and page 2 ($4000).
    private(set) var pages = [Page(apple: Array(repeating: 0, count: pageSize), start: Array(repeating: 0, count: pageSize)),
                              Page(apple: Array(repeating: 0, count: pageSize), start: Array(repeating: 0, count: pageSize))]
    /// Drawings on layer 3 under way, one inside the other (big text's
    /// letters are DRAW_SPRITE's inside DRAW_TEXT's, a short line's PLOTs
    /// inside HORIZONTAL_LINE's): what they write stays out of layer 2, and
    /// only the outermost is an item.
    private(set) var drawing = 0
    /// The entry points of the routines that draw on layer 3, those
    /// switched on (`Machine`: its natives that draw there).
    var routines: Set<Int> = []

    init() {}

    func copy() -> PageLayers {
        let c = PageLayers()
        c.pages = pages
        c.drawing = drawing
        c.routines = routines
        return c
    }

    /// The routine at `entry` draws on layer 3.
    @inline(__always)
    func isOn(_ entry: Int) -> Bool { routines.contains(entry) }

    /// The page (0 or 1) whose bytes the line high byte `high` is in.
    static func page(lineHigh high: UInt8) -> Int { high >= 0x40 ? 1 : 0 }

    /// A byte of a page ($2000-$5FFF) written: what changed in it goes to
    /// layer 2 and, in its place after layer 3's drawings, to the writes
    /// between them; but in a drawing on layer 3.
    @inline(__always)
    func write(_ address: Int, old: UInt8, new: UInt8) {
        let changed = old ^ new
        guard changed != 0, drawing == 0 else { return }
        let p = address >= 0x4000 ? 1 : 0
        guard !pages[p].items.isEmpty else { return }
        let i = address & (PageLayers.pageSize - 1)
        pages[p].apple[i] = pages[p].apple[i] & ~changed | new & changed
        pages[p].writes.add(i, changed: changed, value: new)
    }

    /// A drawing on layer 3 starts on `page` (`memory`: the 64K as they are):
    /// `item` (nil: inside another, part of it, or nothing to draw).
    func begin(_ item: LayerItem?, page: Int, memory: UnsafePointer<UInt8>) {
        defer { drawing += 1 }
        guard drawing == 0, let item else { return }
        if pages[page].items.isEmpty {
            let base = 0x2000 + page * PageLayers.pageSize
            pages[page].apple = Array(UnsafeBufferPointer(start: memory + base, count: PageLayers.pageSize))
            pages[page].start = pages[page].apple
        }
        if !pages[page].writes.isEmpty {
            pages[page].items.append(.writes(pages[page].writes))
            pages[page].writes = PageWrites()
        }
        pages[page].items.append(item)
    }

    /// The drawing `begin` started returns.
    func end() {
        if drawing > 0 { drawing -= 1 }
    }

    /// `page`'s drawing starts again (DRAW_ROOM_TILES): its layer 3 empty.
    /// No drawing on layer 3 goes on across it.
    func clear(page: Int) {
        pages[page].items = []
        pages[page].writes = PageWrites()
        drawing = 0
    }
}

/// A drawing on layer 3: what it draws, in the engine's coordinates; or
/// what was written to the page between two (`PageWrites`).
nonisolated enum LayerItem: Equatable {
    case text(DrawnText)
    case sprite(LayerSprite)
    case line(LayerLine)
    case writes(PageWrites)
}

/// What was written to a page after a drawing on layer 3, outside the
/// drawings (the 6502 code's, the natives', a routine's switched off): in
/// the order written, the bits each write changed with their new values.
/// The canvas draws them in their place among layer 3's drawings
/// (`LayerPixels`): over the drawings before them, under those after them.
nonisolated struct PageWrites: Equatable {
    /// Each write: its offset in the page (as in memory) << 16, the bits it
    /// changed << 8, the byte written.
    private(set) var writes: [UInt32] = []

    var isEmpty: Bool { writes.isEmpty }

    @inline(__always)
    mutating func add(_ offset: Int, changed: UInt8, value: UInt8) {
        writes.append(UInt32(offset) << 16 | UInt32(changed) << 8 | UInt32(value))
    }

    /// Each write: offset in the page, bits changed, byte written.
    func forEach(_ body: (_ offset: Int, _ changed: UInt8, _ value: UInt8) -> Void) {
        for w in writes { body(Int(w >> 16), UInt8(truncatingIfNeeded: w >> 8), UInt8(truncatingIfNeeded: w)) }
    }
}

/// A sprite DRAW_SPRITE drew: its 16 rows (row 0 at the bottom), each bit
/// two pixels across, bit 6 on the left; at (x, y), x in object units (two
/// pixels), y the bottom row's line counted from the bottom of the screen;
/// in the colour of PATTERN_EVEN/ODD (the pixels it sets in even and odd
/// byte columns, bit 7 the palette).
nonisolated struct LayerSprite: Equatable {
    let rows: [UInt8]
    let x, y: Int
    let patternEven, patternOdd: UInt8

    init(rows: [UInt8], x: Int, y: Int, patternEven: UInt8, patternOdd: UInt8) {
        self.rows = rows
        self.x = x
        self.y = y
        self.patternEven = patternEven
        self.patternOdd = patternOdd
    }

    /// The sprite DRAW_SPRITE is about to draw, in `mem` where it starts;
    /// nil where it draws nothing (x ≥ $86, y ≥ $B1).
    init?(_ mem: [UInt8]) {
        let x = Int(mem[\.drawX]), y = Int(mem[\.drawY])
        guard x < 0x86, y < 0xB1 else { return nil }
        let rows = mem[\.spritePointer]
        self.init(rows: (0 ..< 16).map { mem[(rows + $0) & 0xFFFF] }, x: x, y: y,
                  patternEven: mem[\.patternEven], patternOdd: mem[\.patternOdd])
    }
}

/// A plot or a line PLOT, HORIZONTAL_LINE or VERTICAL_LINE drew: the pixels
/// it covers, `x ..< x + width` across (screen pixels) on the lines
/// `y ..< y + height` (from the bottom of the screen), lit where the
/// patterns of its colour light them (LINE_PATTERNS_EVEN/ODD, by byte
/// column; PLOT's tables light the same pixels), cleared elsewhere.  Under
/// 8 pixels across (4 units) it is plots, a unit each (HORIZONTAL_LINE
/// plots a short line, VERTICAL_LINE plots every line): `LayerPixels`
/// draws it so.
nonisolated struct LayerLine: Equatable {
    let x, width, y, height: Int
    let patternEven, patternOdd: UInt8

    /// A colour's patterns (even, odd byte columns).
    typealias Patterns = (Int) -> (even: UInt8, odd: UInt8)

    /// PLOT: the colour pixel at (x, y), two pixels across (x in object
    /// units); nil off the screen.
    static func plot(x: UInt8, y: UInt8, colour: UInt8, _ patterns: Patterns) -> LayerLine? {
        guard x < 0x8C, y < 0xC0 else { return nil }
        let p = patterns(Int(colour))
        return LayerLine(x: 2 * Int(x), width: 2, y: Int(y), height: 1, patternEven: p.even, patternOdd: p.odd)
    }

    /// HORIZONTAL_LINE: from x1 to x2 (clamped, both drawn) at y; nil for y ≥ $C0.
    static func horizontal(x1: UInt8, x2: UInt8, y: UInt8, colour: UInt8, _ patterns: Patterns) -> LayerLine? {
        guard y < 0xC0 else { return nil }
        let a = Engine.clampX(x1), b = Engine.clampX(x2)
        let low = min(a, b), end = max(a, b) + 1
        let p = patterns(Int(colour))
        return LayerLine(x: 2 * low, width: 2 * (end - low), y: Int(y), height: 1, patternEven: p.even, patternOdd: p.odd)
    }

    /// VERTICAL_LINE: from y1 to y2 (clamped, both drawn) at x; nil for x ≥ $8B.
    static func vertical(x: UInt8, y1: UInt8, y2: UInt8, colour: UInt8, _ patterns: Patterns) -> LayerLine? {
        guard x < 0x8B else { return nil }
        let a = Engine.clampY(y1), b = Engine.clampY(y2)
        let p = patterns(Int(colour))
        return LayerLine(x: 2 * Int(x), width: 2, y: min(a, b), height: abs(a - b) + 1, patternEven: p.even, patternOdd: p.odd)
    }
}

/// A page as the canvas shows it: as the game drew it (layer 1, `page`), and
/// as drawn without the drawings on layer 3 (`apple`, layer 2) with those
/// over it (`items`, and the writes between them).  Without any, `apple` is
/// the page.  The Apple's pixels of both together: `LayerPixels`, drawn on
/// layer 2 as it was where the first drawing came (`start`).
nonisolated struct PageFrame {
    let page, apple, start: HiresScreen
    let items: [LayerItem]

    init(page: HiresScreen, apple: HiresScreen? = nil, start: HiresScreen? = nil, items: [LayerItem] = []) {
        self.page = page
        self.apple = apple ?? page
        self.start = start ?? apple ?? page
        self.items = items
    }
}
