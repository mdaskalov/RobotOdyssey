import Foundation

/// The Apple IIe as Robot Odyssey uses it, running the original code from the
/// disks: 64K of main RAM, the language card's two $D000 banks, the soft
/// switches the game touches, its input devices, and native Swift routines in
/// place of engine routines that have been ported (`install`, `Native`).  A
/// native routine runs when the 6502 code reaches its entry point and returns
/// like RTS; it must leave memory exactly as the original does, and the
/// registers too where other code uses them (Data/native_check.swift).
nonisolated final class Machine {
    /// The world's engine and version, where natives find their symbols; nil:
    /// an unknown version, everything runs as 6502 code.
    let variant: Variant?
    let cpu: CPU6502
    /// The $D000-$DFFF bank that is not mapped in; bank 1 (engine data) while
    /// the engine code in bank 2 runs.
    private(set) var otherBank: [UInt8]
    private(set) var bank = 2
    /// Hi-res page on screen, 1 or 2 ($C054/$C055).
    private(set) var shownPage = 1
    /// The CPU cycle of every speaker click ($C030), when not nil (Data/ro_sounds.sh).
    var clicks: [UInt64]?
    /// The sounds the native PLAY_SOUNDS played and nobody has taken yet.
    private var sounds: [Sound.Played] = []
    /// Keyboard, joystick and buttons.
    var devices = InputDevices()
    /// Native routines by entry point (always in bank 2 when in $D000-$DFFF).
    private var natives: [UInt16: (inout Engine) -> Bool] = [:]
    /// Off: everything runs as 6502 code, for comparisons.
    var nativesEnabled = true
    private(set) var nativeCalls = 0
    /// Called where DRAW_SPRITE starts, with the machine there, when set
    /// (`DrawPhase.sprites`).  The natives draw without it: it sees every
    /// sprite only with them off.
    var onDrawSprite: ((Machine) -> Void)? {
        didSet { cpu.traps[GameSymbols.address(\.drawSprite)] = true }
    }

    init(memory: [UInt8], bank1: [UInt8], variant: Variant?) {
        self.variant = variant
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
        let m = Machine(memory: cpu.mem, bank1: otherBank, variant: variant)
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
        case 0xC030: clicks?.append(cpu.cycles)
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

    /// Installs `natives` (the world's `CodeCheck` chose them); returns their
    /// names and entry points.
    @discardableResult
    func install(_ natives: [Native]) -> [(name: String, entry: UInt16)] {
        guard let variant else { return [] }
        return natives.compactMap { native in
            guard let entry = GameSymbols.map[keyPath: native.routine].entry(variant) else { return nil }
            install(at: entry, native.run)
            return (native.name, entry)
        }
    }

    func install(at address: UInt16, _ run: @escaping (inout Engine) -> Bool) {
        natives[address] = run
        cpu.traps[Int(address)] = true
    }

    private func runNative(at pc: UInt16) -> Bool {
        if let onDrawSprite, Int(pc) == GameSymbols.address(\.drawSprite) { onDrawSprite(self) }
        guard nativesEnabled, !(0xD000 ..< 0xE000).contains(pc) || bank == 2,
              let run = natives[pc], call(run) else { return false }
        nativeCalls += 1
        cpu.returnFromSubroutine()
        return true
    }

    /// Runs a native routine on the machine as it is: its memory (the CPU's
    /// own), registers and devices, and takes the time it reports.  False if
    /// the routine declined.
    @discardableResult
    func call(_ run: (inout Engine) -> Bool) -> Bool {
        guard let variant else { return false }
        let registers = Registers(a: cpu.a, x: cpu.x, y: cpu.y, p: cpu.p)
        let (devices, cycles) = (devices, cpu.cycles)
        let result = cpu.mem.withUnsafeMutableBufferPointer { bytes -> Engine? in
            var engine = Engine(m: RAM(bytes.baseAddress!, variant), r: registers, devices: devices, cycles: cycles)
            return run(&engine) ? engine : nil
        }
        guard let result else { return false }
        (cpu.a, cpu.x, cpu.y, cpu.p) = (result.r.a, result.r.x, result.r.y, result.r.p)
        self.devices = result.devices
        cpu.cycles += result.elapsed
        sounds += result.sounds
        return true
    }

    /// The sounds played since the last call, in order.
    func takeSounds() -> [Sound.Played] {
        defer { sounds = [] }
        return sounds
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
    /// (LINE_LOW_TABLE, LINE_HIGH_TABLE), top line first.
    func drawnScreen() -> HiresScreen {
        var screen = HiresScreen()
        let mem = cpu.mem
        let high = mem[\.lineHighTable]
        for line in 0 ..< HiresScreen.height {
            let y = 191 - line
            let address = Int(mem[\.lineLowTable, y]) | Int(mem[high + y]) << 8
            screen.bytes.replaceSubrange(line * 40 ..< line * 40 + 40, with: mem[address ..< address + 40])
        }
        return screen
    }
}

/// Where a world's main loop draws: after it sets the current room to the
/// player's and asks whether the player looks out of a robot
/// (`LDA OBJ_ROOM / STA CURRENT_ROOM / JSR PLAYER_IN_ROBOT`), up to
/// `JSR FLIP_PAGE`.  In between come the engine's drawing routines and the
/// world's own (sprites of its puzzles, code rooms...).
nonisolated struct DrawPhase {
    let start: Int
    let end: Int
    /// First instruction of the main loop (where the start-up code arrives).
    let loopStart: Int

    init?(in mem: [UInt8]) {
        let setRoom = WorldBuilder.instruction(0xAD, \.objRoom) + WorldBuilder.instruction(0x8D, \.currentRoom) + [0x20]
        guard let set = WorldBuilder.find(setRoom, in: mem, from: 0x0803, to: 0x2000),
              let flip = WorldBuilder.find(WorldBuilder.instruction(0x20, \.flipPage), in: mem, from: set, to: 0x2000)
        else { return nil }
        // The loop ends with a JMP back to its start, a little after the flip.
        guard let jmp = (flip ..< flip + 0x40).first(where: { a in
            mem[a] == 0x4C && Int(mem[a + 1]) | Int(mem[a + 2]) << 8 < set && Int(mem[a + 2]) >= 0x08
        }) else { return nil }
        start = set + 9
        end = flip
        loopStart = Int(mem[jmp + 1]) | Int(mem[jmp + 2]) << 8
    }

    /// The stack pointer the draw phase runs with (`draw`).
    private static let stack = 0xF0

    /// Runs the draw phase for `room` on `machine`, a world between two ticks,
    /// and returns the page drawn.
    func draw(room: Int, on machine: Machine) throws -> HiresScreen {
        machine.cpu.mem[\.currentRoom] = UInt8(room)
        machine.cpu.sp = UInt8(DrawPhase.stack)
        // A world's own loop (e.g. Level 5's transporter) may flip pages itself: stop there too.
        let flipPage = UInt16(GameSymbols.address(\.flipPage))
        try machine.cpu.call(UInt16(start), stopAt: [UInt16(end), flipPage], maxSteps: 3_000_000)
        return machine.drawnScreen()
    }

    /// Runs the draw phase for `room` like `draw`, all as 6502 code (the
    /// natives leave memory as it does, so it draws the same), and returns
    /// every sprite DRAW_SPRITE drew, in order.
    func sprites(room: Int, on machine: Machine) throws -> [DrawnSprite] {
        machine.nativesEnabled = false
        var sprites: [DrawnSprite] = []
        // `draw` calls the draw phase like JSR (the sentinel takes 2 bytes),
        // so the return address of each of its JSRs is at the bottom.
        let frame = 0x100 + DrawPhase.stack - 3
        machine.onDrawSprite = { [start, end] m in
            let mem = m.cpu.mem
            let jsr = (Int(mem[frame]) | Int(mem[frame + 1]) << 8) - 2
            let routine = (start ..< end).contains(jsr) && mem[jsr] == 0x20 ? Int(mem[jsr + 1]) | Int(mem[jsr + 2]) << 8 : nil
            sprites.append(DrawnSprite(mem, routine: routine))
        }
        defer { machine.onDrawSprite = nil }
        _ = try draw(room: room, on: machine)
        return sprites
    }
}

/// A sprite the draw phase drew: DRAW_SPRITE's parameters where it starts.
nonisolated struct DrawnSprite {
    /// SPRITE_POINTER, and the 16 rows there as drawn (row 0 at the bottom).
    let address: Int
    let rows: [UInt8]
    /// DRAW_X and DRAW_Y, in object coordinates (y from the bottom).
    let x, y: Int
    /// PATTERN_EVEN and PATTERN_ODD.
    let patterns: (even: UInt8, odd: UInt8)
    /// The colour with these patterns (COLOUR_PATTERN0/1), if one has them.
    let colour: Int?
    /// The draw phase's routine that drew it (the main loop calls them one
    /// after the other); nil if not found on the stack.
    let routine: Int?
    /// The object DRAW_ROOM_OBJECTS drew (CURRENT_OBJECT); nil for the others.
    let object: Int?

    init(_ mem: [UInt8], routine: Int?) {
        let address = mem[\.spritePointer]
        self.address = address
        rows = (0 ..< 16).map { mem[(address + $0) & 0xFFFF] }
        x = Int(mem[\.drawX])
        y = Int(mem[\.drawY])
        let patterns = (even: mem[\.patternEven], odd: mem[\.patternOdd])
        self.patterns = patterns
        colour = (0 ..< 0x20).first { mem[\.colourPattern0, $0] == patterns.even && mem[\.colourPattern1, $0] == patterns.odd }
        self.routine = routine
        object = routine == GameSymbols.address(\.drawRoomObjects) ? Int(mem[\.currentObject]) : nil
    }
}

/// Draws rooms the way the game does: the world's start-up code runs once
/// (all 6502 code), then for each room its draw phase (with CURRENT_ROOM set
/// to the room) on the 6502 emulator, with the native engine routines in
/// place: those the loader's `CodeCheck` found the code for.
/// `loop` runs the main loop from there (GameLoop).
nonisolated final class GameScreen {
    let phase: DrawPhase
    /// Native routines in use, with their entry points (shown in the viewer).
    let natives: [(name: String, entry: UInt16)]
    /// The world at the first instruction of its main loop.
    private let started: Machine

    enum Failure: LocalizedError {
        case noMainLoop
        var errorDescription: String? { "The world's main loop was not found." }
    }

    init(world: World) throws {
        guard let phase = DrawPhase(in: world.mem) else { throw Failure.noMainLoop }
        self.phase = phase
        let machine = Machine(memory: world.mem, bank1: world.bank1, variant: world.codeCheck?.variant)
        // The random generator (RANDOM, a shift register) never leaves 0, and
        // Level 4 waits for a usable number.  On the Apple the monitor's
        // keyboard wait has stirred these bytes by the time a world starts.
        if machine.cpu.mem[\.randomLow] == 0 && machine.cpu.mem[\.randomHigh] == 0 {
            machine.cpu.mem[\.randomLow] = 0x5A
            machine.cpu.mem[\.randomHigh] = 0xA5
        }
        machine.cpu.sp = 0xFF
        let start = UInt16(GameSymbols.address(\.worldStart))
        try machine.cpu.call(start, stopAt: [UInt16(phase.loopStart)], maxSteps: 2_000_000)
        natives = machine.install(world.codeCheck?.natives ?? [])
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
