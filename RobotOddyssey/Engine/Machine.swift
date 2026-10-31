import Foundation

/// A native routine: runs on the machine's memory, registers and input
/// devices when the 6502 code reaches its entry point, and returns like RTS.
/// It may decline (return false, having changed nothing), and the original
/// code runs instead.
typealias Native = (inout NativeState) -> Bool

/// What a native routine works on.
struct NativeState {
    var ram: RAM
    var registers: Registers
    var devices: InputDevices
    /// The CPU's cycle counter at the call (a native routine takes no time).
    let cycles: UInt64
}

/// The Apple IIe as Robot Odyssey uses it, running the original code from the
/// disks: 64K of main RAM, the language card's two $D000 banks, the soft
/// switches the game touches, its input devices, and native Swift routines in
/// place of engine routines that have been ported (`installNatives`).  A
/// native routine runs when the 6502 code reaches its entry point and returns
/// like RTS; it must leave memory exactly as the original does, and the
/// registers too where other code uses them (Data/native_check.swift).
final class Machine {
    let cpu: CPU6502
    /// The $D000-$DFFF bank that is not mapped in; bank 1 (engine data) while
    /// the engine code in bank 2 runs.
    private(set) var otherBank: [UInt8]
    private(set) var bank = 2
    /// Hi-res page on screen, 1 or 2 ($C054/$C055).
    private(set) var shownPage = 1
    private(set) var speakerClicks = 0
    /// Keyboard, joystick and buttons.
    var devices = InputDevices()
    /// Native routines by entry point (always in bank 2 when in $D000-$DFFF).
    private var natives: [UInt16: Native] = [:]
    /// Off: everything runs as 6502 code, for comparisons.
    var nativesEnabled = true
    private(set) var nativeCalls = 0

    init(memory: [UInt8], bank1: [UInt8]) {
        cpu = CPU6502(memory: memory)
        otherBank = bank1
        cpu.ioRead = { [unowned self] in io($0) }
        cpu.ioWrite = { [unowned self] a, _ in _ = io(a) }
        cpu.onTrap = { [unowned self] in runNative(at: $0) }
    }

    /// Bank 1 as it is now, wherever it is mapped.
    var bank1: [UInt8] { bank == 1 ? Array(cpu.mem[0xD000 ..< 0xE000]) : otherBank }

    /// An independent machine in the same state: memory, banks, registers,
    /// soft switches, devices and natives (the native call count starts at 0).
    func copy() -> Machine {
        let m = Machine(memory: cpu.mem, bank1: otherBank)
        m.bank = bank
        m.shownPage = shownPage
        m.devices = devices
        m.natives = natives
        m.nativesEnabled = nativesEnabled
        let c = m.cpu
        c.traps = cpu.traps
        (c.a, c.x, c.y, c.sp, c.p, c.pc, c.cycles) = (cpu.a, cpu.x, cpu.y, cpu.sp, cpu.p, cpu.pc, cpu.cycles)
        return m
    }

    private func io(_ a: UInt16) -> UInt8 {
        switch a {
        case 0xC000: return devices.key
        case 0xC010: devices.key &= 0x7F
        case 0xC030: speakerClicks += 1
        case 0xC054, 0xC055: shownPage = Int(a - 0xC054) + 1
        case 0xC061, 0xC062: return devices.buttons[Int(a - 0xC061)] ? 0x80 : 0
        case 0xC064 ... 0xC067: return devices.paddleRunning(Int(a - 0xC064), after: cpu.cycles &- devices.strobe) ? 0x80 : 0
        case 0xC070: devices.strobe = cpu.cycles
        case 0xC080 ... 0xC08F: select(bank: a & 0x08 != 0 ? 1 : 2)
        default: break
        }
        return 0
    }

    /// The game only ever uses language card RAM, so a bank switch swaps $D000-$DFFF.
    private func select(bank b: Int) {
        guard b != bank else { return }
        let mapped = Array(cpu.mem[0xD000 ..< 0xE000])
        cpu.mem.replaceSubrange(0xD000 ..< 0xE000, with: otherBank)
        otherBank = mapped
        bank = b
    }

    // MARK: native routines

    func install(at address: UInt16, _ routine: @escaping Native) {
        natives[address] = routine
        cpu.traps[Int(address)] = true
    }

