import Apple2Kit
import Foundation
import MOS6502

/// The machine as a native routine sees it: memory with the game's symbols
/// (`m`), the registers (`r`) and the Apple's devices (`apple`: the keyboard,
/// the game port, the mouse card).  The ported routines are
/// its methods, one file per part of the engine (EngineGraphics,
/// ObjectMotion, PlayerInput, RobotDrawing, Speaker), and read like the code
/// they replace:
///
///     /// MOVE_OBJECT ($9DB3): moves CUR_OBJECT by (MOVE_DX, MOVE_DY) from its room.
///     mutating func moveObject() {
///         r.y = m.currentObject
///         r.x = r.nz(m.objRoom[r.y])
///         moveObjectXY()
///     }
nonisolated struct Engine {
    let m: RAM
    var r: CPU6502.Registers
    /// The Apple, for its devices: a routine reads and switches them at the
    /// cycle the original does (`cycles` + where in it).
    let apple: Apple2Machine
    /// The CPU's cycle counter at the call.
    let cycles: UInt64
    /// The cycles the original takes, added to the CPU's when the routine
    /// returns; 0 (no time) for the routines that don't count them yet.
    var elapsed: UInt64 = 0
    /// The sounds the routine played (`Machine.takeSounds`).
    var sounds: [Sound.Played] = []

    /// The world's engine: the robot drawing differs a little between them.
    var build: EngineBuild { m.variant.engine }

    /// The address of world sprite `n` (SPRITES, 16 rows each).
    func sprite(_ n: Int) -> Int { m.sprites.address + 16 * n }
}

/// A native routine: the Mac takes over the engine routine `routine` where
/// the 6502 code reaches its entry, each with a switch (`Machine.switchedOff`,
/// by `name`), in one of two ways (`Flags`), or both:
///
/// - Swift in place of the routine (`run`), returning like RTS.  It leaves
///   memory exactly as the original does (and the registers, where callers
///   use them, `leavesRegisters`), so it replaces the routine only where the
///   code of the routine and of every routine it reproduces (`uses`) is
///   exactly the code it was ported from: their fingerprints in GameSymbols
///   (`CodeCheck`).  Data/native_check.sh compares each with the original.
/// - Its drawing on layer 3 (`drawsOnLayer3`, `PageLayers`): what it draws,
///   drawn by the Mac at its resolution, the page drawn as ever.  Without
///   `run` the original code runs, and `Machine` follows it there
///   (`drawing`); the Swift versions do it themselves (`RAM.drawingOnLayer`).
///   Off: the Apple's pixels.
nonisolated struct Native {
    let routine: KeyPath<GameSymbols, Routine>
    let uses: [KeyPath<GameSymbols, Routine>]
    let flags: Flags
    /// Swift in place of the routine; false: declined, having changed
    /// nothing, and the original code runs.  nil: the original code runs
    /// (a native that only draws on layer 3).
    let run: ((inout Engine) -> Bool)?
    /// How `Machine` follows the original code's drawing onto layer 3; nil
    /// unless it draws there.
    let drawing: Drawing?

    var name: String { GameSymbols.name(of: routine) }

    /// What a native is (`Native.all` filters and sorts by them).
    struct Flags: OptionSet {
        let rawValue: Int

        /// The worlds' code calls it and uses the registers it leaves, so it
        /// leaves them as the original does; otherwise only memory counts.
        static let leavesRegisters = Flags(rawValue: 1 << 0)
        /// Its drawing is on layer 3 (`drawing`): switched off, the Apple's pixels.
        static let drawsOnLayer3 = Flags(rawValue: 1 << 1)
    }

    /// A drawing on layer 3 as the 6502 code makes it (`Machine.followDrawing`):
    /// looked at where the routine's code starts, from its parameters
    /// (memory; PLOT's colour in A).
    struct Drawing {
        /// Whether the routine draws itself there: DRAW_TEXT jumps to
        /// DRAW_BIG_TEXT for big text, which is followed there.
        let draws: (CPU6502) -> Bool
        /// What it draws; nil: nothing (off the screen).
        let item: (CPU6502) -> LayerItem?
    }

    private init(_ routine: KeyPath<GameSymbols, Routine>, uses: [KeyPath<GameSymbols, Routine>], flags: Flags,
                 run: ((inout Engine) -> Bool)?, drawing: Drawing?) {
        self.routine = routine
        self.uses = uses
        self.flags = flags
        self.run = run
        self.drawing = drawing
    }
}

