import Testing
@testable import MOS6502

/// A CPU with `code` at $0300, PC there.
private func cpu(_ code: [UInt8], at origin: Int = 0x0300) -> CPU6502 {
    var mem = [UInt8](repeating: 0, count: 0x10000)
    mem.replaceSubrange(origin ..< origin + code.count, with: code)
    let cpu = CPU6502(memory: mem)
    cpu.pc = UInt16(origin)
    return cpu
}

/// Cycles one instruction takes.
private func cycles(_ cpu: CPU6502) throws -> UInt64 {
    let start = cpu.cycles
    try cpu.step()
    return cpu.cycles - start
}

@Suite struct OpcodeTable {
    @Test func everyByteHasItsOpcode() {
        #expect(Opcode.table.count == 256)
        for (i, opcode) in Opcode.table.enumerated() { #expect(Int(opcode.byte) == i) }
        #expect(Opcode.table.filter(\.isDocumented).count == 151)
        #expect(Opcode.table.filter { $0.mnemonic == .jam }.count == 12)
    }

    @Test func pageCrossCycleOnlyForIndexedReads() {
        #expect(Opcode(0xBD).addsCycleOnPageCross)          // LDA abs,X
        #expect(Opcode(0xB1).addsCycleOnPageCross)          // LDA (zp),Y
        #expect(Opcode(0xBF).addsCycleOnPageCross)          // LAX abs,Y
        #expect(!Opcode(0x9D).addsCycleOnPageCross)         // STA abs,X
        #expect(!Opcode(0xFE).addsCycleOnPageCross)         // INC abs,X
        #expect(!Opcode(0xB5).addsCycleOnPageCross)         // LDA zp,X
        #expect(Opcode(0xBD).description == "LDA abs,X")
    }
}

@Suite struct Cycles {
    @Test func indexedReadCrossingAPage() throws {
        let c = cpu([0xBD, 0xFF, 0x20, 0xBD, 0x00, 0x20])  // LDA $20FF,X  LDA $2000,X
        c.x = 1
        #expect(try cycles(c) == 5)
        #expect(try cycles(c) == 4)
    }

    @Test func indexedWriteAlwaysTakesTheLongWay() throws {
        let c = cpu([0x9D, 0x00, 0x20])                     // STA $2000,X
        #expect(try cycles(c) == 5)
    }

    @Test func branches() throws {
        let c = cpu([0xD0, 0x01, 0xEA, 0xF0, 0x02, 0xD0, 0x7F], at: 0x03F8)
        c.p &= ~CPU6502.Flag.zero
        #expect(try cycles(c) == 3)                         // BNE taken, same page
        #expect(c.pc == 0x03FB)
        #expect(try cycles(c) == 2)                         // BEQ not taken
        #expect(try cycles(c) == 4)                         // BNE from $03FF to $047E
        #expect(c.pc == 0x047E)
    }

    @Test func accessesHappenOnTheirBusCycles() throws {
        let c = cpu([0xAD, 0x30, 0xC0, 0xEE, 0x30, 0xC0, 0x9D, 0x30, 0xC0])  // LDA $C030  INC $C030  STA $C030,X
        c.ioPages[0xC0] = true
        var accesses: [(String, UInt64)] = []
        c.ioRead = { _ in accesses.append(("read", c.cycles)); return 0 }
        c.ioWrite = { _, _ in accesses.append(("write", c.cycles)) }
        try c.step()
        try c.step()
        try c.step()
        #expect(accesses.map(\.0) == ["read", "read", "write", "write"])
        let expected: [UInt64] = [3, 4 + 3, 4 + 5, 10 + 4]  // LDA: its 4th cycle; INC: its 4th and 6th; STA: its 5th
        #expect(accesses.map(\.1) == expected)
        #expect(c.cycles == 15)
    }
}

@Suite struct Documented {
    @Test func jmpIndirectDoesNotCarryIntoThePointersHighByte() throws {
        let c = cpu([0x6C, 0xFF, 0x12])                     // JMP ($12FF)
        c.mem[0x12FF] = 0x34
        c.mem[0x1200] = 0x56
        c.mem[0x1300] = 0x99
        try c.step()
        #expect(c.pc == 0x5634)
    }

    @Test func zeroPageIndexingWraps() throws {
        let c = cpu([0xB5, 0xFF, 0xA1, 0xFF, 0xB1, 0xFF])   // LDA $FF,X  LDA ($FF,X)  LDA ($FF),Y
        c.x = 2
        c.mem[0x0001] = 0x00                                // $01: pointer to $4200
        c.mem[0x0002] = 0x42
        c.mem[0x4200] = 0x77
        try c.step()
        #expect(c.a == 0x00)
        try c.step()
        #expect(c.a == 0x77)
        c.mem[0x00FF] = 0x00                                // $FF: pointer to $4200, high byte from $00
        c.mem[0x0000] = 0x42
        c.y = 1
        c.mem[0x4201] = 0x88
        try c.step()
        #expect(c.a == 0x88)
    }

    @Test func decimalAddFlagsAreTheNMOSOnes() throws {
        let c = cpu([0xF8, 0x18, 0xA9, 0x99, 0x69, 0x01])   // SED  CLC  LDA #$99  ADC #$01
        for _ in 0 ..< 4 { try c.step() }
        #expect(c.a == 0x00)
        #expect(c.p & CPU6502.Flag.carry != 0)
        #expect(c.p & CPU6502.Flag.zero == 0)               // Z from the binary sum $9A
        #expect(c.p & CPU6502.Flag.negative != 0)           // N from $A0 before the high digit's fix
    }

