import Foundation

/// The 64K memory image as the native engine routines see it: the very bytes
/// the 6502 code works on (`Machine` swaps them in and out of the CPU), so
/// native and original routines can take turns.  Parameters live where the
/// engine keeps them; names follow Data/RobotOdyssey.sym.
struct RAM {
    var bytes: [UInt8]

    subscript(_ a: Int) -> UInt8 {
        get { bytes[a] }
        set { bytes[a] = newValue }
    }

    func word(_ a: Int) -> Int { Int(bytes[a]) | Int(bytes[a + 1]) << 8 }

    mutating func setWord(_ a: Int, _ v: Int) {
        bytes[a] = UInt8(v & 0xFF)
        bytes[a + 1] = UInt8(v >> 8 & 0xFF)
    }

    // MARK: engine parameters (zero page and $9Cxx)

    static let spritePointer = 0x0D     // ZP_SPRITEPTR, 2 bytes
    static let patternEven = 0x0F       // ZP_PAT_EVEN
    static let patternOdd = 0x10        // ZP_PAT_ODD
    static let linePointer = 0x11       // 2 bytes: hi-res line being drawn
    static let spriteBits = 0x13
    static let drawY = 0x14             // ZP_DRAW_Y, counted from the bottom
    static let maskTemp = 0x15
    static let lineHiTable = 0x16       // ZP_LINE_HI_PTR: line high bytes of the page drawn on
    static let drawX = 0x18             // ZP_DRAW_X, 0-139
    static let jumpVector = 0x19        // ZP_JUMP_VEC, 2 bytes
    static let lineColour = 0x9C34      // lines and boxes: colour, x1, y1, x2, y2
    static let lineX1 = 0x9C35, lineY1 = 0x9C36, lineX2 = 0x9C37, lineY2 = 0x9C38
    static let currentRoom = 0x9C2D     // CUR_ROOM
    static let moveDX = 0x9C22          // MOVE_DX, MOVE_DY: the move of CUR_OBJECT
    static let moveDY = 0x9C23
    static let destinationRoom = 0x9C2E // DEST_ROOM
    static let currentObject = 0x9C2F   // CUR_OBJECT
    static let buttonA = 0x9C3B         // BUTTON_A, BUTTON_B: 1 while pressed
    static let buttonB = 0x9C3C
    static let lastKey = 0x9C3D         // LAST_KEY: the key of this tick (0: none), 0 once used

    var x: UInt8 {
        get { bytes[RAM.drawX] }
        set { bytes[RAM.drawX] = newValue }
    }

    var y: UInt8 {
        get { bytes[RAM.drawY] }
        set { bytes[RAM.drawY] = newValue }
    }

    var sprite: Int {
        get { word(RAM.spritePointer) }
        set { setWord(RAM.spritePointer, newValue) }
    }
}

/// The 6502 registers as a native routine takes and leaves them: routines that
/// other code calls take parameters in registers, and their callers may use
/// what they leave (a result in A, a flag to branch on).  The helpers do what
/// the instructions do to the flags, so a port can leave them exactly as the
/// original does.
struct Registers {
    var a: UInt8 = 0, x: UInt8 = 0, y: UInt8 = 0
    var p: UInt8 = CPU6502.Flag.unused

    var carry: Bool {
        get { p & CPU6502.Flag.carry != 0 }
        set { set(CPU6502.Flag.carry, newValue) }
    }

    var zero: Bool { p & CPU6502.Flag.zero != 0 }

    mutating func set(_ flag: UInt8, _ on: Bool) {
        p = on ? p | flag : p & ~flag
    }

    /// N and Z as a load, transfer, INC/DEC or logic instruction leaves them; returns `v`.
    @discardableResult
    mutating func nz(_ v: UInt8) -> UInt8 {
        set(CPU6502.Flag.zero, v == 0)
        set(CPU6502.Flag.negative, v & 0x80 != 0)
        return v
    }

    /// CMP, CPX, CPY.
    mutating func compare(_ r: UInt8, _ m: UInt8) {
        carry = r >= m
        nz(r &- m)
    }

    /// ADC (binary mode) with the carry as it is.
    mutating func adc(_ a: UInt8, _ m: UInt8) -> UInt8 {
        let s = Int(a) + Int(m) + (carry ? 1 : 0)
        let r = UInt8(s & 0xFF)
        set(CPU6502.Flag.overflow, (a ^ r) & (m ^ r) & 0x80 != 0)
        carry = s > 0xFF
        return nz(r)
    }

    /// SBC (binary mode) with the carry as it is.
    mutating func sbc(_ a: UInt8, _ m: UInt8) -> UInt8 {
        adc(a, ~m)
    }

    /// BIT: Z from A AND m, N and V from bits 7 and 6 of m.
    mutating func bit(_ a: UInt8, _ m: UInt8) {
        set(CPU6502.Flag.zero, a & m == 0)
        set(CPU6502.Flag.negative, m & 0x80 != 0)
        set(CPU6502.Flag.overflow, m & 0x40 != 0)
    }

    /// Loads `v` and drops its sign, as `LDA v / JSR $AE20` does (`BPL`, else
    /// `EOR #$FF / CLC / ADC #1`): $80 stays $80.
    mutating func magnitude(_ v: UInt8) -> UInt8 {
        guard nz(v) & 0x80 != 0 else { return v }
        carry = false
        return adc(v ^ 0xFF, 1)
    }
}

/// What `CLC / ADC` and the following `ADC` do with the carry: some engine code
/// adds two constants in a row without clearing it in between.
struct Adder {
    private(set) var carry = false

    mutating func callAsFunction(_ a: UInt8, _ b: UInt8) -> UInt8 {
        let s = Int(a) + Int(b) + (carry ? 1 : 0)
        carry = s > 0xFF
        return UInt8(s & 0xFF)
    }
}