nonisolated extension Native {
    /// Swift in place of `routine`, reproducing the routines it `uses`.
    init(_ routine: KeyPath<GameSymbols, Routine>, uses: [KeyPath<GameSymbols, Routine>] = [],
         leavesRegisters: Bool = true, _ run: @escaping (inout Engine) -> Void) {
        self.init(routine, uses: uses, flags: leavesRegisters ? .leavesRegisters : [], run: { e in
            run(&e)
            return true
        }, drawing: nil)
    }

    /// Swift in place of `routine` that may decline (the original code runs).
    init(_ routine: KeyPath<GameSymbols, Routine>, uses: [KeyPath<GameSymbols, Routine>],
         mayDecline run: @escaping (inout Engine) -> Bool) {
        self.init(routine, uses: uses, flags: .leavesRegisters, run: run, drawing: nil)
    }

    /// `routine`'s drawing on layer 3, the original code running: `item`
    /// what it draws where its code starts, if it `draws` there.
    init(drawing routine: KeyPath<GameSymbols, Routine>, draws: @escaping (CPU6502) -> Bool = { _ in true },
         _ item: @escaping (CPU6502) -> LayerItem?) {
        self.init(routine, uses: [], flags: .drawsOnLayer3, run: nil, drawing: Drawing(draws: draws, item: item))
    }

    /// What the robot drawing draws with.
    private static let graphics: [KeyPath<GameSymbols, Routine>] = [
        \.drawSpriteColour, \.drawSprite, \.plot, \.horizontalLine, \.verticalLine, \.clampX, \.clampY, \.drawBox]
    /// STOP_AT_WALLS and what it calls.
    private static let walls: [KeyPath<GameSymbols, Routine>] = [
        \.stopAtWalls, \.testMove, \.stopAtTileColumn, \.stopAtTileRow, \.magnitude, \.roomWallsPointer, \.wallAt]
    private static let moving: [KeyPath<GameSymbols, Routine>] = [\.moveObject, \.moveObjectXY, \.setObjectRoom]

    /// The patterns of line colour `c` (LINE_PATTERNS_EVEN/ODD), for `LayerLine`.
    private static func linePatterns(_ mem: [UInt8]) -> LayerLine.Patterns {
        { c in (mem[\.linePatternsEven, c], mem[\.linePatternsOdd, c]) }
    }

    /// Every native routine: those in Swift, then those drawing on layer 3.
    static let all: [Native] = [
        Native(\.roomWallsPointer) { $0.roomWallsPointer() },
        Native(\.moveObject, uses: moving) { $0.moveObject() },
        Native(\.moveObjectXY, uses: [\.setObjectRoom]) { $0.moveObjectXY() },
        Native(\.setObjectRoom) { $0.setObjectRoom() },
        Native(\.readInput, uses: [\.readDevice, \.readKey, \.keyAsStick, \.readJoystick, \.moveByKey, \.moveByStick,
                                   \.clearButtons, \.limitMove, \.withSign, \.keepOnScreen] + walls + moving,
               mayDecline: { $0.readInput() }),
        Native(\.detectJoystick, uses: [], mayDecline: { $0.detectJoystick() }),
        Native(\.keepOnScreen) { $0.keepOnScreen() },
        Native(\.limitMove, uses: [\.withSign, \.magnitude]) { $0.limitMove() },
        Native(\.stopAtWalls, uses: walls) { $0.stopAtWalls() },
        Native(\.wallAt) { $0.wallAt() },
        Native(\.grabButton) { $0.grabButton() },
        Native(\.drawRobots, uses: graphics, leavesRegisters: false) { $0.drawRobots() },
        Native(\.drawRobotInterior, uses: graphics, leavesRegisters: false) { $0.drawRobotInterior() },
        Native(\.playerWalkSprite, uses: [\.magnitude]) { $0.playerWalkSprite() },
        Native(\.keepMove) { $0.keepMove() },
        Native(\.playSounds, uses: [\.playTone, \.playNoise]) { $0.playSounds() },

        // On layer 3: after the tiles, everything the draw phase draws (Frontends.md "The native layer").
        Native(drawing: \.drawText, draws: { $0.mem[\.currentTextStyle] != 2 }) { .text(DrawnText($0.mem)) },
        Native(drawing: \.drawBigText) { .text(DrawnText($0.mem)) },
        Native(drawing: \.drawSprite) { LayerSprite($0.mem).map(LayerItem.sprite) },
        Native(drawing: \.plot) { cpu in
            LayerLine.plot(x: cpu.mem[\.drawX], y: cpu.mem[\.drawY], colour: cpu.a, linePatterns(cpu.mem)).map(LayerItem.line)
        },
        Native(drawing: \.horizontalLine) { cpu in
            let mem = cpu.mem
            return LayerLine.horizontal(x1: mem[\.lineX1], x2: mem[\.lineX2], y: mem[\.drawY], colour: mem[\.lineColour],
                                        linePatterns(mem)).map(LayerItem.line)
        },
        Native(drawing: \.verticalLine) { cpu in
            let mem = cpu.mem
            return LayerLine.vertical(x: mem[\.drawX], y1: mem[\.lineY1], y2: mem[\.lineY2], colour: mem[\.lineColour],
                                      linePatterns(mem)).map(LayerItem.line)
        },
    ]
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
        var matches: [KeyPath<GameSymbols, Routine>: Bool] = [:]
        for routine in Set(Native.all.flatMap { [$0.routine] + $0.uses }) {
            matches[routine] = GameSymbols.map[keyPath: routine].matches(mem, variant)
        }
        natives = Native.all.filter { n in ([n.routine] + n.uses).allSatisfy { matches[$0] ?? (n.run == nil) } }
        differing = matches.filter { !$0.value }.map { GameSymbols.name(of: $0.key) }.sorted()
    }
}
