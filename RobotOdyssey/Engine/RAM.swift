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
    /// The canvas's layers of the pages, when the machine keeps them
    /// (`Machine.layers`): what is written to a page goes to them too.
    /// Unowned: the machine keeps them through the call.
    unowned(unsafe) let layers: PageLayers?

    init(_ bytes: UnsafeMutablePointer<UInt8>, _ variant: Variant, layers: PageLayers? = nil) {
        self.bytes = bytes
        self.variant = variant
        self.layers = layers
    }

    /// The byte at a computed address (a pointer's target, a table's entry).
    subscript(_ a: Int) -> UInt8 {
        get { bytes[a & 0xFFFF] }
        nonmutating set {
            let a = a & 0xFFFF
            if let layers, (0x2000 ..< 0x6000).contains(a) { layers.write(a, old: bytes[a], new: newValue) }
            bytes[a] = newValue
        }
    }

    /// Runs `draw`, `routine`'s drawing: on layer 3 (`PageLayers`) of the
    /// page the engine draws on if its native draws there, switched on
    /// (`Native.Flags.drawsOnLayer3`), `item` what it draws, made only if it
    /// is one.
    func drawingOnLayer(_ routine: RoutineSymbol, _ item: () -> LayerItem?, _ draw: () -> Void) {
        guard let layers, layers.isOn(address(routine)) else { return draw() }
        let page = PageLayers.page(lineHigh: self[word(address(\.lineHighTable))])
        layers.begin(layers.drawing == 0 ? item() : nil, page: page, memory: bytes)
        draw()
        layers.end()
    }

    func word(_ a: Int) -> Int { Int(self[a]) | Int(self[a + 1]) << 8 }

    /// The patterns of line colour `c` (LINE_PATTERNS_EVEN/ODD), for `LayerLine`.
    func lineColourPatterns(_ c: Int) -> (even: UInt8, odd: UInt8) {
        (self[address(\.linePatternsEven) + c], self[address(\.linePatternsOdd) + c])
    }

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

/// The registers a native routine takes and leaves (`Engine.r`, MOS6502's
/// `CPU6502.Registers`): the engine's own MAGNITUDE.
nonisolated extension CPU6502.Registers {
    /// Loads `v` and drops its sign, as `LDA v / JSR MAGNITUDE` does (`BPL`,
    /// else `EOR #$FF / CLC / ADC #1`): $80 stays $80.
    mutating func magnitude(_ v: UInt8) -> UInt8 {
        guard nz(v) & 0x80 != 0 else { return v }
        carry = false
        return adc(v ^ 0xFF, 1)
    }
}
