import Apple2Kit
import Foundation
import MOS6502

/// The machine as a native routine sees it: memory with the symbols of the
/// world's engine (`m`, Apple2Kit's `RAM` by the engine's map), the registers
/// (`r`) and the Apple's devices (`apple`: the keyboard, the game port, the
/// mouse card).  The ported routines are its methods, one file per part of
/// the engine (EngineGraphics, ObjectMotion, PlayerInput, RobotDrawing,
/// Speaker), and read like the code they replace:
///
///     /// MOVE_OBJECT ($9DB3): moves CUR_OBJECT by (MOVE_DX, MOVE_DY) from its room.
///     mutating func moveObject() {
///         r.y = m.currentObject
///         r.x = r.nz(m.objRoom[r.y])
///         moveObjectXY()
///     }
///
/// Written for any engine's map: engine main's routines for what every world
/// has (`GameSymbols`), the robot drawing for the names the engines share
/// (`EngineSymbols`), the levels' own for `LevelsSymbols`.  The compiler
/// makes each for the engines that run it, their addresses folded in.
nonisolated struct Engine<Map: GameSymbols> {
    let m: RAM<Map>
    var r: CPU6502.Registers
    /// The Apple, for its devices: a routine reads and switches them at the
    /// cycle the original does (`cycles` + where in it).
    let apple: Apple2Machine
    /// The CPU's cycle counter at the call.
    let cycles: UInt64
    /// The canvas's layers of the pages, when the machine keeps them
    /// (`Machine.layers`): the drawings on layer 3 go there (`drawingOnLayer`).
    /// Unowned: the machine keeps them through the call.
    unowned(unsafe) let layers: PageLayers?
    /// The cycles the original takes, added to the CPU's when the routine
    /// returns; 0 (no time) for the routines that don't count them yet.
    var elapsed: UInt64 = 0
    /// The sounds the routine played (`Machine.takeSounds`).
    var sounds: [Sound.Played] = []

    /// The address of world sprite `n` (SPRITES, 16 rows each).
    func sprite(_ n: Int) -> Int { m.sprites.address + 16 * n }
}

nonisolated extension Engine where Map: EngineSymbols {
    /// The world's engine: the robot drawing differs a little between them.
    var build: EngineBuild { m.map.build }
}

/// A native routine: the Mac takes over an engine routine where the 6502
/// code reaches its entry, each with a switch (`Apple2Machine.switchedOff`, by
/// `name`), in one of two ways (`Flags`), or both:
///
/// - Swift in place of the routine (`run`), returning like RTS.  It leaves
///   memory exactly as the original does (and the registers, where callers
///   use them, `leavesRegisters`), so it replaces the routine only where the
///   code of the routine and of every routine it reproduces (`uses`) is
///   exactly the code it was ported from: their fingerprints in the symbol
///   maps (`CodeCheck`).  Data/native_check.sh compares each with the original.
/// - Its drawing on layer 3 (`drawsOnLayer3`, `PageLayers`): what it draws,
///   drawn by the Mac at its resolution, the page drawn as ever.  Without
///   `run` the original code runs, and `Machine` follows it there
///   (`drawing`); the Swift versions do it themselves (`Engine.drawingOnLayer`).
///   Off: the Apple's pixels.
///
/// A native is one engine's, in a version (`Natives` makes them from the
/// engine's map): its entry and its code are that engine's.
nonisolated struct Native {
    /// The routine's .sym name: the native's, and its switch's.
    let name: String
    /// The routine in the engine's map: where it starts, and its code.
    let routine: Routine
    /// The routines it reproduces besides, with their names.
    let uses: [(name: String, routine: Routine)]
    let flags: Flags
    /// Swift in place of the routine, on the machine at its entry; false:
    /// declined, having changed nothing, and the original code runs.  nil:
    /// the original code runs (a native that only draws on layer 3).
    let run: ((Machine) -> Bool)?
    /// How `Machine` follows the original code's drawing onto layer 3; nil
    /// unless it draws there.
    let drawing: Drawing?

    /// Where the routine starts.
    var entry: UInt16 { routine.entry }

    /// The routine and those it reproduces: all their code is the native's.
    var routines: [(name: String, routine: Routine)] { [(name, routine)] + uses }

    /// It stands in for `routine`, one every world has.
    func replaces(_ routine: RoutineSymbol) -> Bool {
        Int(entry) == GameSymbols.address(routine)
    }

    /// What a native is.
    struct Flags: OptionSet {
        let rawValue: Int

        /// The worlds' code calls it and uses the registers it leaves, so it
        /// leaves them as the original does; otherwise only memory counts.
        static let leavesRegisters = Flags(rawValue: 1 << 0)
        /// Its drawing is on layer 3 (`drawing`): switched off, the Apple's pixels.
        static let drawsOnLayer3 = Flags(rawValue: 1 << 1)
    }

    /// A drawing on layer 3 as the 6502 code makes it (`Machine.followLayers`):
    /// looked at where the routine's code starts, from its parameters
    /// (memory; PLOT's colour in A).
    struct Drawing {
        /// Whether the routine draws itself there: DRAW_TEXT jumps to
        /// DRAW_BIG_TEXT for big text, which is followed there.
        let draws: (CPU6502) -> Bool
        /// What it draws; nil: nothing (off the screen).
        let item: (CPU6502) -> LayerItem?
        /// The page it draws on, 0 or 1; nil: the engine's (LINE_HIGH_TABLE's).
        var page: ((CPU6502) -> Int)? = nil
    }

    /// Every native routine of an engine in a version: those in Swift, then
    /// those drawing on layer 3.  Made once.
    static func all(_ variant: Variant) -> [Native] { lists[variant] ?? [] }

    // By the engine's class, each list made with the natives for that class
    // (not through `any EngineSymbols`: they would run as unspecialised code).
    private static let lists: [Variant: [Native]] = Dictionary(uniqueKeysWithValues: Variant.all.map { variant in
        switch variant.symbols {
        case let map as LevelsSymbols: (variant, Natives(map: map).all)
        case let map as KitSymbols: (variant, Natives(map: map).all)
        case let map as LabSymbols: (variant, Natives(map: map).all)
        default: (variant, [])
        }
    })
}

