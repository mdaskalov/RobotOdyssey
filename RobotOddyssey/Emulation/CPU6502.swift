import Foundation

/// NMOS 6502 (documented opcodes) with cycle counting, over a flat 64K memory.
///
/// Reads/writes of $C000-$C0FF go to `ioRead`/`ioWrite` so callers can fake
/// the keyboard and soft switches.  Used to run original game code headless
/// (level exit scripts today, timing measurements and reference behaviour for
/// the game-logic port later).  Mirrors Data/cpu6502.py.
final class CPU6502 {
    var mem: [UInt8]
    var a: UInt8 = 0, x: UInt8 = 0, y: UInt8 = 0
    var sp: UInt8 = 0xFF
    var p: UInt8 = Flag.unused | Flag.interrupt
    var pc: UInt16 = 0
    var cycles: UInt64 = 0
    var ioRead: (UInt16) -> UInt8 = { _ in 0 }
    var ioWrite: (UInt16, UInt8) -> Void = { _, _ in }

    enum Flag {
        static let carry: UInt8 = 0x01, zero: UInt8 = 0x02, interrupt: UInt8 = 0x04, decimal: UInt8 = 0x08
        static let brk: UInt8 = 0x10, unused: UInt8 = 0x20, overflow: UInt8 = 0x40, negative: UInt8 = 0x80
    }

    enum CPUError: Error {
        case illegalOpcode(UInt8, at: UInt16)
        case brk(at: UInt16)
        case tooManySteps(pc: UInt16)
    }

    init(memory: [UInt8]) {
        precondition(memory.count == 0x10000)
        mem = memory
    }

    // MARK: memory

    @inline(__always) func read(_ addr: UInt16) -> UInt8 {
        (0xC000...0xC0FF).contains(addr) ? ioRead(addr) : mem[Int(addr)]
    }

    @inline(__always) func write(_ addr: UInt16, _ v: UInt8) {
        if (0xC000...0xC0FF).contains(addr) { ioWrite(addr, v) } else { mem[Int(addr)] = v }
    }

    func read16(_ addr: UInt16) -> UInt16 {
        UInt16(read(addr)) | UInt16(read(addr &+ 1)) << 8
    }

    func push(_ v: UInt8) {
        mem[0x100 + Int(sp)] = v
        sp &-= 1
    }

    func pull() -> UInt8 {
        sp &+= 1
        return mem[0x100 + Int(sp)]
    }

    // MARK: running

    /// JSR to `address` and run until it returns or PC reaches one of `stopAt`.
    @discardableResult
    func call(_ address: UInt16, stopAt: Set<UInt16> = [], maxSteps: Int = 5_000_000) throws -> UInt16 {
        push(0xFF)
        push(0xFE)                              // RTS lands on $FFFF: the sentinel
        pc = address
        for _ in 0 ..< maxSteps {
            if pc == 0xFFFF || stopAt.contains(pc) { return pc }
            try step()
        }
        throw CPUError.tooManySteps(pc: pc)
    }

    func step() throws {
        let opcode = read(pc)
        guard let info = CPU6502.table[Int(opcode)] else { throw CPUError.illegalOpcode(opcode, at: pc) }
        pc &+= 1
        let (addr, pageCrossed) = operand(info.mode)
        cycles += UInt64(info.cycles)
        try execute(info.op, info.mode, addr, pageCrossed)
    }

    // MARK: addressing

    private func fetch() -> UInt8 {
        let v = read(pc)
        pc &+= 1
        return v
    }

    private func fetch16() -> UInt16 {
        let v = read16(pc)
        pc &+= 2
        return v
    }

