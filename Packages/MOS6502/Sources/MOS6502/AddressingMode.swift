/// Where an instruction finds its operand.
public enum AddressingMode: Sendable, CaseIterable {
    /// No operand: `CLC`.
    case implied
    /// The accumulator: `ASL A`.
    case accumulator
    /// The byte after the opcode: `LDA #$12`.
    case immediate
    /// `LDA $12`
    case zeroPage
    /// `LDA $12,X`: stays in the zero page ($FF,X with X = 2 is $01).
    case zeroPageX
    /// `LDX $12,Y`: stays in the zero page.
    case zeroPageY
    /// `LDA $1234`
    case absolute
    /// `LDA $1234,X`
    case absoluteX
    /// `LDA $1234,Y`
    case absoluteY
    /// `LDA ($12,X)`: the address at $12 + X in the zero page (both bytes wrap
    /// within it).
    case indirectX
    /// `LDA ($12),Y`: the address at $12 in the zero page (the high byte from
    /// $00 for $FF), + Y.
    case indirectY
    /// `JMP ($1234)`: the NMOS 6502 doesn't carry into the pointer's high byte,
    /// `JMP ($12FF)` takes the high byte from $1200.
    case indirect
    /// Branches: -128...127 from the next instruction.
    case relative

    /// Bytes of the instruction, the opcode included.
    public var length: Int {
        switch self {
        case .implied, .accumulator: 1
        case .immediate, .zeroPage, .zeroPageX, .zeroPageY, .indirectX, .indirectY, .relative: 2
        case .absolute, .absoluteX, .absoluteY, .indirect: 3
        }
    }

    /// Indexed by X or Y past a 16-bit base, so the index can cross a page.
    public var isIndexedAbsolute: Bool {
        self == .absoluteX || self == .absoluteY || self == .indirectY
    }

    /// The operand as written in assembly, with `value` the instruction's
    /// operand bytes (little-endian) and `next` the address after it (for
    /// branches): "$1234,X".
    public func syntax(_ value: UInt16, next: UInt16) -> String {
        let byte = hex(value & 0xFF, 2), word = hex(value, 4)
        return switch self {
        case .implied: ""
        case .accumulator: "A"
        case .immediate: "#$\(byte)"
        case .zeroPage: "$\(byte)"
        case .zeroPageX: "$\(byte),X"
        case .zeroPageY: "$\(byte),Y"
        case .absolute: "$\(word)"
        case .absoluteX: "$\(word),X"
        case .absoluteY: "$\(word),Y"
        case .indirectX: "($\(byte),X)"
        case .indirectY: "($\(byte)),Y"
        case .indirect: "($\(word))"
        case .relative: "$\(hex(next &+ UInt16(bitPattern: Int16(Int8(bitPattern: UInt8(value & 0xFF)))), 4))"
        }
    }

    private func hex(_ value: UInt16, _ digits: Int) -> String {
        let s = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, digits - s.count)) + s
    }
}