/// The natives of an engine, from its map: each routine with the Swift that
/// stands in for it, a method of `Engine` for that map.
nonisolated struct Natives<Map: EngineSymbols> {
    let map: Map

    private typealias RoutinePath = KeyPath<Map, Routine>

    /// Swift in place of `routine`, reproducing the routines it `uses`.
    private func native(_ routine: RoutinePath, uses: [RoutinePath] = [], leavesRegisters: Bool = true,
                        _ run: @escaping (inout Engine<Map>) -> Void) -> Native {
        native(routine, uses: uses, flags: leavesRegisters ? .leavesRegisters : []) { e in
            run(&e)
            return true
        }
    }

    /// Swift in place of `routine` that may decline (the original code runs).
    private func native(_ routine: RoutinePath, uses: [RoutinePath], flags: Native.Flags = .leavesRegisters,
                        mayDecline run: @escaping (inout Engine<Map>) -> Bool) -> Native {
        Native(name: map.name(of: routine), routine: map[keyPath: routine], uses: uses.map(named), flags: flags,
               run: { [map] machine in machine.call(map, run) }, drawing: nil)
    }

    /// `routine`'s drawing on layer 3, the original code running: `item`
    /// what it draws where its code starts, if it `draws` there.
    private func native(drawing routine: RoutinePath, draws: @escaping (CPU6502) -> Bool = { _ in true },
                        _ item: @escaping (CPU6502) -> LayerItem?) -> Native {
        Native(name: map.name(of: routine), routine: map[keyPath: routine], uses: [], flags: .drawsOnLayer3,
               run: nil, drawing: Native.Drawing(draws: draws, item: item))
    }

    private func named(_ routine: RoutinePath) -> (name: String, routine: Routine) {
        (map.name(of: routine), map[keyPath: routine])
    }

    /// What the robot drawing draws with.
    private var graphics: [RoutinePath] {
        [\.drawSpriteColour, \.drawSprite, \.plot, \.horizontalLine, \.verticalLine, \.clampX, \.clampY, \.drawBox]
    }

    /// STOP_AT_WALLS and what it calls.
    private var walls: [RoutinePath] {
        [\.stopAtWalls, \.testMove, \.stopAtTileColumn, \.stopAtTileRow, \.magnitude, \.roomWallsPointer, \.wallAt]
    }

    private var moving: [RoutinePath] { [\.moveObject, \.moveObjectXY, \.setObjectRoom] }

    /// The patterns of line colour `c` (LINE_PATTERNS_EVEN/ODD), for `LayerLine`.
    private func linePatterns(_ mem: [UInt8]) -> LayerLine.Patterns {
        { c in (mem[\.linePatternsEven, c], mem[\.linePatternsOdd, c]) }
    }

    /// Every native routine: those in Swift, then those drawing on layer 3.
    /// The levels have three of their own (their code is the levels' alone).
    var all: [Native] {
        let levels = self as? Natives<LevelsSymbols>
        return [
            native(\.roomWallsPointer) { $0.roomWallsPointer() },
            native(\.moveObject, uses: moving) { $0.moveObject() },
            native(\.moveObjectXY, uses: [\.setObjectRoom]) { $0.moveObjectXY() },
            native(\.setObjectRoom) { $0.setObjectRoom() },
            native(\.readInput, uses: [\.readDevice, \.readKey, \.keyAsStick, \.readJoystick, \.moveByKey, \.moveByStick,
                                       \.clearButtons, \.limitMove, \.withSign, \.keepOnScreen] + walls + moving,
                   mayDecline: { $0.readInput() }),
            native(\.detectJoystick, uses: [], mayDecline: { $0.detectJoystick() }),
            native(\.keepOnScreen) { $0.keepOnScreen() },
            native(\.limitMove, uses: [\.withSign, \.magnitude]) { $0.limitMove() },
            native(\.stopAtWalls, uses: walls) { $0.stopAtWalls() },
            native(\.wallAt) { $0.wallAt() },
        ] + (levels.map { [$0.native(\.grabButton) { $0.grabButton() }] } ?? []) + [
            native(\.drawRobots, uses: graphics, leavesRegisters: false) { $0.drawRobots() },
            native(\.drawRobotInterior, uses: graphics, leavesRegisters: false) { $0.drawRobotInterior() },
        ] + (levels.map { [
            $0.native(\.playerWalkSprite, uses: [\.magnitude]) { $0.playerWalkSprite() },
            $0.native(\.keepMove) { $0.keepMove() },
        ] } ?? []) + [
            native(\.playSounds, uses: [\.playTone, \.playNoise]) { $0.playSounds() },

            // On layer 3: after the tiles, everything the draw phase draws (Frontends.md "The native layer").
            native(drawing: \.drawText, draws: { $0.mem[\.currentTextStyle] != 2 }) { .text(DrawnText($0.mem)) },
            native(drawing: \.drawBigText) { .text(DrawnText($0.mem)) },
            native(drawing: \.drawSprite) { LayerSprite($0.mem).map(LayerItem.sprite) },
            native(drawing: \.plot) { cpu in
                LayerLine.plot(x: cpu.mem[\.drawX], y: cpu.mem[\.drawY], colour: cpu.a, linePatterns(cpu.mem)).map(LayerItem.line)
            },
            native(drawing: \.horizontalLine) { cpu in
                let mem = cpu.mem
                return LayerLine.horizontal(x1: mem[\.lineX1], x2: mem[\.lineX2], y: mem[\.drawY], colour: mem[\.lineColour],
                                            linePatterns(mem)).map(LayerItem.line)
            },
            native(drawing: \.verticalLine) { cpu in
                let mem = cpu.mem
                return LayerLine.vertical(x: mem[\.drawX], y1: mem[\.lineY1], y2: mem[\.lineY2], colour: mem[\.lineColour],
                                          linePatterns(mem)).map(LayerItem.line)
            },
        ]
    }
}

/// The loader's check of a world's engine code, made when it loads the world
/// (before any of the code runs; the worlds' start-up code changes no engine
/// code): which natives may replace their routines, and which routines differ
/// from the version's code (a modified or damaged disk).  Those, and the
/// natives that need them, run as the original 6502 code.  A native that only
/// draws on layer 3 (no `run`) needs the fingerprints its routine has:
/// DRAW_TEXT and DRAW_BIG_TEXT change their own code and have none.
nonisolated struct CodeCheck {
    let variant: Variant
    /// The natives whose routines all have their fingerprints.
    let natives: [Native]
    /// Names of the routines whose code differs.
    let differing: [String]

    /// Checks `mem` (language card bank 2 mapped) as the code of `variant`.
    init(_ mem: [UInt8], _ variant: Variant) {
        self.variant = variant
        let all = Native.all(variant)
        var matches: [String: Bool] = [:]
        for (name, routine) in all.flatMap(\.routines) where matches[name] == nil {
            matches[name] = routine.matches(mem)
        }
        natives = all.filter { n in n.routines.allSatisfy { matches[$0.name] ?? (n.run == nil) } }
        differing = matches.filter { !$0.value }.map(\.key).sorted()
    }
}