    @Test func decimalSubtract() throws {
        let c = cpu([0xF8, 0x38, 0xA9, 0x10, 0xE9, 0x01])   // SED  SEC  LDA #$10  SBC #$01
        for _ in 0 ..< 4 { try c.step() }
        #expect(c.a == 0x09)
        #expect(c.p & CPU6502.Flag.carry != 0)
    }

    @Test func jsrAndRts() throws {
        let c = cpu([0x20, 0x00, 0x04])                     // JSR $0400
        c.mem[0x0400] = 0x60                                // RTS
        #expect(try cycles(c) == 6)
        #expect(c.pc == 0x0400)
        #expect(c.mem[0x01FF] == 0x03 && c.mem[0x01FE] == 0x02)
        #expect(try cycles(c) == 6)
        #expect(c.pc == 0x0303)
    }

    @Test func brkPushesBAndRtiReturnsPastItsByte() throws {
        let c = cpu([0x00, 0xEA, 0xEA])                     // BRK  (signature)  NOP
        c.mem[0xFFFE] = 0x00
        c.mem[0xFFFF] = 0x05
        c.mem[0x0500] = 0x40                                // RTI
        #expect(try cycles(c) == 7)
        #expect(c.pc == 0x0500)
        #expect(c.mem[0x01FD] & CPU6502.Flag.brk != 0)
        #expect(c.p & CPU6502.Flag.interrupt != 0)
        try c.step()
        #expect(c.pc == 0x0302)
        #expect(c.p & CPU6502.Flag.brk == 0)
    }

    @Test func stopsAtBRKWhenAsked() {
        let c = cpu([0x00])
        c.stopsAtBRK = true
        #expect(throws: CPU6502.CPUError.self) { try c.step() }
        #expect(c.pc == 0x0300)
    }

    @Test func irqWaitsForI() {
        let c = cpu([0xEA])
        c.mem[0xFFFE] = 0x00
        c.mem[0xFFFF] = 0x06
        #expect(!c.irq())
        c.p &= ~CPU6502.Flag.interrupt
        #expect(c.irq())
        #expect(c.pc == 0x0600)
        #expect(c.mem[0x01FD] & CPU6502.Flag.brk == 0)
    }
}

@Suite struct Undocumented {
    @Test func jamHaltsUntilReset() throws {
        let c = cpu([0x02])
        #expect(throws: CPU6502.CPUError.self) { try c.step() }
        #expect(c.isJammed && c.pc == 0x0300 && c.cycles == 2)
        c.reset()
        #expect(!c.isJammed)
    }

    @Test func dcpComparesTheWrappedByte() throws {
        let c = cpu([0xC7, 0x10])                           // DCP $10
        c.a = 0xFF
        try c.step()
        #expect(c.mem[0x10] == 0xFF)
        #expect(c.p & CPU6502.Flag.carry != 0)              // AppleWin: clear
        #expect(c.p & CPU6502.Flag.zero != 0)
    }

    @Test func iscSubtractsTheWrappedByte() throws {
        let c = cpu([0x38, 0xE7, 0x10])                     // SEC  ISC $10
        c.mem[0x10] = 0xFF
        c.a = 0x42
        try c.step()
        try c.step()
        #expect(c.mem[0x10] == 0x00)
        #expect(c.a == 0x42)
        #expect(c.p & CPU6502.Flag.carry != 0)              // AppleWin: clear
    }

    @Test func laxSaxSbx() throws {
        let c = cpu([0xA7, 0x10, 0x87, 0x11, 0xCB, 0x01])   // LAX $10  SAX $11  SBX #$01
        c.mem[0x10] = 0x8F
        try c.step()
        #expect(c.a == 0x8F && c.x == 0x8F && c.p & CPU6502.Flag.negative != 0)
        c.a = 0xF0
        try c.step()
        #expect(c.mem[0x11] == 0x80)
        try c.step()
        #expect(c.x == 0x7F && c.p & CPU6502.Flag.carry != 0)
    }

    @Test func shaPutsItsValueOnTheHighByteWhenCrossingAPage() throws {
        let c = cpu([0x9F, 0xF0, 0x12, 0x9F, 0x00, 0x12])   // SHA $12F0,Y  SHA $1200,Y
        (c.a, c.x, c.y) = (0xFF, 0x0F, 0x20)
        try c.step()
        #expect(c.mem[0x0310] == 0x03)                      // $0F AND $13 = $03, at $0310 not $1310
        try c.step()
        #expect(c.mem[0x1220] == 0x03)
    }

    @Test func arrInDecimalModeFixesByTheANDResult() throws {
        let c = cpu([0xF8, 0x18, 0xA9, 0xFF, 0x6B, 0x66])   // SED  CLC  LDA #$FF  ARR #$66
        for _ in 0 ..< 4 { try c.step() }
        // $66 >> 1 = $33; low digit 6 > 5: $39; high digit 6 > 5: $99, C set
        #expect(c.a == 0x99)
        #expect(c.p & CPU6502.Flag.carry != 0)
    }

    @Test func nopsReadTheirOperand() throws {
        let c = cpu([0x0C, 0x30, 0xC0, 0x1A])               // NOP $C030  NOP
        c.ioPages[0xC0] = true
        var reads = 0
        c.ioRead = { _ in reads += 1; return 0 }
        #expect(try cycles(c) == 4)
        #expect(try cycles(c) == 2)
        #expect(reads == 1)
    }
}