    /// A routine that works on memory and registers and always runs.
    func install(at address: UInt16, _ routine: @escaping (inout RAM, inout Registers) -> Void) {
        install(at: address) { (s: inout NativeState) in
            routine(&s.ram, &s.registers)
            return true
        }
    }

    /// A routine whose callers use no registers it leaves.
    func install(at address: UInt16, _ routine: @escaping (inout RAM) -> Void) {
        install(at: address) { (s: inout NativeState) in
            routine(&s.ram)
            return true
        }
    }

    /// Native routines for the engine code in memory, matched by fingerprint;
    /// returns their names.  Install them after the world's start-up code, so
    /// the fingerprints see any patches it makes.
    @discardableResult
    func installNatives() -> [String] {
        var names: [String] = []
        if let layout = RobotDrawing.layout(in: cpu.mem) {
            let robots = RobotDrawing(layout: layout)
            install(at: layout.exterior, robots.drawExteriors)
            install(at: layout.interior, robots.drawInterior)
            names.append(String(format: "robots $%04X/$%04X (%@)", layout.exterior, layout.interior, layout.name))
        }
        if ObjectMotion.matches(cpu.mem) {
            for (entry, _, routine) in ObjectMotion.entries { install(at: entry, routine) }
            names.append("object motion " + ObjectMotion.entries.map { String(format: "$%04X", $0.0) }.joined(separator: "/"))
        }
        if PlayerInput.matches(cpu.mem) {
            install(at: PlayerInput.entry) { PlayerInput.readInput(&$0) }
            names.append(String(format: "input $%04X", PlayerInput.entry))
        }
        if let level = PlayerInput.LevelRoutines.find(in: cpu.mem) {
            install(at: level.walk) { PlayerInput.walk(&$0, &$1) }
            install(at: level.grab) { PlayerInput.grabButton(&$0, &$1) }
            install(at: level.keepMove) { PlayerInput.keepMove(&$0, &$1) }
            names.append(String(format: "player $%04X/$%04X/$%04X", level.walk, level.grab, level.keepMove))
        }
        return names
    }

    private func runNative(at pc: UInt16) -> Bool {
        guard nativesEnabled, !(0xD000 ..< 0xE000).contains(pc) || bank == 2,
              let routine = natives[pc], call(routine) else { return false }
        nativeCalls += 1
        cpu.returnFromSubroutine()
        return true
    }

    /// Runs a native routine on the machine as it is: its memory (moved, not
    /// copied), registers and devices.  False if the routine declined.
    @discardableResult
    func call(_ routine: Native) -> Bool {
        var s = NativeState(ram: RAM(bytes: []), registers: Registers(a: cpu.a, x: cpu.x, y: cpu.y, p: cpu.p),
                            devices: devices, cycles: cpu.cycles)
        swap(&s.ram.bytes, &cpu.mem)
        let done = routine(&s)
        swap(&s.ram.bytes, &cpu.mem)
        guard done else { return false }
        (cpu.a, cpu.x, cpu.y, cpu.p) = (s.registers.a, s.registers.x, s.registers.y, s.registers.p)
        devices = s.devices
        return true
    }

    /// Runs a native routine on the CPU's memory (moved, not copied).
    func run(_ routine: (inout RAM) -> Void) {
        var ram = RAM(bytes: [])
        swap(&ram.bytes, &cpu.mem)
        routine(&ram)
        swap(&ram.bytes, &cpu.mem)
    }

    // MARK: the hi-res pages

    /// The page on screen ($C054/$C055), top line first.
    func shownScreen() -> HiresScreen {
        var screen = HiresScreen()
        let base = shownPage == 1 ? 0x2000 : 0x4000
        for line in 0 ..< HiresScreen.height {
            let address = base + line % 8 * 0x400 + line / 8 % 8 * 0x80 + line / 64 * 0x28
            screen.bytes.replaceSubrange(line * 40 ..< line * 40 + 40, with: cpu.mem[address ..< address + 40])
        }
        return screen
    }

    /// The page the engine is drawing on, read through its line tables
    /// ($9839 and ($16)), top line first.
    func drawnScreen() -> HiresScreen {
        var screen = HiresScreen()
        let mem = cpu.mem
        let high = Int(mem[0x16]) | Int(mem[0x17]) << 8
        for line in 0 ..< HiresScreen.height {
            let y = 191 - line
            let address = Int(mem[RAM.lineLowBytes + y]) | Int(mem[high + y]) << 8
            screen.bytes.replaceSubrange(line * 40 ..< line * 40 + 40, with: mem[address ..< address + 40])
        }
        return screen
    }
}