    private func operand(_ mode: Mode) -> (UInt16, Bool) {
        switch mode {
        case .imp, .acc: return (0, false)
        case .imm: let a = pc; pc &+= 1; return (a, false)
        case .zp: return (UInt16(fetch()), false)
        case .zpx: return (UInt16(fetch() &+ x), false)
        case .zpy: return (UInt16(fetch() &+ y), false)
        case .abs: return (fetch16(), false)
        case .abx:
            let b = fetch16(), a = b &+ UInt16(x)
            return (a, (a ^ b) & 0xFF00 != 0)
        case .aby:
            let b = fetch16(), a = b &+ UInt16(y)
            return (a, (a ^ b) & 0xFF00 != 0)
        case .izx:
            let z = fetch() &+ x
            return (UInt16(mem[Int(z)]) | UInt16(mem[Int(z &+ 1)]) << 8, false)
        case .izy:
            let z = fetch()
            let b = UInt16(mem[Int(z)]) | UInt16(mem[Int(z &+ 1)]) << 8, a = b &+ UInt16(y)
            return (a, (a ^ b) & 0xFF00 != 0)
        case .ind:
            let ptr = fetch16()
            let hi = (ptr & 0xFF00) | ((ptr &+ 1) & 0x00FF)        // NMOS page-wrap bug
            return (UInt16(read(ptr)) | UInt16(read(hi)) << 8, false)
        case .rel:
            let o = Int8(bitPattern: fetch())
            return (UInt16(truncatingIfNeeded: Int(pc) + Int(o)), false)
        }
    }

    // MARK: flags

    @discardableResult
    private func nz(_ v: UInt8) -> UInt8 {
        p = (p & ~(Flag.negative | Flag.zero)) | (v & Flag.negative) | (v == 0 ? Flag.zero : 0)
        return v
    }

    private func set(_ flag: UInt8, _ on: Bool) {
        p = on ? (p | flag) : (p & ~flag)
    }

    private var carry: UInt8 { p & Flag.carry }

    // MARK: instructions

    private func adc(_ v: UInt8) {
        let a16 = UInt16(a), v16 = UInt16(v), c16 = UInt16(carry)
        if p & Flag.decimal != 0 {
            var lo = (a16 & 0x0F) + (v16 & 0x0F) + c16
            var hi = (a16 >> 4) + (v16 >> 4) + (lo > 9 ? 1 : 0)
            if lo > 9 { lo += 6 }
            set(Flag.zero, (a16 + v16 + c16) & 0xFF == 0)
            set(Flag.negative, hi & 8 != 0)
            set(Flag.overflow, ~(a16 ^ v16) & (a16 ^ (hi << 4)) & 0x80 != 0)
            if hi > 9 { hi += 6 }
            set(Flag.carry, hi > 15)
            a = UInt8(((hi << 4) | (lo & 0x0F)) & 0xFF)
        } else {
            let r = a16 + v16 + c16
            set(Flag.carry, r > 0xFF)
            set(Flag.overflow, ~(a16 ^ v16) & (a16 ^ r) & 0x80 != 0)
            a = nz(UInt8(r & 0xFF))
        }
    }

    private func sbc(_ v: UInt8) {
        guard p & Flag.decimal != 0 else { return adc(~v) }
        let a16 = Int(a), v16 = Int(v), borrow = 1 - Int(carry)
        let r = a16 - v16 - borrow
        var lo = (a16 & 0x0F) - (v16 & 0x0F) - borrow
        var hi = (a16 >> 4) - (v16 >> 4) - (lo < 0 ? 1 : 0)
        if lo < 0 { lo -= 6 }
        if hi < 0 { hi -= 6 }
        set(Flag.carry, r >= 0)
        set(Flag.overflow, (a16 ^ v16) & (a16 ^ r) & 0x80 != 0)
        nz(UInt8(truncatingIfNeeded: r))
        a = UInt8(truncatingIfNeeded: (hi << 4) | (lo & 0x0F))
    }

    private func compare(_ reg: UInt8, _ v: UInt8) {
        set(Flag.carry, reg >= v)
        nz(reg &- v)
    }

    private func branch(_ target: UInt16, _ condition: Bool) {
        guard condition else { return }
        cycles += (target ^ pc) & 0xFF00 != 0 ? 2 : 1
        pc = target
    }

    private func modify(_ mode: Mode, _ addr: UInt16, _ f: (UInt8) -> UInt8) {
        if mode == .acc { a = f(a) } else { write(addr, f(read(addr))) }
    }

