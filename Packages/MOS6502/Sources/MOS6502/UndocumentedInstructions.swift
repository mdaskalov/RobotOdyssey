/// The NMOS 6502's undocumented instructions: what two documented ones do at
/// once, on one operand, because their opcodes switch on both units.  The
/// read-modify-write pairs (SLO = ASL + ORA, RLA, SRE, RRA, DCP, ISC) and SAX
/// are one line each in `execute`; the rest are here.
///
/// The results are the 6502's ("No More Secrets", VICE), which AppleWin's
/// differ from for DCP and ISC when the operand wraps (it keeps 16 bits:
/// DCP of $00 with A = $FF gives C = 0, ISC of $FF gives C = 0) and for ARR in
/// decimal mode (it decides the fixes on the rotated value).  ANE and LXA take
/// AppleWin's magic constants; real chips differ.
extension CPU6502 {
    /// LAX: LDA and LDX.
    func lax(_ operand: Operand) {
        a = nz(load(operand))
        x = a
    }

    /// LAS: A, X and SP = operand AND SP.
    func las(_ operand: Operand) {
        let value = nz(load(operand) & sp)
        (a, x, sp) = (value, value, value)
    }

    /// TAS: SP = A AND X, then stored like SHA.
    func tas(_ operand: Operand) {
        sp = a & x
        storeANDHighByte(sp, operand)
    }

    /// SHA, SHX, SHY, TAS: store `value` AND (the address's high byte before
    /// the index + 1).  When the index crosses a page the 6502 also puts that
    /// result on the address's high byte.
    func storeANDHighByte(_ value: UInt8, _ operand: Operand) {
        let result = value & (operand.baseHigh &+ 1)
        var target = operand
        if operand.crossesPage { target.address = UInt16(result) << 8 | operand.address & 0x00FF }
        store(result, target)
    }

    /// ANC: AND, then C = N.
    func anc(_ operand: Operand) {
        a = nz(a & load(operand))
        set(Flag.carry, isSet(Flag.negative))
    }

    /// ALR: AND, then LSR A.
    func alr(_ operand: Operand) {
        a = shiftRight(a & load(operand))
    }

    /// ARR: AND, then ROR A, with C = bit 6 and V = bit 6 XOR bit 5 of the
    /// result.  In decimal mode N and Z are the rotated value's, V is whether
    /// bit 6 changed in the rotation, and each digit of the AND result above 5
    /// (counting an odd one up) gets its digit of the rotated value fixed by 6;
    /// a fixed high digit sets C.
    func arr(_ operand: Operand) {
        let value = a & load(operand)
        var result = nz(value >> 1 | carry << 7)
        guard isSet(Flag.decimal) else {
            set(Flag.carry, result & 0x40 != 0)
            set(Flag.overflow, (result ^ result << 1) & 0x40 != 0)
            a = result
            return
        }
        set(Flag.overflow, (result ^ value) & 0x40 != 0)
        let (low, high) = (Int(value & 0x0F), Int(value & 0xF0))
        if low + low & 0x01 > 0x05 { result = result & 0xF0 | (result &+ 0x06) & 0x0F }
        let fixesHigh = high + high & 0x10 > 0x50
        if fixesHigh { result &+= 0x60 }
        set(Flag.carry, fixesHigh)
        a = result
    }

    /// ANE (XAA): A = (A OR magic) AND X AND operand.  The magic constant
    /// varies between chips; AppleWin takes $FF.
    func ane(_ operand: Operand) {
        a = nz((a | 0xFF) & x & load(operand))
    }

    /// LXA: A = X = (A OR magic) AND operand.  The magic constant varies
    /// between chips; AppleWin takes $EE.
    func lxa(_ operand: Operand) {
        a = nz((a | 0xEE) & load(operand))
        x = a
    }

    /// SBX: X = (A AND X) - operand, flags as CMP (no borrow in, no V, no
    /// decimal mode).
    func sbx(_ operand: Operand) {
        let value = load(operand)
        let ax = a & x
        set(Flag.carry, ax >= value)
        x = nz(ax &- value)
    }
}
