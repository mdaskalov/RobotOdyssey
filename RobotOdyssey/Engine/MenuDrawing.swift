import Foundation
import MOS6502

/// Memory as the loader's natives see it: the CPU's own 64K with the loader's
/// symbols by name (`m.pictureRow`, `m.tileBank`); addresses wrap at 64K like
/// the 6502's.
@dynamicMemberLookup
nonisolated struct LoaderRAM {
    let cpu: CPU6502

    subscript(_ a: Int) -> UInt8 {
        get { cpu.mem[a & 0xFFFF] }
        nonmutating set { cpu.mem[a & 0xFFFF] = newValue }
    }

    func word(_ a: Int) -> Int { Int(self[a]) | Int(self[a + 1]) << 8 }

    func setWord(_ a: Int, _ v: Int) {
        self[a] = UInt8(v & 0xFF)
        self[a + 1] = UInt8(v >> 8 & 0xFF)
    }

    subscript(dynamicMember s: KeyPath<LoaderSymbols, Byte>) -> UInt8 {
        get { self[LoaderSymbols.address(s)] }
        nonmutating set { self[LoaderSymbols.address(s)] = newValue }
    }

    subscript(dynamicMember s: KeyPath<LoaderSymbols, Word>) -> Int {
        get { word(LoaderSymbols.address(s)) }
        nonmutating set { setWord(LoaderSymbols.address(s), newValue) }
    }

    /// Entry `i` of a table.
    subscript(_ s: KeyPath<LoaderSymbols, Table>, _ i: Int) -> UInt8 {
        self[LoaderSymbols.address(s) + i]
    }
}

