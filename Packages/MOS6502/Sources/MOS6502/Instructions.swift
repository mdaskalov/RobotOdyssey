extension CPU6502 {
    /// Runs `opcode` (fetched from `address`) on `operand`; `end` is the cycle
    /// it ends on, which a branch taken moves.
    func execute(_ opcode: Opcode, _ operand: Operand, at address: UInt16) throws {
        let mode = opcode.mode
        switch opcode.mnemonic {
        // Loads and stores
        case .lda: a = nz(load(operand))
        case .ldx: x = nz(load(operand))
        case .ldy: y = nz(load(operand))
        case .sta: store(a, operand)
        case .stx: store(x, operand)
        case .sty: store(y, operand)

        // Arithmetic and logic
        case .adc: addWithCarry(load(operand))
        case .sbc: subtractWithBorrow(load(operand))
        case .and: a = nz(a & load(operand))
        case .ora: a = nz(a | load(operand))
        case .eor: a = nz(a ^ load(operand))
        case .cmp: compare(a, load(operand))
        case .cpx: compare(x, load(operand))
        case .cpy: compare(y, load(operand))
        case .bit:
            let value = load(operand)
            set(Flag.zero, a & value == 0)
            set(Flag.negative, value & 0x80 != 0)
            set(Flag.overflow, value & 0x40 != 0)

        // Shifts, rotations, increments and decrements
        case .asl: modify(mode, operand) { shiftLeft($0) }
        case .lsr: modify(mode, operand) { shiftRight($0) }
        case .rol: modify(mode, operand) { rotateLeft($0) }
        case .ror: modify(mode, operand) { rotateRight($0) }
        case .inc: modify(mode, operand) { nz($0 &+ 1) }
        case .dec: modify(mode, operand) { nz($0 &- 1) }
        case .inx: x = nz(x &+ 1)
        case .iny: y = nz(y &+ 1)
        case .dex: x = nz(x &- 1)
        case .dey: y = nz(y &- 1)

        // Register transfers
        case .tax: x = nz(a)
        case .tay: y = nz(a)
        case .txa: a = nz(x)
        case .tya: a = nz(y)
        case .tsx: x = nz(sp)
        case .txs: sp = x

        // Stack
        case .pha: push(a)
        case .php: push(p | Flag.brk | Flag.unused)
        case .pla: a = nz(pull())
        case .plp: p = pullStatus()

        // Jumps, subroutines and interrupts
        case .jmp: pc = operand.address
        case .jsr: jumpToSubroutine()
        case .rts: returnFromSubroutine()
        case .rti:
            p = pullStatus()
            pc = pullWord()
        case .brk:
            pc &+= 1                            // skips the byte after BRK
            interrupt(through: 0xFFFE, pushing: p | Flag.brk | Flag.unused)

        // Branches
        case .bpl: branch(to: operand, if: !isSet(Flag.negative))
        case .bmi: branch(to: operand, if: isSet(Flag.negative))
        case .bvc: branch(to: operand, if: !isSet(Flag.overflow))
        case .bvs: branch(to: operand, if: isSet(Flag.overflow))
        case .bcc: branch(to: operand, if: !isSet(Flag.carry))
        case .bcs: branch(to: operand, if: isSet(Flag.carry))
        case .bne: branch(to: operand, if: !isSet(Flag.zero))
        case .beq: branch(to: operand, if: isSet(Flag.zero))

        // Flags
        case .clc: set(Flag.carry, false)
        case .sec: set(Flag.carry, true)
        case .cli: set(Flag.interrupt, false)
        case .sei: set(Flag.interrupt, true)
        case .cld: set(Flag.decimal, false)
        case .sed: set(Flag.decimal, true)
        case .clv: set(Flag.overflow, false)

        case .nop: if mode != .implied { _ = load(operand) }

        // Undocumented (UndocumentedInstructions.swift)
        case .slo: a = nz(a | modify(mode, operand) { shiftLeft($0) })
        case .rla: a = nz(a & modify(mode, operand) { rotateLeft($0) })
        case .sre: a = nz(a ^ modify(mode, operand) { shiftRight($0) })
        case .rra: addWithCarry(modify(mode, operand) { rotateRight($0) })
        case .dcp: compare(a, modify(mode, operand) { $0 &- 1 })
        case .isc: subtractWithBorrow(modify(mode, operand) { $0 &+ 1 })
        case .lax: lax(operand)
        case .sax: store(a & x, operand)
        case .las: las(operand)
        case .sha: storeANDHighByte(a & x, operand)
        case .shx: storeANDHighByte(x, operand)
        case .shy: storeANDHighByte(y, operand)
        case .tas: tas(operand)
        case .anc: anc(operand)
        case .alr: alr(operand)
        case .arr: arr(operand)
        case .ane: ane(operand)
        case .lxa: lxa(operand)
        case .sbx: sbx(operand)
        case .jam:
            pc = address
            isJammed = true
            throw CPUError.jammed(at: address)
        }
    }

    /// JSR pushes the address of its own last byte (RTS adds 1) and jumps.  The
    /// 6502 reads the target's high byte only after the pushes, which can
    /// overwrite it (AppleWin GH#1257).
    func jumpToSubroutine() {
        let low = fetch()
        pushWord(pc)
        pc = UInt16(read(pc)) << 8 | UInt16(low)
    }

    /// A branch taken takes a cycle more, two when it lands on another page
    /// than the next instruction's.
    func branch(to target: Operand, if condition: Bool) {
        guard condition else { return }
        end += target.address & 0xFF00 == pc & 0xFF00 ? 1 : 2
        pc = target.address
    }
}
