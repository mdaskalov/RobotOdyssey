import Foundation
import MOS6502

/// A world's main loop running as in the game: tick after tick, the original
/// 6502 code with the native routines, from the state after the world's
/// start-up code (`GameScreen.loop`).  Everything runs: the player by the
/// keys typed (`devices`), robots, circuits and the world's own code.  Run it
/// by CPU cycles (`run(until:)`) and show the page on screen, like the
/// Apple II: a tick takes as long as its work.  The viewer runs each tick at
/// once as the clock reaches it (`finishingTick`), so its page is on screen
/// a tick earlier than the Apple's, and between two pages shows what moved
/// on its way (`inBetween`); the ticks themselves run as they do.  Where the world hands back to
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
    /// The cycle the tick of the page on screen started, and the cycle of its flip.
    private var shownTick: UInt64 = 0
    private var flipCycle: UInt64 = 0
    /// The room and draw start of the page before it (`inBetween`).
    private var previousShown: (room: Int?, drawStart: Machine?)?
    /// The last in-between frame: of which page, what it moved, the page it drew.
    private var lastInBetween: (flips: Int, moves: [Int], screen: HiresScreen)?
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
    /// The canvas's mouse holding the player or an object (`MouseHand`),
    /// applied where each tick starts; nil once it lets go.
    var hand: MouseHand?

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
        machine.clicks = []
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

    /// The natives switched off by name, the loader's intro too
    /// (`Machine.switchedOff`): from the next instruction on, the original
    /// code runs there.
    var switchedOff: Set<String> {
        get { machine.switchedOff }
        set { machine.switchedOff = newValue }
    }

    /// The keyboard, joystick and buttons the game reads.
    var devices: InputDevices {
        get { machine.devices }
        set { machine.devices = newValue }
    }

    /// The mouse lets go at once (a movement key typed): the joystick it
    /// steered the player with is let go too.
    func letGo() {
        if hand?.holding == .player { machine.devices.joystick = InputDevices.centre }
        hand = nil
    }

    /// Main RAM as the CPU sees it, and language card bank 1.
    var memory: [UInt8] { machine.cpu.mem }
    var bank1: [UInt8] { machine.bank1 }

    /// Cycles run in the current tick so far.
    var cyclesIntoTick: UInt64 { machine.cpu.cycles - tickStart.cpu.cycles }

    /// The hi-res page on screen.
    func screen() -> HiresScreen { machine.shownScreen() }

    /// What the speaker played since the last call: the sounds of the native
    /// PLAY_SOUNDS (`Machine.takeSounds`), and the cycle of every click, in
    /// order: theirs and the 6502 code's ($C030: the loader's bell, the
    /// menu's and the intro's tunes, PLAY_SOUNDS switched off).
    func takeSpeaker() -> (sounds: [Sound.Played], clicks: [UInt64]) {
        let sounds = machine.takeSounds()
        var clicks = machine.clicks ?? []
        machine.clicks = []
        if !sounds.isEmpty {
            clicks += sounds.flatMap { s in s.clicks.map { s.start + UInt64($0) } }
            clicks.sort()
        }
        return (sounds, clicks)
    }

    /// How far `run(until:finishingTick:)` runs past the clock to finish a
    /// tick (the longest take about 270,000 cycles), and past the tick's flip.
    private static let runAhead: UInt64 = 500_000
    private static let afterFlip: UInt64 = 10_000

    /// The code of the game's sound player: PLAY_SOUNDS, PLAY_TONE and
    /// PLAY_NOISE (engine main, the same in every world).
    private static let soundCode = [\GameSymbols.playSounds, \.playTone, \.playNoise].flatMap {
        GameSymbols.map[keyPath: $0].code.flatMap(\.ranges)
    }

    /// Runs until the cycle counter reaches `cycles` (or the loop halts).
    /// `finishingTick` then runs the tick under way on to its end, so its
    /// page is on screen as the tick starts rather than as its cycles run
    /// out; the next tick starts once the clock has caught up, so the ticks
    /// keep their pace.  It stops early where the game waits: for a key
    /// (`Machine.waitsForKey`), past `runAhead` cycles (a sound playing), or
    /// `afterFlip` cycles after the tick's page flip (a world's own animation
    /// flipping pages); from there the tick runs by the clock.  A sound the
    /// game's sound player plays as 6502 code (its native switched off) runs
    /// on past the flip, as the native takes the sound's cycles at once: the
    /// sound comes whole with its page, not its first clicks with the page
    /// and the rest once the clock has caught up.
    func run(until cycles: UInt64, finishingTick: Bool = false) throws {
        while !halted && machine.cpu.cycles < cycles { try step() }
        guard finishingTick else { return }
        let limit = cycles + GameLoop.runAhead
        while !halted, let phase, Int(machine.cpu.pc) != phase.loopStart, machine.cpu.cycles < limit, !machine.waitsForKey,
              flipCycle < tickStart.cpu.cycles || machine.cpu.cycles < flipCycle + GameLoop.afterFlip || playsSound {
            try step()
        }
    }

    /// The game's sound player runs as 6502 code.
    private var playsSound: Bool {
        let pc = Int(machine.cpu.pc)
        return GameLoop.soundCode.contains { $0.contains(pc) }
    }

    /// Nothing clicks for a while from here: the loop is at the start of a
    /// tick, or past the tick's page flip and out of the sound player (the
    /// game plays its sounds right after the flip).  The viewer ends the
    /// speaker's sound there (`SpeakerStream`): finished ahead of the clock,
    /// the loop waits for it.
    var speakerQuiet: Bool {
        guard let phase, !halted else { return false }
        return Int(machine.cpu.pc) == phase.loopStart || flipCycle >= tickStart.cpu.cycles && !playsSound
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

    /// The most an object or a wire end moves in a tick to be shown on its
    /// way (`inBetween`): the player walks 7 across, 16 up or down.
    private static let maxStep = (x: 8, y: 16)

    /// An in-between frame: the page on screen at the clock's `cycle` into
    /// the tick that drew it, with what moved since the page before (the
    /// objects in the room, wire ends; a step's worth, as the player walks)
    /// that part of the way back where it was, drawn by the draw phase from
    /// where it drew the page.  So the page before turns into this one over
    /// the tick, as the Apple would show them a tick later each.  Nil where it
    /// is the page itself: nothing moved, another room, the tick over.
    func inBetween(at cycle: UInt64) throws -> HiresScreen? {
        guard let phase, let room = shownRoom, let to = shownDrawStart,
              let previousShown, previousShown.room == room, let from = previousShown.drawStart
        else { return nil }
        let end = tickStart.cpu.cycles > shownTick ? tickStart.cpu.cycles : machine.cpu.cycles
        guard end > shownTick, cycle < end else { return nil }
        let f = Double(max(cycle, shownTick) - shownTick) / Double(end - shownTick)
        let a = from.cpu.mem, b = to.cpu.mem
        var moves: [Int] = []
        // The coordinates at x and y: f of the way from the page before.
        func move(_ x: Int, _ y: Int) {
            let dx = Int(b[x]) - Int(a[x]), dy = Int(b[y]) - Int(a[y])
            guard abs(dx) <= GameLoop.maxStep.x, abs(dy) <= GameLoop.maxStep.y else { return }
            for (address, d) in [(x, dx), (y, dy)] {
                let value = Int(a[address]) + Int((Double(d) * f).rounded())
                if value != b[address] { moves.append(address << 8 | value) }
            }
        }
        let objRoom = GameSymbols.address(\.objRoom), objX = GameSymbols.address(\.objX), objY = GameSymbols.address(\.objY)
        let inRoom = (0 ..< World.objectCount).filter { a[objRoom + $0] == room && b[objRoom + $0] == room }
        for o in inRoom { move(objX + o, objY + o) }
        if let engine = machine.variant?.engine, let wireTo = GameSymbols.map.wireTo.address(engine),
           let ax = GameSymbols.map.wireAX.address(engine), let ay = GameSymbols.map.wireAY.address(engine),
           let bx = GameSymbols.map.wireBX.address(engine), let by = GameSymbols.map.wireBY.address(engine) {
            for o in inRoom where a[wireTo + o] != 0 && b[wireTo + o] != 0 {
                move(ax + o, ay + o)
                move(bx + o, by + o)
            }
            // Loose wires (World.looseWire).
            let loose = wireTo + 0x466
            for o in inRoom where (0xD1 ... 0xDF).contains(o) && a[loose + o] != 0 && b[loose + o] != 0 {
                move(loose + 0x0F + o, loose + 0x2D + o)
                move(loose + 0x1E + o, loose + 0x3C + o)
            }
        }
        guard !moves.isEmpty else { return nil }
        if let last = lastInBetween, last.flips == flips, last.moves == moves { return last.screen }
        let machine = to.copy()
        for m in moves { machine.cpu.mem[m >> 8] = UInt8(m & 0xFF) }
        let screen = try phase.draw(room: room, on: machine)
        lastInBetween = (flips, moves, screen)
        return screen
    }

    /// Whether `code` is one of the world's movement keys (MOVE_KEYS: up,
    /// down, left, right, each also slowly), lower case as capitals as
    /// READ_KEY takes them: a key the player walks with while it is held.
    func walks(_ code: UInt8) -> Bool {
        guard !inLoader else { return false }
        let mem = machine.cpu.mem
        var key = code | 0x80
        if (0xE1 ..< 0xFB).contains(key) { key &= mem[\.caseMask] }
        return [0, 1, 2, 3, 6, 7, 8, 9].contains { mem[\.moveKeys, $0] == key }
    }

    private func step() throws {
        if let phase, Int(machine.cpu.pc) == phase.loopStart {
            if let hand { self.hand = machine.apply(hand) }   // may press the button for this tick
            machine.devices.startTick()             // as the tick starts, where READ_INPUT reads it
        }
        let page = machine.shownPage
        try machine.cpu.step()
        if machine.shownPage != page {
            previousShown = (shownRoom, shownDrawStart)
            shownRoom = drawing
            shownDrawStart = drawStart
            shownTick = tickStart.cpu.cycles
            flipCycle = machine.cpu.cycles
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
        letGo()
        phase = nil
        exitJump = nil
        drawing = nil
        drawStart = nil
        shownRoom = nil
        shownDrawStart = nil
        previousShown = nil
        lastInBetween = nil
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