/// Where a world's main loop draws: after it sets the current room to the
/// player's and asks whether the player looks out of a robot
/// (`LDA $6300 / STA $9C2D / JSR …`), up to `JSR FLIP_PAGE` ($AEED).  In
/// between come the engine's drawing routines and the world's own (sprites
/// of its puzzles, code rooms...).
struct DrawPhase {
    let start: Int
    let end: Int
    /// First instruction of the main loop (where the start-up code arrives).
    let loopStart: Int

    init?(in mem: [UInt8]) {
        guard let set = WorldBuilder.find([0xAD, 0x00, 0x63, 0x8D, 0x2D, 0x9C, 0x20], in: mem, from: 0x0803, to: 0x2000),
              let flip = WorldBuilder.find([0x20, 0xED, 0xAE], in: mem, from: set, to: 0x2000)
        else { return nil }
        // The loop ends with a JMP back to its start, a little after the flip.
        guard let jmp = (flip ..< flip + 0x40).first(where: { a in
            mem[a] == 0x4C && Int(mem[a + 1]) | Int(mem[a + 2]) << 8 < set && Int(mem[a + 2]) >= 0x08
        }) else { return nil }
        start = set + 9
        end = flip
        loopStart = Int(mem[jmp + 1]) | Int(mem[jmp + 2]) << 8
    }

    /// Runs the draw phase for `room` on `machine`, a world between two ticks,
    /// and returns the page drawn.
    func draw(room: Int, on machine: Machine) throws -> HiresScreen {
        machine.cpu.mem[RAM.currentRoom] = UInt8(room)
        machine.cpu.sp = 0xF0
        // A world's own loop (e.g. Level 5's transporter) may flip pages itself: stop there too.
        try machine.cpu.call(UInt16(start), stopAt: [UInt16(end), 0xAEED], maxSteps: 3_000_000)
        return machine.drawnScreen()
    }
}

/// Draws rooms the way the game does: the world's start-up code runs once
/// (all 6502 code), then for each room its draw phase (with `CUR_ROOM` set to
/// the room) on the 6502 emulator, with the native engine routines in place.
/// `loop` runs the main loop from there (GameLoop).
final class GameScreen {
    let phase: DrawPhase
    /// Native routines in use (shown in the viewer).
    let natives: [String]
    /// The world at the first instruction of its main loop.
    private let started: Machine

    enum Failure: LocalizedError {
        case noMainLoop
        var errorDescription: String? { "The world's main loop was not found." }
    }

    init(world: World) throws {
        guard let phase = DrawPhase(in: world.mem) else { throw Failure.noMainLoop }
        self.phase = phase
        let machine = Machine(memory: world.mem, bank1: world.bank1)
        // The random generator ($D429, a shift register in $4E/$4F) never leaves 0,
        // and Level 4 waits for a usable number.  On the Apple the monitor's
        // keyboard wait has stirred these bytes by the time a world starts.
        if machine.cpu.mem[0x4E] == 0 && machine.cpu.mem[0x4F] == 0 {
            machine.cpu.mem[0x4E] = 0x5A
            machine.cpu.mem[0x4F] = 0xA5
        }
        machine.cpu.sp = 0xFF
        try machine.cpu.call(0x0803, stopAt: [UInt16(phase.loopStart)], maxSteps: 2_000_000)
        natives = machine.installNatives()
        started = machine
    }

    /// Room `room` as the game draws it.  `nativesEnabled: false` runs every
    /// engine routine as 6502 code.
    func render(room: Int, nativesEnabled: Bool = true) throws -> (screen: HiresScreen, machine: Machine) {
        let machine = started.copy()
        machine.nativesEnabled = nativesEnabled
        return (try phase.draw(room: room, on: machine), machine)
    }

    /// The main loop, ready to run its first tick, drawing `room`.
    func loop(room: Int?, nativesEnabled: Bool = true) -> GameLoop {
        let machine = started.copy()
        machine.nativesEnabled = nativesEnabled
        return GameLoop(machine: machine, phase: phase, room: room)
    }
}
