import Apple2Kit
import Foundation
import MOS6502

/// The Apple IIe as Robot Odyssey uses it, running the original code from the
/// disks: Apple2Kit's `Apple2` without ROMs (`apple`: 64K of main RAM, the
/// language card's RAM with its two $D000 banks, the soft switches, the
/// speaker, the keyboard, the game port, the mouse card in slot 4), and
/// native Swift routines in place of engine
/// routines that have been ported (`install`, `Native`).  A
/// native routine runs when the 6502 code reaches its entry point and returns
/// like RTS; it must leave memory exactly as the original does, and the
/// registers too where other code uses them (Data/native_check.swift).
nonisolated final class Machine {
    /// The world's engine and version, where natives find their symbols; nil:
    /// an unknown version, everything runs as 6502 code.  Another world's
    /// when the loader starts one (`load(variant:)`).
    private(set) var variant: Variant?
    /// The Apple: its CPU, memory, switches and speaker.  The game's code
    /// lives in the language card's RAM (no ROMs: the card is always read
    /// and written, $C080-$C08F pick its $D000 bank); it lies in
    /// `apple.cpu.mem` with main RAM, the $D000 bank selected at $D000.
    let apple: Apple2Machine
    /// The sounds the native PLAY_SOUNDS played and nobody has taken yet.
    private var sounds: [Sound.Played] = []
    /// What the mouse card took over as it went in (`plugMouse`); nil: it is out.
    var beforeMouse: AppleMouse.Before?
    /// The cycles of the last two reads of the keyboard ($C000) that found no
    /// key (0: none since one was found).
    private var emptyKeyReads: (UInt64, UInt64) = (0, 0)
    // The natives and hooks are Apple2Kit's hooks on `apple` (`addHook`),
    // each native's by its name: switched off by it (`apple.switchedOff`),
    // the original code runs there, its drawing the Apple's pixels, and the
    // CPU doesn't stop there.  A native leaves memory as the original does,
    // so the two can take each other's place at any call: a switch counts
    // from the next instruction.

    /// The native routines `install` put in, at their entry points, with
    /// the hook of each that runs in Swift.
    private var installed: [(native: Native, entry: UInt16, hook: HookID?)] = []
    /// The hooks of `hook`, one an address.
    private var hookIDs: [UInt16: HookID] = [:]
    /// While the layers are kept: the observers of where a page's drawing
    /// starts and where the drawings on layer 3 start (`followLayers`).
    private var layerHooks: [HookID] = []
    /// The observer of `onDrawSprite`.
    private var spriteHook: HookID?
    /// The disk drive the loader reads and writes; nil: no loader, a world
    /// that hands back to it stops (`GameLoop.halted`).
    var drive: DiskDrive?
    /// Off: everything runs as 6502 code, for comparisons.
    var nativesEnabled = true
    private(set) var nativeCalls = 0
    /// Called where DRAW_SPRITE starts, with the machine there, when set
    /// (`DrawPhase.sprites`).  The natives draw without it: it sees every
    /// sprite only with them off.
    var onDrawSprite: ((Machine) -> Void)? {
        didSet {
            if let spriteHook { apple.removeHook(spriteHook) }
            spriteHook = onDrawSprite == nil ? nil : apple.addObserver(at: UInt16(GameSymbols.address(\.drawSprite))) { apple in
                guard let m = apple.host as? Machine else { return }
                m.onDrawSprite?(m)
            }
        }
    }
    /// The canvas's layers of the pages (`PageLayers`), while a world runs
    /// (`GameLoop`); nil: none kept, the canvas shows the pages.  They look
    /// and change nothing: memory is the same with them as without.
    var layers: PageLayers? {
        get { pageLayers }
        set {
            pageLayers = newValue
            followsLoader = false
            followLayers()
        }
    }
    private var pageLayers: PageLayers?
    /// The layers follow the loader's drawing (`keepLoaderLayers`), not the engine's.
    private var followsLoader = false
    /// The drawings on layer 3 the 6502 code is in (DRAW_TEXT, DRAW_SPRITE):
    /// where each returns to, with the stack pointer it returns with.
    private var layerReturns: [(address: UInt16, sp: UInt8)] = []
    /// The observers where drawings return to, one an address, kept while
    /// the layers are (a few call sites; put in and taken out at every
    /// drawing they would cost more than the drawing).
    private var returnHooks: [UInt16: HookID] = [:]

    /// A machine with `memory` (64K: main RAM, and at $D000-$FFFF the
    /// language card's bank 2 and $E000-$FFFF; $C000-$CFFF left out) and the
    /// card's `bank1`, bank 2 selected, the CPU's registers clear.
    convenience init(memory: [UInt8], bank1: [UInt8], variant: Variant?) {
        let apple = Apple2Machine(model: .apple2e, rom: nil, diskROM: nil)
        apple.load(memory: memory, languageCard: bank1 + memory[0xD000 ..< 0x10000])
        let cpu = apple.cpu
        (cpu.a, cpu.x, cpu.y, cpu.sp, cpu.p, cpu.pc, cpu.cycles) = (0, 0, 0, 0xFF, CPU6502.Flag.unused | CPU6502.Flag.interrupt, 0, 0)
        self.init(apple: apple, variant: variant)
    }

    private init(apple: Apple2Machine, variant: Variant?) {
        self.variant = variant
        self.apple = apple
        apple.cpu.stopsAtBRK = true             // no ROM behind the vector: the code went astray
        apple.ioHook = { [unowned self] a, write, _ in
            if a == 0xC000 && !write { keyboardRead() }
            return nil
        }
        // What is written to a watched page (`followLayers`): the 6502 code's and the natives' (`RAM`).
        apple.cpu.onWrite = { [unowned self] a, old, new in pageLayers?.write(Int(a), old: old, new: new) }
        apple.host = self
        apple.mouseReportsClickOnce = true          // the game's (`AppleMouse.swift`)
    }

    /// Bank 1 of the language card as it is now, wherever it is mapped.
    var bank1: [UInt8] { Array(apple.languageCardRAM[0 ..< 0x1000]) }

    /// An independent machine in the same state: memory, banks, registers,
    /// soft switches, devices and natives (the native call count starts at 0).
    func copy() -> Machine {
        let m = Machine(apple: apple.copy(), variant: variant)      // the hooks with it
        m.beforeMouse = beforeMouse
        m.installed = installed
        m.hookIDs = hookIDs
        m.layerHooks = layerHooks
        m.spriteHook = spriteHook                                   // `onDrawSprite` isn't copied
        m.drive = drive
        m.nativesEnabled = nativesEnabled
        m.pageLayers = layers?.copy()
        m.followsLoader = followsLoader
        m.apple.cpu.watchedPages = apple.cpu.watchedPages                 // the layers' (`followLayers`)
        m.layerReturns = layerReturns
        m.returnHooks = returnHooks
        return m
    }

    /// The code waits for a key: it reads the keyboard again and again and
    /// finds none (`GameLoop.run` doesn't run ahead of the clock there).
    var waitsForKey: Bool {
        let (previous, last) = emptyKeyReads
        return previous != 0 && last - previous < 256 && apple.cpu.cycles - last < 256
    }

    /// The code reads the keyboard ($C000, `apple`'s `ioHook`, before the
    /// Apple answers): noted for `waitsForKey`.
    private func keyboardRead() {
        let cycles = apple.cpu.cycles
        emptyKeyReads = apple.readKeyboard(at: cycles) & 0x80 == 0 ? (emptyKeyReads.1, cycles) : (0, 0)
    }

    // MARK: native routines

    /// Installs `natives` (the world's `CodeCheck` chose them, of its
    /// engine and version); returns them with their entry points.  Each in
    /// Swift is a hook by its name (always in bank 2 when in $D000-$DFFF);
    /// those that draw on layer 3 are followed while the layers are kept.
    @discardableResult
    func install(_ natives: [Native]) -> [(native: Native, entry: UInt16)] {
        guard variant != nil else { return [] }
        for native in natives {
            let hook = native.run.map { run in
                let bank2 = (0xD000 ..< 0xE000).contains(native.entry)
                return apple.addHook(at: native.entry, name: native.name) { apple in
                    guard let m = apple.host as? Machine, m.nativesEnabled, !bank2 || apple.languageCardBank == 2,
                          run(m) else { return false }
                    m.nativeCalls += 1
                    apple.cpu.returnFromSubroutine()
                    return true
                }
            }
            installed.append((native, native.entry, hook))
        }
        followLayers()
        return natives.map { ($0, $0.entry) }
    }

    /// Takes the natives out, for the engine of another world, in `variant`
    /// (`install` puts in those its code check allows).
    func load(variant: Variant?) {
        for hook in installed.compactMap(\.hook) { apple.removeHook(hook) }
        installed = []
        followLayers()
        self.variant = variant
    }

    /// Puts in a hook at `address` (in place of one there): run where the
    /// CPU gets there, before the instruction; true: it set the CPU up to go
    /// on (PC and all), false: the instruction runs.  One with a `name` can
    /// be switched off (`apple.switchedOff`).
    func hook(_ address: Int, name: String? = nil, _ run: @escaping (Machine) -> Bool) {
        let a = UInt16(address)
        if let old = hookIDs[a] { apple.removeHook(old) }
        hookIDs[a] = apple.addHook(at: a, name: name) { apple in
            guard let m = apple.host as? Machine else { return false }
            return run(m)
        }
    }

    /// The random generator (RANDOM, a shift register) never leaves 0, and
    /// Level 4 waits for a usable number.  On the Apple the monitor's
    /// keyboard wait has stirred these bytes by the time a world starts.
    func stirRandom() {
        if apple.cpu.mem[\.randomLow] == 0 && apple.cpu.mem[\.randomHigh] == 0 {
            apple.cpu.mem[\.randomLow] = 0x5A
            apple.cpu.mem[\.randomHigh] = 0xA5
        }
    }

    /// Runs a native routine on the machine as it is: its memory (the CPU's
    /// own, by the names of the engine's `map`), registers and the Apple's
    /// devices, and takes the time it reports.  False if the routine declined.
    @discardableResult
    func call<Map: GameSymbols>(_ map: Map, _ run: (inout Engine<Map>) -> Bool) -> Bool {
        let registers = apple.cpu.registers
        let (apple, cycles) = (apple, apple.cpu.cycles)
        let layers = layers
        let result = apple.cpu.withRAM(map) { m -> Engine<Map>? in
            var engine = Engine(m: m, r: registers, apple: apple, cycles: cycles, layers: layers)
            return run(&engine) ? engine : nil
        }
        guard let result else { return false }
        apple.cpu.registers = result.r
        apple.cpu.cycles += result.elapsed
        sounds += result.sounds
        return true
    }

    /// The sounds played since the last call, in order.
    func takeSounds() -> [Sound.Played] {
        defer { sounds = [] }
        return sounds
    }

    // MARK: the hi-res pages

    /// The page on screen with its layers (`PageFrame`).
    func shownFrame() -> PageFrame {
        frame(page: apple.video.page2 ? 1 : 0, screen: apple.hiresScreen())
    }

    /// The page the engine draws on with its layers: what a draw phase drew.
    func drawnFrame() -> PageFrame {
        frame(page: drawnPage, screen: drawnScreen())
    }

    private func frame(page p: Int, screen: HiresScreen) -> PageFrame {
        guard let layers, !layers.pages[p].items.isEmpty else { return PageFrame(page: screen) }
        return PageFrame(page: screen, apple: HiresScreen(layers.pages[p].apple, base: 0),
                         start: HiresScreen(layers.pages[p].start, base: 0), items: layers.pages[p].drawn)
    }

    /// Keeps the canvas's layers of the pages while the loader runs (`keep`;
    /// else none), following the loader's drawing: its texts (CHAR_OUT) on
    /// layer 3, owning their cells (`PageLayers.textsOwnCells`), page 1's
    /// emptied where CLEAR_SCREEN clears it (`Loader.charOutDrawing`).
    func keepLoaderLayers(_ keep: Bool) {
        pageLayers = keep ? PageLayers(textsOwnCells: true) : nil
        followsLoader = keep
        followLayers()
    }

    /// The page the engine draws on (LINE_HIGH_TABLE's), 0 or 1.
    private var drawnPage: Int {
        PageLayers.page(lineHigh: apple.cpu.mem[apple.cpu.mem[\.lineHighTable]])
    }

    /// Where a page's drawing starts: DRAW_ROOM_TILES.
    private static let drawRoomTiles = UInt16(GameSymbols.address(\.drawRoomTiles))

    /// The layers came or went: the pages' writes followed, and observers
    /// where a page's drawing starts (DRAW_ROOM_TILES) and where the natives
    /// that draw on layer 3 start, by their names, while they are kept.  The
    /// loader's (`keepLoaderLayers`): where CLEAR_SCREEN clears page 1 and
    /// where CHAR_OUT starts, by its name.
    private func followLayers() {
        for page in 0x20 ..< 0x60 { apple.cpu.watchedPages[page] = layers != nil }
        for hook in layerHooks + returnHooks.values { apple.removeHook(hook) }
        layerHooks = []
        returnHooks = [:]
        layerReturns = []
        guard layers != nil else { return }
        if followsLoader {
            layerHooks.append(apple.addObserver(at: Loader.clearScreenEntry) { apple in
                (apple.host as? Machine)?.pageDrawingStarts(page: 0)
            })
            let drawing = Loader.charOutDrawing()
            layerHooks.append(apple.addObserver(at: Loader.charOutEntry, name: Loader.charOutName) { apple in
                (apple.host as? Machine)?.drawingStarts(drawing)
            })
            return
        }
        layerHooks.append(apple.addObserver(at: Machine.drawRoomTiles) { apple in
            guard let m = apple.host as? Machine else { return }
            m.pageDrawingStarts(page: m.drawnPage)
        })
        for (native, entry, _) in installed {
            guard let drawing = native.drawing else { continue }
            layerHooks.append(apple.addObserver(at: entry, name: native.name) { apple in
                (apple.host as? Machine)?.drawingStarts(drawing)
            })
        }
    }

    /// DRAW_ROOM_TILES (the loader's CLEAR_SCREEN): `page`'s drawing starts,
    /// its layer 3 empty.  The engine's routines, at the same place in every
    /// world; the engine's layers are kept only while a world runs.
    private func pageDrawingStarts(page: Int) {
        guard let layers else { return }
        layers.clear(page: page)
        layerReturns = []
    }

    /// A drawing on layer 3 starts (a native that draws there, switched on:
    /// `Native.Drawing`, the item it draws noted from its parameters, as it
    /// starts); it ends where it returns (`drawingReturns`).
    private func drawingStarts(_ drawing: Native.Drawing) {
        guard let layers, drawing.draws(apple.cpu) else { return }
        let item = layers.drawing > 0 ? nil : drawing.item(apple.cpu)
        // It returns where the JSR that called it (or its caller, which jumped to it) goes back to.
        let sp = Int(apple.cpu.sp)
        let back = (UInt16(apple.cpu.mem[0x100 + (sp + 1) & 0xFF]) | UInt16(apple.cpu.mem[0x100 + (sp + 2) & 0xFF]) << 8) &+ 1
        if returnHooks[back] == nil {
            returnHooks[back] = apple.addObserver(at: back, first: true) { apple in
                (apple.host as? Machine)?.drawingReturns()
            }
        }
        layerReturns.append((back, apple.cpu.sp &+ 2))
        let page = drawing.page?(apple.cpu) ?? drawnPage
        apple.cpu.mem.withUnsafeBufferPointer { layers.begin(item, page: page, memory: $0.baseAddress!) }
    }

    /// The CPU is where a drawing on layer 3 returns to: the innermost
    /// ends if it returns with its stack pointer.
    private func drawingReturns() {
        guard let r = layerReturns.last, r.address == apple.cpu.pc, r.sp == apple.cpu.sp else { return }
        layerReturns.removeLast()
        guard let layers else { return }
        apple.cpu.mem.withUnsafeBufferPointer { layers.end(memory: $0.baseAddress!) }
    }

    /// The page the engine is drawing on, read through its line tables
    /// (LINE_LOW_TABLE, LINE_HIGH_TABLE), top line first.
    func drawnScreen() -> HiresScreen {
        var screen = HiresScreen()
        let mem = apple.cpu.mem
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
        machine.apple.cpu.mem[\.currentRoom] = UInt8(room)
        machine.apple.cpu.sp = UInt8(DrawPhase.stack)
        // A world's own loop (e.g. Level 5's transporter) may flip pages itself: stop there too.
        let flipPage = UInt16(GameSymbols.address(\.flipPage))
        try machine.apple.cpu.call(UInt16(start), stopAt: [UInt16(end), flipPage], maxSteps: 3_000_000)
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
            let mem = m.apple.cpu.mem
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
    let natives: [(native: Native, entry: UInt16)]
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
        machine.stirRandom()
        machine.apple.cpu.sp = 0xFF
        let start = UInt16(GameSymbols.address(\.worldStart))
        try machine.apple.cpu.call(start, stopAt: [UInt16(phase.loopStart)], maxSteps: 2_000_000)
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

    /// The main loop, ready to run its first tick, drawing `room`; with a
    /// drive the loader runs when the world hands back to it (`Loader`).
    func loop(room: Int?, nativesEnabled: Bool = true, drive: DiskDrive? = nil) -> GameLoop {
        let machine = started.copy()
        machine.nativesEnabled = nativesEnabled
        if let drive { Loader.install(on: machine, drive: drive) }
        return GameLoop(machine: machine, phase: phase, room: room)
    }
}
