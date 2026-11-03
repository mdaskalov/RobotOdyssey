// Compares the MOS6502 package with AppleWin's 6502 on the random single
// instructions cpu_check_applewin.cpp ran (cpu_check.sh builds and runs both):
// registers, flags (B aside), cycles, the jam and every byte written.
//
// The differences where the package follows the 6502 rather than AppleWin
// are counted apart, as long as they are exactly those (README of the
// package): DCP's and ISC's carry when the operand wraps, ARR in decimal mode.
//
// Usage: cpu_check CASES.bin

import Foundation
import MOS6502

struct State: Equatable {
    var pc: UInt16, a: UInt8, x: UInt8, y: UInt8, p: UInt8, sp: UInt8
    var cycles: UInt32 = 0, jammed = false
    var writes: [UInt16: UInt8] = [:]
}

struct Reader {
    let data: Data
    var at = 0
    var atEnd: Bool { at >= data.count }
    mutating func byte() -> UInt8 { defer { at += 1 }; return data[at] }
    mutating func word() -> UInt16 { UInt16(byte()) | UInt16(byte()) << 8 }
    mutating func long() -> UInt32 { UInt32(word()) | UInt32(word()) << 16 }
    mutating func state() -> State { State(pc: word(), a: byte(), x: byte(), y: byte(), p: byte(), sp: byte()) }
}

@main
struct CPUCheck {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 2 else {
            print("usage: cpu_check CASES.bin")
            exit(2)
        }
        var reader = Reader(data: try Data(contentsOf: URL(fileURLWithPath: args[1])))
        let start = (0 ..< 0x10000).map { _ in reader.byte() }
        let cpu = CPU6502(memory: start)
        var cases = [Int](repeating: 0, count: 256)
        var expected = [Int](repeating: 0, count: 256)
        var unexpected = [Int](repeating: 0, count: 256)
        var examples: [String] = []

        while !reader.atEnd {
            let input = reader.state()
            let code = [reader.byte(), reader.byte(), reader.byte()]
            var appleWin = reader.state()
            appleWin.cycles = reader.long()
            appleWin.jammed = reader.byte() != 0
            for _ in 0 ..< reader.word() { appleWin.writes[reader.word()] = reader.byte() }
            appleWin.p &= ~CPU6502.Flag.brk

            if cpu.isJammed { cpu.reset() }
            cpu.mem = start
            cpu.mem.replaceSubrange(Int(input.pc) ..< Int(input.pc) + 3, with: code)
            let before = cpu.mem
            (cpu.pc, cpu.a, cpu.x, cpu.y, cpu.p, cpu.sp) = (input.pc, input.a, input.x, input.y, input.p, input.sp)
            cpu.cycles = 0
            var ours = State(pc: 0, a: 0, x: 0, y: 0, p: 0, sp: 0)
            do { try cpu.step() } catch CPU6502.CPUError.jammed { ours.jammed = true }
            (ours.pc, ours.a, ours.x, ours.y, ours.p, ours.sp) = (cpu.pc, cpu.a, cpu.x, cpu.y, cpu.p & ~CPU6502.Flag.brk, cpu.sp)
            ours.cycles = UInt32(cpu.cycles)
            cpu.mem.withUnsafeBufferPointer { now in
                before.withUnsafeBufferPointer { was in
                    for page in 0 ..< 256 where memcmp(now.baseAddress! + page * 256, was.baseAddress! + page * 256, 256) != 0 {
                        for i in page * 256 ..< page * 256 + 256 where now[i] != was[i] { ours.writes[UInt16(i)] = now[i] }
                    }
                }
            }

            let opcode = Opcode(code[0])
            cases[Int(code[0])] += 1
            guard ours != appleWin else { continue }
            if isKnownDifference(opcode, input, ours, appleWin) {
                expected[Int(code[0])] += 1
                continue
            }
            unexpected[Int(code[0])] += 1
            if examples.count < 30 {
                examples.append("\(hex(code[0])) \(opcode): in \(describe(input)) \(code.map(hex))\n"
                                + "    AppleWin \(describe(appleWin))\n    MOS6502  \(describe(ours))")
            }
        }

        let total = cases.reduce(0, +)
        print("\(total) instructions, \(cases.filter { $0 > 0 }.count) opcodes")
        for i in 0 ..< 256 where expected[i] > 0 {
            print("  \(hex(UInt8(i))) \(Opcode(UInt8(i))): \(expected[i]) of \(cases[i]) differ as expected (the 6502's result)")
        }
        let bad = unexpected.reduce(0, +)
        print(bad == 0 ? "no other differences" : "\(bad) UNEXPECTED DIFFERENCES")
        for example in examples { print(example) }
        exit(bad == 0 ? 0 : 1)
    }

    /// The package's results where it follows the 6502, not AppleWin.
    static func isKnownDifference(_ opcode: Opcode, _ input: State, _ ours: State, _ appleWin: State) -> Bool {
        var carryAside = appleWin
        carryAside.p = carryAside.p & ~CPU6502.Flag.carry | ours.p & CPU6502.Flag.carry
        switch opcode.mnemonic {
        case .dcp:      // $00 - 1 = $FF compared with A = $FF: C set; AppleWin compares with $FFFF
            return carryAside == ours && input.a == 0xFF && ours.writes.values.contains(0xFF)
        case .isc:      // $FF + 1 = $00 subtracted: C set unless A - borrow < 0; AppleWin subtracts $100
            return carryAside == ours && ours.writes.values.contains(0x00)
        case .arr:      // decimal fixes decided on the AND result; AppleWin decides on the rotated one
            return input.p & CPU6502.Flag.decimal != 0
        default:
            return false
        }
    }

    static func describe(_ s: State) -> String {
        let writes = s.writes.sorted { $0.key < $1.key }.map { "\(hex($0.key))=\(hex($0.value))" }.joined(separator: " ")
        return "PC=\(hex(s.pc)) A=\(hex(s.a)) X=\(hex(s.x)) Y=\(hex(s.y)) P=\(hex(s.p)) SP=\(hex(s.sp))"
            + " \(s.cycles) cycles\(s.jammed ? " JAM" : "") \(writes)"
    }

    static func hex<T: BinaryInteger>(_ v: T) -> String {
        let s = String(v, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, MemoryLayout<T>.size * 2 - s.count)) + s
    }
}
