import Foundation
import MOS6502

/// Symbols of the game's map as code passes them around: `\.moveDX`, `\.drawRobots`.
typealias ByteSymbol = KeyPath<GameSymbols, Byte>
typealias RoutineSymbol = KeyPath<GameSymbols, Routine>

/// Memory as the native routines see it: the CPU's own 64K (not a copy, so
/// what a native writes is what the 6502 code reads next), with every symbol
/// of the game's map by name, where the world's variant has it:
///
///     m.robotX = m.objX[body]
///     m.drawX = m.robotX &+ 3
///
/// A `Byte` reads as UInt8, a `Word` as Int, a `Table` as `Bytes` (indexed
/// from its address), a `Sprite` as its address.  Addresses wrap at 64K like
/// the 6502's.  Only valid during the native call (`Machine.call`).
@dynamicMemberLookup
nonisolated struct RAM {
    private let bytes: UnsafeMutablePointer<UInt8>
    /// The world's engine and version: where its symbols are.
    let variant: Variant

    init(_ bytes: UnsafeMutablePointer<UInt8>, _ variant: Variant) {
        self.bytes = bytes
        self.variant = variant
    }

    /// The byte at a computed address (a pointer's target, a table's entry).
    subscript(_ a: Int) -> UInt8 {
        get { bytes[a & 0xFFFF] }
        nonmutating set { bytes[a & 0xFFFF] = newValue }
    }

    func word(_ a: Int) -> Int { Int(self[a]) | Int(self[a + 1]) << 8 }

    func setWord(_ a: Int, _ v: Int) {
        self[a] = UInt8(v & 0xFF)
        self[a + 1] = UInt8(v >> 8 & 0xFF)
    }

    /// Where a symbol is in this variant; a symbol the variant lacks is a bug.
    /// (Inlined, the compiler turns `m.robotX` into a load from the map.)
    @inline(__always)
    func address<S: Symbol>(_ s: KeyPath<GameSymbols, S>) -> Int {
        guard let a = GameSymbols.map[keyPath: s].address(variant) else { missing() }
        return a
    }

    private func missing() -> Never {
        fatalError("A symbol the \(variant) engine doesn't have")
    }

    @inline(__always)
    subscript(dynamicMember s: ByteSymbol) -> UInt8 {
        get { self[address(s)] }
        nonmutating set { self[address(s)] = newValue }
    }

    /// A variable passed by its symbol: `m[move]` for `move = \.moveDX`.
    @inline(__always)
    subscript(_ s: ByteSymbol) -> UInt8 {
        get { self[address(s)] }
        nonmutating set { self[address(s)] = newValue }
    }

    @inline(__always)
    subscript(dynamicMember s: KeyPath<GameSymbols, Word>) -> Int {
        get { word(address(s)) }
        nonmutating set { setWord(address(s), newValue) }
    }

    @inline(__always)
    subscript(dynamicMember s: KeyPath<GameSymbols, Table>) -> Bytes {
        Bytes(ram: self, address: address(s))
    }

    @inline(__always)
    subscript(dynamicMember s: KeyPath<GameSymbols, Sprite>) -> Int {
        address(s)
    }
}

/// A table in memory, indexed from its address.
nonisolated struct Bytes {
    let ram: RAM
    let address: Int

    subscript(_ i: Int) -> UInt8 {
        get { ram[address + i] }
        nonmutating set { ram[address + i] = newValue }
    }

    subscript(_ i: UInt8) -> UInt8 {
        get { ram[address + Int(i)] }
        nonmutating set { ram[address + Int(i)] = newValue }
    }

    /// The 16-bit entry at byte `i`, low byte first.
    func word(_ i: Int) -> Int { ram.word(address + i) }
}

nonisolated extension Array where Element == UInt8 {
    /// Runs `body` on this memory image as the native routines see it.
    mutating func withRAM<R>(_ variant: Variant, _ body: (RAM) throws -> R) rethrows -> R {
        try withUnsafeMutableBufferPointer { try body(RAM($0.baseAddress!, variant)) }
    }

    // Symbols that are at the same place in every variant, for code that
    // looks at a memory image (the model, the viewer, the checks).

    subscript(_ s: ByteSymbol) -> UInt8 {
        get { self[GameSymbols.address(s)] }
        set { self[GameSymbols.address(s)] = newValue }
    }

    subscript(_ s: KeyPath<GameSymbols, Table>, _ i: Int) -> UInt8 {
        get { self[GameSymbols.address(s) + i] }
        set { self[GameSymbols.address(s) + i] = newValue }
    }

    subscript(_ s: KeyPath<GameSymbols, Word>) -> Int {
        let a = GameSymbols.address(s)
        return Int(self[a]) | Int(self[a + 1]) << 8
    }
}

/// The 6502 registers as a native routine takes and leaves them: routines that
/// other code calls take parameters in registers, and their callers may use
/// what they leave (a result in A, a flag to branch on).  The helpers do what
/// the instructions do to the flags, so a port can leave them exactly as the
/// original does.
nonisolated struct Registers {
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

    /// Loads `v` and drops its sign, as `LDA v / JSR MAGNITUDE` does (`BPL`,
    /// else `EOR #$FF / CLC / ADC #1`): $80 stays $80.
    mutating func magnitude(_ v: UInt8) -> UInt8 {
        guard nz(v) & 0x80 != 0 else { return v }
        carry = false
        return adc(v ^ 0xFF, 1)
    }
}

/// What `CLC / ADC` and the following `ADC` do with the carry: some engine code
/// adds two constants in a row without clearing it in between.
nonisolated struct Adder {
    private(set) var carry = false

    mutating func callAsFunction(_ a: UInt8, _ b: UInt8) -> UInt8 {
        let s = Int(a) + Int(b) + (carry ? 1 : 0)
        carry = s > 0xFF
        return UInt8(s & 0xFF)
    }
}
