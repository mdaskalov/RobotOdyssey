/// The NMOS 6502 of the Apple II and //e, as AppleWin (and so Mariani) runs it:
/// all 256 opcodes, the undocumented ones included, and their cycles.
///
/// Runs one instruction at a time (`step`) over a flat 64K `mem`; the pages
/// marked in `ioPages` go to `ioRead`/`ioWrite` instead (soft switches,
/// devices).  An instruction makes the accesses its operation needs (a read, a
/// write, or a read and then a write) on the cycles the 6502 makes them, and
/// none of the 6502's dummy accesses, as in AppleWin.  Where AppleWin's
/// results differ from the 6502's, the 6502's (README.md).
///
/// The state is `@exclusivity(unchecked)`: Swift's run-time checks of class
/// properties made `step` three times slower, and no access to them lasts
/// across a call that could come back to them (`ioRead` may read `cycles`,
/// switch banks in `mem`).
public final class CPU6502 {
    // MARK: registers

    @exclusivity(unchecked) public var a: UInt8 = 0
    @exclusivity(unchecked) public var x: UInt8 = 0
    @exclusivity(unchecked) public var y: UInt8 = 0
    /// The stack is at $0100 + sp, growing down.
    @exclusivity(unchecked) public var sp: UInt8 = 0xFF
    /// Status, bits by `Flag`.  B is never set here, only in the copy that PHP
    /// and BRK push.
    @exclusivity(unchecked) public var p: UInt8 = Flag.unused | Flag.interrupt
    @exclusivity(unchecked) public var pc: UInt16 = 0

    /// Cycles run.  Between instructions the cycle the next starts on.  While
    /// an instruction reads or writes memory, the cycle of that access: the
    /// instruction's last, but for a read-modify-write's read, two cycles
    /// before its write (`load`, `store`, `modify`).
    @exclusivity(unchecked) public var cycles: UInt64 = 0

    /// A JAM opcode halted the CPU; `step` keeps throwing `CPUError.jammed`
    /// until `reset`.
    public internal(set) var isJammed = false

    /// Throw `CPUError.brk` at a BRK instead of running it (push PC and status,
    /// set I, go through the vector at $FFFE): for hosts without a ROM behind
    /// the vector, where a BRK means the code went astray.
    public var stopsAtBRK = false

    // MARK: memory

    @exclusivity(unchecked) public var mem: [UInt8]
    /// Pages ($xx00-$xxFF) whose reads and writes go to `ioRead`/`ioWrite`
    /// instead of `mem` ($C0 on the Apple II).
    @exclusivity(unchecked) public var ioPages = [Bool](repeating: false, count: 256)
    public var ioRead: (UInt16) -> UInt8 = { _ in 0 }
    public var ioWrite: (UInt16, UInt8) -> Void = { _, _ in }

    /// Addresses where `onTrap` is asked first, before the instruction there
    /// runs.  It returns true when it handled the instruction (e.g. ran a
    /// native routine and returned).
    @exclusivity(unchecked) public var traps = [Bool](repeating: false, count: 0x10000)
    public var onTrap: (UInt16) -> Bool = { _ in false }

    /// The cycle the running instruction ends on: its start + `Opcode.cycles`
    /// + the extras.
    @exclusivity(unchecked) var end: UInt64 = 0

    public enum CPUError: Error {
        /// A JAM opcode at the address halted the CPU.
        case jammed(at: UInt16)
        /// A BRK at the address, with `stopsAtBRK` set.
        case brk(at: UInt16)
        /// `call` ran out of steps.
        case tooManySteps(pc: UInt16)
    }

    public init(memory: [UInt8]) {
        precondition(memory.count == 0x10000)
        mem = memory
    }

    // MARK: memory and stack

    @inline(__always) public func read(_ address: UInt16) -> UInt8 {
        ioPages[Int(address >> 8)] ? ioRead(address) : mem[Int(address)]
    }

    @inline(__always) public func write(_ address: UInt16, _ value: UInt8) {
        if ioPages[Int(address >> 8)] { ioWrite(address, value) } else { mem[Int(address)] = value }
    }

    /// The little-endian word at `address`: vectors.
    public func readWord(_ address: UInt16) -> UInt16 {
        UInt16(read(address)) | UInt16(read(address &+ 1)) << 8
    }

    public func push(_ value: UInt8) {
        mem[0x100 + Int(sp)] = value
        sp &-= 1
    }

    public func pull() -> UInt8 {
        sp &+= 1
        return mem[0x100 + Int(sp)]
    }

    func pushWord(_ value: UInt16) {
        push(UInt8(value >> 8))
        push(UInt8(value & 0xFF))
    }

    func pullWord() -> UInt16 {
        UInt16(pull()) | UInt16(pull()) << 8
    }

    /// What RTS does: return to the address on the stack + 1.
    public func returnFromSubroutine() {
        pc = pullWord() &+ 1
    }

    // MARK: running

    /// Runs the instruction at `pc`, or the trap there when `onTrap` takes it.
    public func step() throws {
        if traps[Int(pc)], onTrap(pc) { return }
        let address = pc
        let opcode = Opcode(read(pc))
        if opcode.mnemonic == .brk, stopsAtBRK { throw CPUError.brk(at: address) }
        pc &+= 1
        let operand = operand(opcode)
        end = cycles + UInt64(opcode.cycles) + (opcode.addsCycleOnPageCross && operand.crossesPage ? 1 : 0)
        defer { cycles = end }
        try execute(opcode, operand, at: address)
    }

    /// JSR to `address` and run until it returns or PC reaches one of `stopAt`.
    @discardableResult
    public func call(_ address: UInt16, stopAt: Set<UInt16> = [], maxSteps: Int = 5_000_000) throws -> UInt16 {
        pushWord(0xFFFE)                        // RTS lands on $FFFF: the sentinel
        pc = address
        for _ in 0 ..< maxSteps {
            if pc == 0xFFFF || stopAt.contains(pc) { return pc }
            try step()
        }
        throw CPUError.tooManySteps(pc: pc)
    }

    // MARK: reset and interrupts

    /// The RESET line: the 6502 runs an interrupt's pushes without writing
    /// (SP goes down by 3), sets I and goes to the vector at $FFFC; 7 cycles.
    public func reset() {
        sp &-= 3
        p |= Flag.interrupt
        pc = readWord(0xFFFC)
        isJammed = false
        cycles += 7
    }

    /// The IRQ line: unless I is set, pushes PC and the status (B clear), sets
    /// I and goes to the vector at $FFFE; 7 cycles.  Whether it was taken.
    @discardableResult
    public func irq() -> Bool {
        guard p & Flag.interrupt == 0 else { return false }
        interrupt(through: 0xFFFE, pushing: p & ~Flag.brk | Flag.unused)
        cycles += 7
        return true
    }

    /// The NMI line: as `irq`, whatever I is, through the vector at $FFFA.
    public func nmi() {
        interrupt(through: 0xFFFA, pushing: p & ~Flag.brk | Flag.unused)
        cycles += 7
    }

    /// BRK, IRQ and NMI: push PC and `status`, set I, go through `vector`.  The
    /// NMOS 6502 leaves D as it is.
    func interrupt(through vector: UInt16, pushing status: UInt8) {
        pushWord(pc)
        push(status)
        p |= Flag.interrupt
        pc = readWord(vector)
    }
}