/// The menu program's drawing as natives (Docs/Loader.md): DRAW_PICTURE
/// (op 00) and XOR_BLOCK (op 06) of its bytecode interpreter, which the title
/// and Robotropolis' intro run.  On the Apple the intro's tunes stop while
/// they draw (0.07-0.34 s a picture, 22 ms a block); here they take no time,
/// so the tunes follow one another.  Each leaves memory as the original
/// does, the interpreter's variables and zero page included; the
/// interpreter, their only caller, uses none of the registers they leave.
/// They run where the routine's code is the menu's (`Routine.code`): at their
/// addresses a world has its own code.  Switched off, the original runs.
nonisolated extension Loader {
    /// A native of the menu program, in place of `routine`.
    struct MenuNative {
        let routine: KeyPath<LoaderSymbols, Routine>
        let run: (LoaderRAM) -> Void

        var name: String { LoaderSymbols.name(of: routine) }
        var entry: Int { LoaderSymbols.address(routine) }
    }

    static let menuNatives = [
        MenuNative(routine: \.drawPicture, run: drawPicture),
        MenuNative(routine: \.xorBlock, run: xorBlock),
    ]

    /// Puts in the menu's natives: each runs, as a subroutine, where its
    /// routine's code is there.
    static func installMenuNatives(on machine: Machine) {
        for native in menuNatives {
            let code = Fingerprint(native.routine)
            machine.hook(native.entry, name: native.name) { m in
                guard code.matches(m.cpu.mem) else { return false }
                native.run(LoaderRAM(cpu: m.cpu))
                m.cpu.returnFromSubroutine()
                return true
            }
        }
    }

    /// A picture's header: the page drawn on, the first row and column, the
    /// sizes of tile banks A and B (big endian); the tiles from `tiles`, then
    /// the stream.
    private enum PictureHeader {
        static let page = 2, row = 3, column = 4, bankASize = 8, bankBSize = 10, tiles = 16
    }

    /// The stream's codes besides tile numbers ($00-$FA).
    private enum PictureCode {
        static let bankA: UInt8 = 0xFB
        static let bankB: UInt8 = 0xFC
        static let end: UInt8 = 0xFD
        /// k: the next column; the one just finished is drawn k times in all.
        static let nextColumn: UInt8 = 0xFE
        /// n, tile: the tile n times (0: 256).
        static let run: UInt8 = 0xFF
    }

    /// DRAW_PICTURE ($0A71): the picture at PICTURE_POINTER on the page its
    /// header names, down its columns from its first row and column, a tile
    /// a cell.  Code $FE k draws the column just finished k times in all: the
    /// stream goes back to where the column started, with TILE_BANK's high
    /// byte as it was there (not its low byte, as in the original).
    static func drawPicture(_ m: LoaderRAM) {
        let picture = m.picturePointer
        m.picturePage = m[picture + PictureHeader.page]
        m.tileBankA = (picture + PictureHeader.tiles) & 0xFFFF
        m.tileBankB = (m.tileBankA + bigEndian(m, picture + PictureHeader.bankASize)) & 0xFFFF
        m.streamPointer = (m.tileBankB + bigEndian(m, picture + PictureHeader.bankBSize)) & 0xFFFF
        m.firstRow = m[picture + PictureHeader.row]
        m.pictureRow = m.firstRow
        m.columnRepeat = 1
        m.pictureColumn = m[picture + PictureHeader.column]
        m.columnStart = m.streamPointer
        while true {
            let code = pictureByte(m)
            switch code {
            case PictureCode.run:
                m.runCount = pictureByte(m)
                drawTile(pictureByte(m), m)
                m.runCount &-= 1
                while m.runCount != 0 {
                    drawTileAgain(m)
                    m.runCount &-= 1
                }
            case PictureCode.nextColumn:
                m.pictureRow = m.firstRow
                m.pictureColumn &+= 1
                let times = pictureByte(m)
                if times != 1 && times != m.columnRepeat {
                    m.columnRepeat &+= 1
                    m.streamPointer = m.columnStart
                    m.tileBank = m.tileBank & 0xFF | Int(m.columnBankHigh) << 8
                    continue
                }
                if times != 1 { m.columnRepeat = 1 }
                m.columnStart = m.streamPointer
                m.columnBankHigh = UInt8(m.tileBank >> 8)
            case PictureCode.end:
                return
            case PictureCode.bankB:
                m.tileBank = m.tileBankB
            case PictureCode.bankA:
                m.tileBank = m.tileBankA
            default:
                drawTile(code, m)
            }
        }
    }

    /// The 16-bit size at `a`, high byte first.
    private static func bigEndian(_ m: LoaderRAM, _ a: Int) -> Int {
        Int(m[a]) << 8 | Int(m[a + 1])
    }

    /// PICTURE_BYTE ($0B9A): the stream's next byte.
    private static func pictureByte(_ m: LoaderRAM) -> UInt8 {
        let b = m[m.streamPointer]
        m.streamPointer = (m.streamPointer + 1) & 0xFFFF
        return b
    }

    /// DRAW_TILE ($0B08): tile `tile` of TILE_BANK (8 bytes a tile), then
    /// DRAW_TILE_AGAIN.
    private static func drawTile(_ tile: UInt8, _ m: LoaderRAM) {
        m.tilePointer = (m.tileBank + 8 * Int(tile)) & 0xFFFF
        drawTileAgain(m)
    }

    /// DRAW_TILE_AGAIN ($0B20): TILE_POINTER's 8 bytes into the cell at
    /// PICTURE_ROW, PICTURE_COLUMN, from its bottom line up (a line is $400
    /// above the next: SBC #4 on CELL_POINTER's high byte, its borrow going
    /// on); then the next row.
    private static func drawTileAgain(_ m: LoaderRAM) {
        let cell = LoaderSymbols.address(\.cellPointer)
        let carry = cellAddress(m.pictureRow, m)
        m[cell] = m.pictureColumn &+ m[cell] &+ (carry ? 1 : 0)
        var noBorrow = true
        for line in (0 ..< 8).reversed() {
            m[m.cellPointer] = m[m.tilePointer + line]
            let high = Int(m[cell + 1]) - 4 - (noBorrow ? 0 : 1)
            noBorrow = high >= 0
            m[cell + 1] = UInt8(high & 0xFF)
        }
        m.pictureRow &+= 1
    }

    /// CELL_ADDRESS ($0BA5): CELL_POINTER for row `row` at column 0 of
    /// PICTURE_PAGE, the cell's bottom line ($1C above its top); the carry
    /// its last ADC leaves, which DRAW_TILE_AGAIN adds with the column.
    private static func cellAddress(_ row: UInt8, _ m: LoaderRAM) -> Bool {
        let half = Int(row >> 1)
        let entry = m[\.rowLowTable, half]
        let cell = LoaderSymbols.address(\.cellPointer)
        m[cell] = entry >> 1 | (row & 1) << 7
        let high = Int(UInt8(half & 3) | m.picturePage) + 0x1C + Int(entry & 1)
        m[cell + 1] = UInt8(high & 0xFF)
        return high > 0xFF
    }

    /// XOR_BLOCK ($0D21): the block at PICTURE_ROW, PICTURE_COLUMN (width in
    /// bytes at +3, lines at +4, the bytes from +5) onto hi-res page 1 at the
    /// line in PICTURE_POINTER's low byte and the byte column in its high
    /// byte, each byte XORed with the screen's and bit 7 set.  Its counters
    /// end in STREAM_POINTER (end line, end column), TILE_POINTER's low byte
    /// (the column), CELL_POINTER (the last line) and the block pointer (past
    /// its bytes); all wrap at 256 as the original's.
    static func xorBlock(_ m: LoaderRAM) {
        let blockAt = LoaderSymbols.address(\.pictureRow)
        let block = m.word(blockAt)
        let line = UInt8(m.picturePointer & 0xFF), column = UInt8(m.picturePointer >> 8)
        let endColumn = column &+ m[block + 3], endLine = line &+ m[block + 4]
        m.streamPointer = Int(endLine) | Int(endColumn) << 8
        var data = (block + 5) & 0xFFFF
        var y = line
        repeat {
            m.cellPointer = Int(m[\.lineLow, Int(y)]) | Int(m[\.lineHigh, Int(y)]) << 8
            var x = column
            repeat {
                let a = m.cellPointer + Int(x)
                m[a] = (m[data] ^ m[a]) | 0x80
                data = (data + 1) & 0xFFFF
                x &+= 1
            } while x != endColumn
            y &+= 1
        } while y != endLine
        m[LoaderSymbols.address(\.tilePointer)] = endColumn
        m.setWord(blockAt, data)
    }
}

/// A routine's code as its fingerprint says (`Routine.code`), checked where a
/// hook runs.  The hooks sit at their addresses in the worlds too, where
/// other code is: the bytes last checked and the answer are kept, so a
/// world's code is hashed once, not at every pass.
private nonisolated final class Fingerprint {
    private let code: Code
    private var last: (bytes: [UInt8], matches: Bool)?

    init(_ routine: KeyPath<LoaderSymbols, Routine>) {
        code = LoaderSymbols.map[keyPath: routine].code[0]
    }

    func matches(_ mem: [UInt8]) -> Bool {
        let bytes = code.ranges.flatMap { mem[$0] }
        if let last, last.bytes == bytes { return last.matches }
        let matches = code.matches(mem)
        last = (bytes, matches)
        return matches
    }
}
