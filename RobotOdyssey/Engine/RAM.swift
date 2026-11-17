import Apple2Kit
import Foundation
import MOS6502

/// Symbols every world has, as code passes them around: `\.moveDX`, `\.drawSprite`.
typealias ByteSymbol = KeyPath<GameSymbols, Byte>
typealias RoutineSymbol = KeyPath<GameSymbols, Routine>

// Memory as the native routines see it is Apple2Kit's `RAM`, by the map of
// the world's engine (`Engine.m`): the CPU's own 64K (not a copy, so what a
// native writes is what the 6502 code reads next), with every symbol of the
// map by name:
//
//     m.robotX = m.objX[body]
//     m.drawX = m.robotX &+ 3
//
// A `Byte` reads as UInt8, a `Word` as Int, a `Table` as `Bytes` (indexed
// from its address), a `Sprite` as its address.  Addresses wrap at 64K like
// the 6502's.  What a native writes to a hi-res page is told to the CPU's
// `onWrite` as the 6502 code's writes are, and so to the canvas's layers
// when the machine keeps them (`Machine.layers`).  Only valid during the
// native call (`Machine.call`).

nonisolated extension RAM where Map: GameSymbols {
    /// A sprite: its address.
    @inline(__always)
    subscript(dynamicMember s: KeyPath<Map, Sprite>) -> Int {
        address(s)
    }

    /// The patterns of line colour `c` (LINE_PATTERNS_EVEN/ODD), for `LayerLine`.
    func lineColourPatterns(_ c: Int) -> (even: UInt8, odd: UInt8) {
        (self[GameSymbols.address(\.linePatternsEven) + c], self[GameSymbols.address(\.linePatternsOdd) + c])
    }
}

nonisolated extension Array where Element == UInt8 {
    /// Runs `body` on this memory image as the native routines see it, by
    /// the names of `map`.
    mutating func withRAM<Map: GameSymbols, R>(_ map: Map, _ body: (RAM<Map>) throws -> R) rethrows -> R {
        try withUnsafeMutableBufferPointer { try body(RAM($0.baseAddress!, map: map)) }
    }

    // Symbols every world has, for code that looks at a memory image (the
    // model, the viewer, the checks).

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
