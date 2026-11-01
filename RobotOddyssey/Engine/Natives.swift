import Foundation

/// The machine as a native routine sees it: memory with the game's symbols
/// (`m`), the registers (`r`) and the input devices.  The ported routines are
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
    var r: Registers
    var devices: InputDevices
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

/// A native routine: Swift in place of the engine routine `routine`, run
/// when the 6502 code reaches its entry, returning like RTS.  It leaves
/// memory exactly as the original does (and the registers, where callers use
/// them), so it replaces the routine only where the code of the routine and
/// of every routine it reproduces (`uses`) is exactly the code it was ported
/// from: their fingerprints in GameSymbols (`CodeCheck`).
/// Data/native_check.sh compares each with the original.
nonisolated struct Native {
    let routine: KeyPath<GameSymbols, Routine>
    let uses: [KeyPath<GameSymbols, Routine>]
    /// The worlds' code calls it and uses the registers it leaves, so it
    /// leaves them as the original does; otherwise only memory counts.
    let leavesRegisters: Bool
    /// False: declined, having changed nothing, and the original code runs.
    let run: (inout Engine) -> Bool

    var name: String { GameSymbols.name(of: routine) }
}

nonisolated extension Native {
    init(_ routine: KeyPath<GameSymbols, Routine>, uses: [KeyPath<GameSymbols, Routine>] = [],
         leavesRegisters: Bool = true, _ run: @escaping (inout Engine) -> Void) {
        self.init(routine: routine, uses: uses, leavesRegisters: leavesRegisters) { e in
            run(&e)
            return true
        }
    }

    init(_ routine: KeyPath<GameSymbols, Routine>, uses: [KeyPath<GameSymbols, Routine>],
         mayDecline run: @escaping (inout Engine) -> Bool) {
        self.init(routine: routine, uses: uses, leavesRegisters: true, run: run)
    }

    /// What the robot drawing draws with.
    private static let graphics: [KeyPath<GameSymbols, Routine>] = [
        \.drawSpriteColour, \.drawSprite, \.plot, \.horizontalLine, \.verticalLine, \.clampX, \.clampY, \.drawBox]
    /// STOP_AT_WALLS and what it calls.
    private static let walls: [KeyPath<GameSymbols, Routine>] = [
        \.stopAtWalls, \.testMove, \.stopAtTileColumn, \.stopAtTileRow, \.magnitude, \.roomWallsPointer, \.wallAt]
    private static let moving: [KeyPath<GameSymbols, Routine>] = [\.moveObject, \.moveObjectXY, \.setObjectRoom]

    /// Every native routine, by address.
    static let all: [Native] = [
        Native(\.roomWallsPointer) { $0.roomWallsPointer() },
        Native(\.moveObject, uses: moving) { $0.moveObject() },
        Native(\.moveObjectXY, uses: [\.setObjectRoom]) { $0.moveObjectXY() },
        Native(\.setObjectRoom) { $0.setObjectRoom() },
        Native(\.readInput, uses: [\.readDevice, \.readKey, \.keyAsStick, \.readJoystick, \.moveByKey, \.moveByStick,
                                   \.clearButtons, \.limitMove, \.withSign, \.keepOnScreen] + walls + moving,
               mayDecline: { $0.readInput() }),
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
    ]
}

/// The loader's check of a world's engine code, made when it loads the world
/// (before any of the code runs; the worlds' start-up code changes no engine
/// code): which natives may replace their routines, and which routines differ
/// from the version's code (a modified or damaged disk).  Those, and the
/// natives that need them, run as the original 6502 code.
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
        natives = Native.all.filter { n in ([n.routine] + n.uses).allSatisfy { matches[$0] == true } }
        differing = matches.filter { !$0.value }.map { GameSymbols.name(of: $0.key) }.sorted()
    }
}
