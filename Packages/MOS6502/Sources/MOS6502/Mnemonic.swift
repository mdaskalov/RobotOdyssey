/// What an instruction does.  The documented instructions, then the NMOS
/// 6502's undocumented ones by their common names; AppleWin names several
/// differently (after Adam Vardy's "Extra Instructions Of The 65XX Series
/// CPU"), noted at each.
public enum Mnemonic: String, Sendable, CaseIterable {
    // Loads and stores
    case lda, ldx, ldy, sta, stx, sty
    // Arithmetic and logic
    case adc, sbc, and, ora, eor, cmp, cpx, cpy, bit
    // Shifts, rotations, increments and decrements
    case asl, lsr, rol, ror, inc, dec, inx, iny, dex, dey
    // Register transfers
    case tax, tay, txa, tya, tsx, txs
    // Stack
    case pha, php, pla, plp
    // Jumps, subroutines and interrupts
    case jmp, jsr, rts, rti, brk
    // Branches
    case bpl, bmi, bvc, bvs, bcc, bcs, bne, beq
    // Flags
    case clc, sec, cli, sei, cld, sed, clv
    case nop

    // Undocumented: a read-modify-write and an operation on A
    /// ASL, then ORA the result (AppleWin: ASO).
    case slo
    /// ROL, then AND the result.
    case rla
    /// LSR, then EOR the result (AppleWin: LSE).
    case sre
    /// ROR, then ADC the result.
    case rra
    /// DEC, then CMP the result (AppleWin: DCM).
    case dcp
    /// INC, then SBC the result (AppleWin: INS).
    case isc

    // Undocumented: loads and stores
    /// LDA and LDX at once.
    case lax
    /// Stores A AND X (AppleWin: AXS).
    case sax
    /// A, X and SP = operand AND SP.
    case las
    /// Stores A AND X AND (high byte of the address + 1) (AppleWin: AXA).
    case sha
    /// Stores X AND (high byte of the address + 1) (AppleWin: XAS).
    case shx
    /// Stores Y AND (high byte of the address + 1) (AppleWin: SAY).
    case shy
    /// SP = A AND X, then stores SP AND (high byte of the address + 1).
    case tas

    // Undocumented: immediate operations on A and X
    /// AND, then C = bit 7 (N).
    case anc
    /// AND, then LSR A.
    case alr
    /// AND, then ROR A, with C and V from bits 6 and 5 (and decimal fixes in D mode).
    case arr
    /// A = (A OR magic) AND X AND operand; the magic constant varies between
    /// chips (AppleWin: XAA, magic $FF).
    case ane
    /// A = X = (A OR magic) AND operand (AppleWin: OAL, magic $EE).
    case lxa
    /// X = (A AND X) - operand, C as CMP, no borrow in (AppleWin: SAX).
    case sbx

    /// Halts the CPU until reset (AppleWin: HLT).
    case jam

    /// How the instruction uses a memory operand.  An indexed read takes a cycle
    /// more when the index crosses a page; writes and read-modify-writes take
    /// that cycle always (`Opcode.addsCycleOnPageCross`).
    public enum Access: Sendable {
        case none, read, write, readModifyWrite
    }

    public var access: Access {
        switch self {
        case .lda, .ldx, .ldy, .adc, .sbc, .and, .ora, .eor, .cmp, .cpx, .cpy, .bit, .nop,
             .lax, .las, .anc, .alr, .arr, .ane, .lxa, .sbx:
            .read
        case .sta, .stx, .sty, .sax, .sha, .shx, .shy, .tas:
            .write
        case .asl, .lsr, .rol, .ror, .inc, .dec, .slo, .rla, .sre, .rra, .dcp, .isc:
            .readModifyWrite
        default:
            .none
        }
    }

    /// As written in assembly: "LDA".
    public var name: String { rawValue.uppercased() }
}
