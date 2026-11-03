/// One of the 256 opcodes: the instruction, where it finds its operand and the
/// cycles it takes (`table`).
public struct Opcode: Sendable, Hashable, CustomStringConvertible {
    public let byte: UInt8
    public let mnemonic: Mnemonic
    public let mode: AddressingMode
    /// Cycles without the extras: +1 for an indexed read that crosses a page
    /// (`addsCycleOnPageCross`); a branch taken +1, +2 when it lands on another
    /// page.
    public let cycles: Int
    /// False for the opcodes MOS didn't document.
    public let isDocumented: Bool

    init(_ byte: UInt8, _ mnemonic: Mnemonic, _ mode: AddressingMode, _ cycles: Int, documented: Bool = true) {
        self.byte = byte
        self.mnemonic = mnemonic
        self.mode = mode
        self.cycles = cycles
        self.isDocumented = documented
    }

    /// The opcode `byte` stands for.
    public init(_ byte: UInt8) {
        self = Opcode.table[Int(byte)]
    }

    /// Bytes of the instruction, the opcode included.
    public var length: Int { mode.length }

    /// An indexed read takes a cycle more when the index carries into the
    /// address's high byte; the 6502 reads the address without the carry first
    /// and finds it wrong.  Writes and read-modify-writes always take that cycle,
    /// it's in `cycles`.
    public var addsCycleOnPageCross: Bool {
        mnemonic.access == .read && mode.isIndexedAbsolute
    }

    /// "LDA abs,X", "JMP (ind)".
    public var description: String {
        let operand = switch mode {
        case .implied: ""
        case .accumulator: " A"
        case .immediate: " #imm"
        case .zeroPage: " zp"
        case .zeroPageX: " zp,X"
        case .zeroPageY: " zp,Y"
        case .absolute: " abs"
        case .absoluteX: " abs,X"
        case .absoluteY: " abs,Y"
        case .indirectX: " (zp,X)"
        case .indirectY: " (zp),Y"
        case .indirect: " (ind)"
        case .relative: " rel"
        }
        return mnemonic.name + operand
    }
}
