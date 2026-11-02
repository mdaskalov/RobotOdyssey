import Foundation

/// A world's main loop running as in the game: tick after tick, the original
/// 6502 code with the native routines, from the state after the world's
/// start-up code (`GameScreen.loop`).  Everything runs: the player by the
/// keys typed (`devices`), robots, circuits and the world's own code.  Run it
/// by CPU cycles (`run(until:)`) and show the page on screen, like the
/// Apple II: a tick takes as long as its work.  Where the world hands back to
/// the loader (`exit`: the menu, the next level, saving...) the loader runs,
/// with a drive (`Machine.drive`, `Loader`), until it starts a world, whose
/// main loop runs on (`loadedWorld`); without one the loop stops there.
///
/// The viewer may look at any room: on arriving at the draw phase, `room`
/// replaces the room the loop chose (the player's), and the loop's room goes
/// back before the page flip, so the rest of the tick sees what the game
/// would.  Looking at the player's room changes nothing; elsewhere, only what
/// the draw phase itself writes differs (the world's own drawing code
/// animates the room it draws).
nonisolated final class GameLoop {
    /// Apple IIe CPU clock in Hz (Data/ro_timing.py).
    static let clock = 1_020_484.0

    /// The running world's draw phase; nil while the loader runs (`inLoader`).
    private(set) var phase: DrawPhase?
    private let machine: Machine
    /// The room to draw; nil draws the loop's own room, the player's view.
    var room: Int?
    /// Ticks completed.
    private(set) var ticks = 0
    /// CPU cycles of the last completed tick.
    private(set) var tickCycles: UInt64 = 0
    /// The room on the page on screen (nil until the first flip).
    private(set) var shownRoom: Int?
    /// Page flips so far: a new page on screen.
    private(set) var flips = 0
    /// The machine at the start of the current tick.
    private var tickStart: Machine
    /// The room the draw phase is drawing.
    private var drawing: Int?
    /// The machine where the draw phase started drawing, and where the draw
    /// of the page on screen started.
    private var drawStart: Machine?
    private var shownDrawStart: Machine?
    /// The loop's own CURRENT_ROOM while the draw phase draws `room`.
    private var loopRoom: UInt8?
    /// The world's `JMP (RESET_VECTOR)`, back to the loader.
    private var exitJump: Int?
    /// What the world asked the loader for, from its exit until the loader
    /// starts a world.
    private(set) var exit: Exit?
    /// The world handed back to the loader and there is none to run (no
    /// drive, or no program disk in it): the loop stops.
    private(set) var halted = false
    /// The world the loader started last (nil: still the loop's first), and
    /// how many it started.
    private(set) var loadedWorld: WorldDefinition?
    private(set) var worldsLoaded = 0
    /// The draw phase and natives of the world the loader started, from when
    /// it arrives at its main loop (`GameScreen` too puts the natives in there).
    private var nextWorld: (phase: DrawPhase, natives: [Native])?
    /// START_WORLD ran: its jump to WORLD_START starts a world.
    private var startingWorld = false
    /// Each room's last preview (`preview`).
    private var previews: [Int: Preview] = [:]

    /// A room drawn on a copy, and the draw state it started from and left:
    /// what its draw phase wrote besides the page (`drawStateRanges`), as
    /// the byte and what the start of its tick had there.
    private struct Preview {
        typealias State = [(address: Int, value: UInt8, was: UInt8)]
        let tick: Int
        let screen: HiresScreen
        let from, left: State
    }

    /// Where a preview's draw state is taken from: memory but the stack, the
    /// hi-res pages and the I/O.
    private static let drawStateRanges = [0x0000 ..< 0x0100, 0x0200 ..< 0x2000, 0x6000 ..< 0xC000, 0xD000 ..< 0x10000]

    /// The world's request to the loader.
    struct Exit: CustomStringConvertible {
        /// MENU_MODE: 1 the menu, 2 the next level, 4 save the game, ...
        let request: UInt8
        /// NEXT_LEVEL: the level (or slot) it asks for.
        let level: UInt8

        var description: String {
            switch request {
            case 1: "back to the menu"
            case 2: "on to the next level (NEXT_LEVEL = \(level))"
            case 3: "to start again"
            case 4: "to save the game"
            case 5: "to load chip \(level)"
            case 6: "to save chip \(level)"
            default: "to the loader (MENU_MODE = \(request), NEXT_LEVEL = \(level))"
            }
        }
    }

    enum Failure: LocalizedError {
        case inLoader
        var errorDescription: String? { "The loader runs: no world to draw." }
    }

    init(machine: Machine, phase: DrawPhase, room: Int?) {
        self.machine = machine
        self.phase = phase
        self.room = room
        machine.cpu.pc = UInt16(phase.loopStart)
        tickStart = machine.copy()
        exitJump = GameLoop.exitJump(in: machine.cpu.mem)
    }

    private static let startWorldEntry = LoaderSymbols.address(\.startWorld)
    private static let worldStartEntry = GameSymbols.address(\.worldStart)

    private static func exitJump(in mem: [UInt8]) -> Int? {
        WorldBuilder.find(WorldBuilder.instruction(0x6C, \.resetVector), in: mem, from: 0x0803, to: 0x2000)
    }

    var cycles: UInt64 { machine.cpu.cycles }

    /// Between a world's exit and the next world's start.
    var inLoader: Bool { phase == nil }

    /// The loader's disk drive.
    var drive: DiskDrive? { machine.drive }

    /// The keyboard, joystick and buttons the game reads.
    var devices: InputDevices {
        get { machine.devices }
        set { machine.devices = newValue }
    }

    /// Main RAM as the CPU sees it, and language card bank 1.
    var memory: [UInt8] { machine.cpu.mem }
    var bank1: [UInt8] { machine.bank1 }

    /// Cycles run in the current tick so far.
    var cyclesIntoTick: UInt64 { machine.cpu.cycles - tickStart.cpu.cycles }

    /// The hi-res page on screen.
    func screen() -> HiresScreen { machine.shownScreen() }

    /// The cycles without a click that end a sound of the loader's (`takeSounds`).
    private static let loaderPause: UInt64 = 50_000

    /// The sounds the game played since the last call (the native
    /// PLAY_SOUNDS); while the loader runs also the clicks of its own code
    /// (CHAR_OUT's bell, the menu's tunes), a sound from a click to a pause
    /// of `loaderPause`: the speaker renders a sound at a time, and a tune
    /// taken in pieces would play broken up.
    func takeSounds() -> [Sound.Played] {
        var sounds = machine.takeSounds()
        guard let clicks = machine.clicks else { return sounds }
        if let first = clicks.first, let last = clicks.last, !inLoader || machine.cpu.cycles - last >= GameLoop.loaderPause {
            sounds.append(Sound.Played(parameters: nil, name: "loader", start: first, cycles: last - first + 1,
                                       clicks: clicks.map { UInt32($0 - first) }))
            machine.clicks = []
        }
        if !inLoader, machine.clicks?.isEmpty == true { machine.clicks = nil }
        return sounds
    }

    /// Runs until the cycle counter reaches `cycles` (or the loop halts).
    func run(until cycles: UInt64) throws {
        while !halted && machine.cpu.cycles < cycles { try step() }
    }

    /// Runs to the start of the next tick (or the world's exit without a
    /// loader).  A tick waiting for a key (a world's message, the loader)
    /// fails after `maxSteps` instructions (`CPUError.tooManySteps`) and can
    /// go on later.
    func runTick(maxSteps: Int = 20_000_000) throws {
        let (t, w) = (ticks, worldsLoaded)
        for _ in 0 ..< maxSteps {
            guard !halted else { return }
            try step()
            if ticks != t || worldsLoaded != w { return }
        }
        throw CPU6502.CPUError.tooManySteps(pc: machine.cpu.pc)
    }

    /// `room` drawn by the draw phase from the state at the start of the
    /// current tick, on a copy: what the loop shows once it gets there.  The
    /// draw starts from what the room's preview in an earlier tick drew
    /// where the game left those bytes alone since (`previewStart`): the
    /// robots' scanner, sparks and rainbow, the random numbers, the world's
    /// own animations go on as if the game drew the room tick after tick,
    /// rather than each tick showing the game's frozen values.  Once a tick.
    func preview(room: Int) throws -> HiresScreen {
        guard let phase else { throw Failure.inLoader }
        if let last = previews[room], last.tick == ticks { return last.screen }
        let (machine, from) = previewStart(room)
        let screen = try phase.draw(room: room, on: machine)
        let start = tickStart.cpu.mem, end = machine.cpu.mem
        var left: Preview.State = []
        for range in GameLoop.drawStateRanges {
            for a in range where end[a] != start[a] { left.append((a, end[a], start[a])) }
        }
        previews[room] = Preview(tick: ticks, screen: screen, from: from, left: left)
        return screen
    }

    /// A copy of the start of the current tick with `room`'s draw state
    /// where the game hasn't changed those bytes since: what its preview in
    /// an earlier tick left, in this tick what it started from.
    private func previewStart(_ room: Int) -> (machine: Machine, state: Preview.State) {
        let machine = tickStart.copy()
        let last = previews[room]
        let state = (last?.tick == ticks ? last?.from : last?.left)?.filter { machine.cpu.mem[$0.address] == $0.was } ?? []
        for s in state { machine.cpu.mem[s.address] = s.value }
        return (machine, state)
    }

    /// Where the draw phase starts drawing `room`, a copy: the draw of the
    /// page on screen if that shows `room`, else as `preview`.
    private func drawStart(room: Int) -> Machine {
        if room == shownRoom, let shownDrawStart { return shownDrawStart.copy() }
        return previewStart(room).machine
    }

    /// Memory and bank 1 as the draw phase finds them when it draws `room` (`drawStart`).
    func memory(drawing room: Int) -> (memory: [UInt8], bank1: [UInt8]) {
        let machine = drawStart(room: room)
        return (machine.cpu.mem, machine.bank1)
    }

    /// Memory and bank 1 at the start of the current tick, what `preview` draws from.
    var tickStartMemory: (memory: [UInt8], bank1: [UInt8]) {
        (tickStart.cpu.mem, tickStart.bank1)
    }

    /// Every sprite the draw phase draws of `room` from there (`DrawPhase.sprites`).
    func sprites(room: Int) throws -> [DrawnSprite] {
        guard let phase else { throw Failure.inLoader }
        return try phase.sprites(room: room, on: drawStart(room: room))
    }

    private func step() throws {
        let page = machine.shownPage
        try machine.cpu.step()
        if machine.shownPage != page {
            shownRoom = drawing
            shownDrawStart = drawStart
            flips += 1
        }
        let pc = Int(machine.cpu.pc)
        guard let phase else {
            if let next = nextWorld, pc == next.phase.loopStart {
                arrive(next)
            } else if pc == GameLoop.startWorldEntry {
                startingWorld = true
            } else if startingWorld, pc == GameLoop.worldStartEntry {
                startWorld()
            }
            return
        }
        if pc == exitJump {
            exit = Exit(request: machine.cpu.mem[\.menuMode], level: machine.cpu.mem[\.nextLevel])
            if machine.drive?.trackZero != nil {
                leaveWorld()
            } else {
                halted = true
            }
            return
        }
        switch pc {
        case phase.loopStart:
            restoreRoom()                           // in case the draw phase was left early
            ticks += 1
            tickCycles = machine.cpu.cycles - tickStart.cpu.cycles
            tickStart = machine.copy()
        case phase.start:
            if let room {
                loopRoom = machine.cpu.mem[\.currentRoom]
                machine.cpu.mem[\.currentRoom] = UInt8(room)
            }
            drawing = Int(machine.cpu.mem[\.currentRoom])
            drawStart = machine.copy()
        case phase.end:
            restoreRoom()
        default:
            break
        }
    }

    private func restoreRoom() {
        guard let r = loopRoom else { return }
        machine.cpu.mem[\.currentRoom] = r
        loopRoom = nil
    }

    /// The world jumps to the loader (`exit`): from here on the loader runs,
    /// until it starts a world.
    private func leaveWorld() {
        restoreRoom()
        machine.clicks = []
        phase = nil
        exitJump = nil
        drawing = nil
        drawStart = nil
        shownRoom = nil
        shownDrawStart = nil
    }

    /// The loader jumps to WORLD_START: the world it loaded starts, its
    /// engine checked as the loader's `CodeCheck` does.  Its start-up code
    /// runs as the loader does, its main loop from `arrive`; a world whose
    /// main loop isn't found runs on that way.
    private func startWorld() {
        startingWorld = false
        guard let drive = machine.drive else { return }
        let mem = machine.cpu.mem
        let world = Loader.world(in: mem, disks: drive.program)
        let variant = world.flatMap { w in drive.program.version.map { Variant(engine: w.engine, version: $0) } }
        machine.load(variant: variant)
        machine.stirRandom()
        nextWorld = DrawPhase(in: mem).map { ($0, variant.map { CodeCheck(mem, $0).natives } ?? []) }
        exitJump = GameLoop.exitJump(in: mem)
        exit = nil
        loadedWorld = world
        worldsLoaded += 1
        previews = [:]
        ticks = 0
        tickCycles = 0
    }

    /// The world the loader started arrives at its main loop.
    private func arrive(_ world: (phase: DrawPhase, natives: [Native])) {
        nextWorld = nil
        phase = world.phase
        machine.install(world.natives)
        tickStart = machine.copy()
    }
}
