/// Where an instruction's operand is.
struct Operand {
    var address: UInt16
    /// The index carried into the address's high byte (abs,X, abs,Y, (zp),Y).
    var crossesPage = false
    /// The address's high byte before the index: SHA, SHX, SHY and TAS store a
    /// value ANDed with it + 1.
    var baseHigh: UInt8 = 0
}

extension CPU6502 {
    // MARK: finding the operand

    /// Fetches the operand bytes after the opcode (`pc` is past it) and works
    /// out where the operand is.
    func operand(_ opcode: Opcode) -> Operand {
        switch opcode.mode {
        case .implied, .accumulator:
            return Operand(address: 0)
        case .immediate:
            defer { pc &+= 1 }
            return Operand(address: pc)
        case .zeroPage:
            return Operand(address: UInt16(fetch()))
        case .zeroPageX:
            return Operand(address: UInt16(fetch() &+ x))
        case .zeroPageY:
            return Operand(address: UInt16(fetch() &+ y))
        case .absolute where opcode.mnemonic == .jsr:
            return Operand(address: pc)         // JSR reads its address itself, half before its pushes
        case .absolute:
            return Operand(address: fetchWord())
        case .absoluteX:
            return indexed(fetchWord(), by: x)
        case .absoluteY:
            return indexed(fetchWord(), by: y)
        case .indirectX:
            return Operand(address: zeroPageWord(fetch() &+ x))
        case .indirectY:
            return indexed(zeroPageWord(fetch()), by: y)
        case .indirect:
            let pointer = fetchWord()
            let highByte = pointer & 0xFF00 | UInt16(UInt8(pointer & 0xFF) &+ 1)     // no carry: the NMOS bug
            return Operand(address: UInt16(read(pointer)) | UInt16(read(highByte)) << 8)
        case .relative:
            let offset = Int8(bitPattern: fetch())
            return Operand(address: pc &+ UInt16(bitPattern: Int16(offset)))
        }
    }

    func fetch() -> UInt8 {
        defer { pc &+= 1 }
        return read(pc)
    }

    func fetchWord() -> UInt16 {
        UInt16(fetch()) | UInt16(fetch()) << 8
    }

    /// The address at `pointer` in the zero page; at $FF the high byte comes
    /// from $00.
    func zeroPageWord(_ pointer: UInt8) -> UInt16 {
        UInt16(read(UInt16(pointer))) | UInt16(read(UInt16(pointer &+ 1))) << 8
    }

    func indexed(_ base: UInt16, by index: UInt8) -> Operand {
        let address = base &+ UInt16(index)
        return Operand(address: address, crossesPage: address & 0xFF00 != base & 0xFF00, baseHigh: UInt8(base >> 8))
    }

    // MARK: reading and writing it, on the 6502's cycles

    /// Reads the operand, on the instruction's last cycle.
    func load(_ operand: Operand) -> UInt8 {
        cycles = end - 1
        return read(operand.address)
    }

    /// Writes the operand, on the instruction's last cycle.
    func store(_ value: UInt8, _ operand: Operand) {
        cycles = end - 1
        write(operand.address, value)
    }

    /// Read-modify-write (ASL, INC, ..., SLO, DCP, ...): reads the operand
    /// three cycles before the end, writes `change`'s result on the last cycle
    /// and returns it.  The 6502 writes the old value back on the cycle
    /// between; AppleWin doesn't, nor does this.  The accumulator form (ASL A)
    /// doesn't touch memory.
    @discardableResult
    func modify(_ mode: AddressingMode, _ operand: Operand, _ change: (UInt8) -> UInt8) -> UInt8 {
        if mode == .accumulator {
            a = change(a)
            return a
        }
        cycles = end - 3
        let value = change(read(operand.address))
        cycles = end - 1
        write(operand.address, value)
        return value
    }
}