    private func execute(_ op: Op, _ mode: Mode, _ addr: UInt16, _ crossed: Bool) throws {
        let penalty: UInt64 = crossed ? 1 : 0
        switch op {
        case .lda: a = nz(read(addr)); cycles += penalty
        case .ldx: x = nz(read(addr)); cycles += penalty
        case .ldy: y = nz(read(addr)); cycles += penalty
        case .sta: write(addr, a)
        case .stx: write(addr, x)
        case .sty: write(addr, y)
        case .adc: adc(read(addr)); cycles += penalty
        case .sbc: sbc(read(addr)); cycles += penalty
        case .and: a = nz(a & read(addr)); cycles += penalty
        case .ora: a = nz(a | read(addr)); cycles += penalty
        case .eor: a = nz(a ^ read(addr)); cycles += penalty
        case .cmp: compare(a, read(addr)); cycles += penalty
        case .cpx: compare(x, read(addr))
        case .cpy: compare(y, read(addr))
        case .bit:
            let v = read(addr)
            set(Flag.zero, a & v == 0)
            set(Flag.negative, v & 0x80 != 0)
            set(Flag.overflow, v & 0x40 != 0)
        case .inc: modify(mode, addr) { nz($0 &+ 1) }
        case .dec: modify(mode, addr) { nz($0 &- 1) }
        case .inx: x = nz(x &+ 1)
        case .iny: y = nz(y &+ 1)
        case .dex: x = nz(x &- 1)
        case .dey: y = nz(y &- 1)
        case .asl: modify(mode, addr) { v in set(Flag.carry, v & 0x80 != 0); return nz(v << 1) }
        case .lsr: modify(mode, addr) { v in set(Flag.carry, v & 1 != 0); return nz(v >> 1) }
        case .rol:
            modify(mode, addr) { v in
                let r = (v << 1) | carry
                set(Flag.carry, v & 0x80 != 0)
                return nz(r)
            }
        case .ror:
            modify(mode, addr) { v in
                let r = (v >> 1) | (carry << 7)
                set(Flag.carry, v & 1 != 0)
                return nz(r)
            }
        case .tax: x = nz(a)
        case .tay: y = nz(a)
        case .txa: a = nz(x)
        case .tya: a = nz(y)
        case .tsx: x = nz(sp)
        case .txs: sp = x
        case .pha: push(a)
        case .php: push(p | Flag.brk | Flag.unused)
        case .pla: a = nz(pull())
        case .plp: p = (pull() & ~Flag.brk) | Flag.unused
        case .jmp: pc = addr
        case .jsr:
            let r = pc &- 1
            push(UInt8(r >> 8))
            push(UInt8(r & 0xFF))
            pc = addr
        case .rts: pc = (UInt16(pull()) | UInt16(pull()) << 8) &+ 1
        case .rti:
            p = (pull() & ~Flag.brk) | Flag.unused
            pc = UInt16(pull()) | UInt16(pull()) << 8
        case .brk: throw CPUError.brk(at: pc &- 1)
        case .nop: break
        case .clc: set(Flag.carry, false)
        case .sec: set(Flag.carry, true)
        case .cli: set(Flag.interrupt, false)
        case .sei: set(Flag.interrupt, true)
        case .cld: set(Flag.decimal, false)
        case .sed: set(Flag.decimal, true)
        case .clv: set(Flag.overflow, false)
        case .bpl: branch(addr, p & Flag.negative == 0)
        case .bmi: branch(addr, p & Flag.negative != 0)
        case .bvc: branch(addr, p & Flag.overflow == 0)
        case .bvs: branch(addr, p & Flag.overflow != 0)
        case .bcc: branch(addr, p & Flag.carry == 0)
        case .bcs: branch(addr, p & Flag.carry != 0)
        case .bne: branch(addr, p & Flag.zero == 0)
        case .beq: branch(addr, p & Flag.zero != 0)
        }
    }

    // MARK: opcode table

    enum Mode { case imp, acc, imm, zp, zpx, zpy, abs, abx, aby, izx, izy, ind, rel }

    enum Op: String {
        case adc, and, asl, bcc, bcs, beq, bit, bmi, bne, bpl, brk, bvc, bvs, clc, cld, cli, clv, cmp, cpx, cpy
        case dec, dex, dey, eor, inc, inx, iny, jmp, jsr, lda, ldx, ldy, lsr, nop, ora, pha, php, pla, plp
        case rol, ror, rti, rts, sbc, sec, sed, sei, sta, stx, sty, tax, tay, tsx, txa, txs, tya
    }

    struct OpInfo {
        let op: Op
        let mode: Mode
        let cycles: UInt8
    }

    /// opcode mnemonic mode base-cycles (same table as Data/cpu6502.py)
    private static let tableSource = """
    69 adc imm 2|65 adc zp 3|75 adc zpx 4|6D adc abs 4|7D adc abx 4|79 adc aby 4|61 adc izx 6|71 adc izy 5
    29 and imm 2|25 and zp 3|35 and zpx 4|2D and abs 4|3D and abx 4|39 and aby 4|21 and izx 6|31 and izy 5
    0A asl acc 2|06 asl zp 5|16 asl zpx 6|0E asl abs 6|1E asl abx 7
    90 bcc rel 2|B0 bcs rel 2|F0 beq rel 2|30 bmi rel 2|D0 bne rel 2|10 bpl rel 2|50 bvc rel 2|70 bvs rel 2
    24 bit zp 3|2C bit abs 4|00 brk imp 7
    18 clc imp 2|D8 cld imp 2|58 cli imp 2|B8 clv imp 2
    C9 cmp imm 2|C5 cmp zp 3|D5 cmp zpx 4|CD cmp abs 4|DD cmp abx 4|D9 cmp aby 4|C1 cmp izx 6|D1 cmp izy 5
    E0 cpx imm 2|E4 cpx zp 3|EC cpx abs 4|C0 cpy imm 2|C4 cpy zp 3|CC cpy abs 4
    C6 dec zp 5|D6 dec zpx 6|CE dec abs 6|DE dec abx 7|CA dex imp 2|88 dey imp 2
    49 eor imm 2|45 eor zp 3|55 eor zpx 4|4D eor abs 4|5D eor abx 4|59 eor aby 4|41 eor izx 6|51 eor izy 5
    E6 inc zp 5|F6 inc zpx 6|EE inc abs 6|FE inc abx 7|E8 inx imp 2|C8 iny imp 2
    4C jmp abs 3|6C jmp ind 5|20 jsr abs 6
    A9 lda imm 2|A5 lda zp 3|B5 lda zpx 4|AD lda abs 4|BD lda abx 4|B9 lda aby 4|A1 lda izx 6|B1 lda izy 5
    A2 ldx imm 2|A6 ldx zp 3|B6 ldx zpy 4|AE ldx abs 4|BE ldx aby 4
    A0 ldy imm 2|A4 ldy zp 3|B4 ldy zpx 4|AC ldy abs 4|BC ldy abx 4
    4A lsr acc 2|46 lsr zp 5|56 lsr zpx 6|4E lsr abs 6|5E lsr abx 7|EA nop imp 2
    09 ora imm 2|05 ora zp 3|15 ora zpx 4|0D ora abs 4|1D ora abx 4|19 ora aby 4|01 ora izx 6|11 ora izy 5
    48 pha imp 3|08 php imp 3|68 pla imp 4|28 plp imp 4
    2A rol acc 2|26 rol zp 5|36 rol zpx 6|2E rol abs 6|3E rol abx 7
    6A ror acc 2|66 ror zp 5|76 ror zpx 6|6E ror abs 6|7E ror abx 7
    40 rti imp 6|60 rts imp 6
    E9 sbc imm 2|E5 sbc zp 3|F5 sbc zpx 4|ED sbc abs 4|FD sbc abx 4|F9 sbc aby 4|E1 sbc izx 6|F1 sbc izy 5
    38 sec imp 2|F8 sed imp 2|78 sei imp 2
    85 sta zp 3|95 sta zpx 4|8D sta abs 4|9D sta abx 5|99 sta aby 5|81 sta izx 6|91 sta izy 6
    86 stx zp 3|96 stx zpy 4|8E stx abs 4|84 sty zp 3|94 sty zpx 4|8C sty abs 4
    AA tax imp 2|A8 tay imp 2|BA tsx imp 2|8A txa imp 2|9A txs imp 2|98 tya imp 2
    """

    static let table: [OpInfo?] = {
        var t = [OpInfo?](repeating: nil, count: 256)
        let modes: [String: Mode] = ["imp": .imp, "acc": .acc, "imm": .imm, "zp": .zp, "zpx": .zpx, "zpy": .zpy,
                                     "abs": .abs, "abx": .abx, "aby": .aby, "izx": .izx, "izy": .izy,
                                     "ind": .ind, "rel": .rel]
        for item in tableSource.split(whereSeparator: { $0 == "|" || $0 == "\n" }) {
            let f = item.split(separator: " ")
            guard f.count == 4, let code = Int(f[0], radix: 16), let op = Op(rawValue: String(f[1])),
                  let mode = modes[String(f[2])], let cyc = UInt8(f[3]) else { continue }
            t[code] = OpInfo(op: op, mode: mode, cycles: cyc)
        }
        return t
    }()
}
