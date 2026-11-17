import Apple2Kit
import Foundation

/// The engine of the Innovation Lab and its tutorial (side B) by name: its
/// pieces at $B8E0, $D000 and $F000, its robot state and tables in the
/// world's code at $0B00, and the paintbrush, which only the lab has.  In the
/// levels' order, name by name what `LevelsSymbols` has elsewhere.
/// With `GameSymbols`, its parent, all a world of this engine has
/// (RobotOdysseyLab.sym).  Docs/Symbols.md.
nonisolated final class LabSymbols: GameSymbols, EngineSymbols, @unchecked Sendable {
    let build = EngineBuild.lab
    let version: Version

    // MARK: robots and circuits, in the world's code ($0B00-$1FFF)

    // The robot drawing's tables (Docs/Robots.md).
    let grabberDX = Table(0x14A0)
    let grabberDY = Table(0x14A4)
    let scanDX = Table(0x14E4)
    let sparkDX = Table(0x14F2)
    let sparkDY = Table(0x14F5)

    /// The 10 parts drawn inside a robot: sprite pointer low and high bytes, x, y.
    let partSpritesLow = Table(0x14FA)
    let partSpritesHigh = Table(0x1504)
    let partX = Table(0x150E)
    let partY = Table(0x1518)

    /// Flame sprite pointers per thruster, for thruster values 1, 2 and 3 on:
    /// 8 bytes each, the 4 low bytes then the 4 high bytes.
    let flameSprites = Table(0x152A)
    let flameDX = Table(0x1542)
    let flameDY = Table(0x1546)
    let dotSprite = Sprite(0x6A40)
    let blankSprite = Sprite(0x6A50)

    /// Two spark patterns (robot 1).
    let sparkSprites = Sprite(0x6CC0)
    let windowSprite = Sprite(0x6C90)
    let antennaSprite = Sprite(0x6CE0)
    let signalSprite = Sprite(0x6CF0)

    /// The wires: the object at the other end, then the ends' coordinates,
    /// 256 each; loose wires from +$466 (World.wire).
    let wireTo = Table(0x0B00)
    let wireAX = Table(0x0C00)
    let wireBX = Table(0x0D00)
    let wireAY = Table(0x0E00)
    let wireBY = Table(0x0F00)

    /// Per sprite: 0 no pin, 1 and 2 a pin at (PIN_DX, PIN_DY) from the
    /// object, $FD, $FE (gates) and $F0 (chips) objects with several.
    let pinTypes = Table(0x1554, guess: true)
    let pinDX = Table(0x1594, guess: true)
    let pinDY = Table(0x15D4, guess: true)

    /// The tool in the player's hand, from TOOL_OBJECTS (TAKE_TOOL at
    /// $BE6D): $00 none, $FD the soldering pen (Docs/CopyProtection.md), $FC
    /// the remote control.
    let toolMode = Byte(0x128E, guess: true)

    /// The robots' state: 4 grabbers per robot, then $1A bytes per robot
    /// (`Robot.stateSize`) with the thrusters, bumper colours, battery and switch.
    let robotGrabbers = Table(0x129F)
    let robotState = Table(0x12AB)
    let robotThrusters = Table(0x12B7)
    let robotBumpers = Table(0x12BB)
    let robotBattery = Table(0x12C3)
    let robotSwitch = Table(0x12C4)

    /// 0 without a button, 1 on a new press, 2 once the grab code is done.
    let grabState = Byte(0x1300)

    /// The pin a wire was started at (SOLDER_WIRE; 0 none), and its PIN_TYPES entry.
    let solderPin = Byte(0x1303, guess: true)
    let solderPinType = Byte(0x1304, guess: true)

    /// Where the wire started, and the room: the player leaving it cuts the wire.
    let solderX = Byte(0x1309, guess: true)
    let solderY = Byte(0x130A, guess: true)
    let solderRoom = Byte(0x130B, guess: true)

    // The robot drawing's variables: the robot being drawn and its parts.
    let drawnGrabbers = Table(0x1358)
    let partIndex = Byte(0x13A8)

    /// This tick's move, kept by KEEP_MOVE.
    let keptDX = Byte(0x13A9)
    let keptDY = Byte(0x13AA)
    let antennaSignal = Byte(0x1368)
    let antennaColour = Byte(0x1369)
    let scanPosition = Byte(0x136A)
    let sparkToggle = Byte(0x136B)
    let rainbowColour = Byte(0x136C)
    let rainbowStep = Byte(0x136D)
    let rainbowX = Byte(0x136E)
    let rainbowBit = Byte(0x136F)
    let rainbowRow = Byte(0x1370)
    let rainbowBits = Byte(0x1371)
    let randomModulus = Byte(0x1372)
    let partsLoop = Byte(0x1373)
    let drawnBumpers = Table(0x1383)
    let drawnThrusters = Table(0x1387)
    let drawnSwitch = Byte(0x138F)
    let robotX = Byte(0x1390)
    let robotY = Byte(0x1391)

    /// A sprite the battery gauge's bar is built in.
    let batteryBar = Table(0x1396)

    /// The battery's charge, then the colour of the interior parts.
    let drawnBattery = Byte(0x13A6)

    // MARK: carrying and grabbing (in the levels the piece at $B8E0)

    /// GRAB_AND_CARRY's hook (GRAB_HOOK), every tick: the wire ends on the
    /// pins of HELD_OBJECT and of the objects that follow it (a gate's, a
    /// chip's...) move by KEPT_DX/DY, the player's move, as FOLLOW_AT moves
    /// the object by it; carried onto the room's edge (x + the move 0 or
    /// $84 on, y 0 or $AF on) or out of CARRY_ROOM, a pin's wires are cut
    /// (UNSOLDER).  With nothing held CARRY_ROOM goes to 0.  The kit's and
    /// the lab's are in their $F000 pieces.
    let carryWires = Routine(0xF0A0, guess: true)

    /// The room HELD_OBJECT was taken in (CARRY_WIRES; 0 nothing held).
    let carryRoom = Byte(0x1316, guess: true)

    /// GRAB_STATE from the buttons; the kit's and the lab's own copies
    /// (their code unchecked, so the native runs in the levels only).
    let grabButton = Routine(0x185A)

    // MARK: the lab's engine piece at $B8E0

    /// PAINTBRUSH ($BEBB, the lab's main loop calls it every tick): holding
    /// the paintbrush (TOOL_MODE $E0) in the maze rooms $0D-$14 turns
    /// WALLS_ON off, and the grab button paints the tile under the player
    /// (SET_WALL): a new press toggles it, held it paints the same value.
    let paintbrush = Routine(0xBEBB)

    /// POINTER and WALL_COLUMN, WALL_ROW of the tile under the player (x+4, y+8).
    let paintbrushTile = Routine(0xBF01)

    /// A tile on the room's edge is painted in the linked room too and stays
    /// a wall where the edge has no exit.
    let paintbrushEdges = Routine(0xBF1A)

    /// The value painted (SET_WALL's A) and WALL_ROW kept while painting the edges.
    let paintValue = Byte(0x13B1)
    let paintRow = Byte(0x13B2)

    /// WALL_COLUMN of x A (X_BYTE_TABLE / 2), 0 off the screen.
    let columnOfX = Routine(0xBFBE)

    /// WALL_ROW of y A (A / 16).
    let rowOfY = Routine(0xBFD5)

    // MARK: language card bank 2 at $D000 (moved in v1.0)

    let drawRobots = Routine(0xD2AB, code: 0xD2AB ..< 0xD674, md5: "249ae8aaef23046e12b763b3c8c68fc6")
    let drawRobot2Scan = Routine(0xD2B5)
    let drawRobot1Sparks = Routine(0xD347)
    let sparkPosition = Routine(0xD3EC)
    let randomBelowA = Routine(0xD40B)
    let random = Routine(0xD420)
    let randomStep = Routine(0xD42B)
    let drawRobot0Rainbow = Routine(0xD439)
    let drawRobotParts = Routine(0xD4BC)
    let drawRainbow = Routine(0xD5F4)
    let drawRobotInterior = Routine(0xD674, code: 0xD674 ..< 0xD768, md5: "eea7722c44735bfdf275fde18d3e9cb9")
    let drawBattery = Routine(0xD6B7)
    let drawInteriorParts = Routine(0xD705)

    /// The last call before the draw phase (`DrawPhase`).
    let playerInRobot: Routine

    // MARK: language card $E000-$FFFF

    /// The soldering pen, called each tick while the player holds it and the
    /// copy protection passed (Docs/CopyProtection.md).  SOLDER_TOUCH acts on
    /// what the pen touches while no wire is started; SOLDER_WIRE starts a
    /// wire at the first touch (with the solder sound) and makes it at the
    /// second.
    let solderTouch = Routine(0x18B0, guess: true)

    /// Cuts the wire of pin SOLDER_PIN (of type SOLDER_PIN_TYPE): what a
    /// new press does on a pin with a wire, with the solder sound.
    let unsolder = Routine(0x18C1, guess: true)
    let solderWire = Routine(0xF59B, guess: true)

    /// Z clear if the pen's tip (object $FE, TOUCH_ANY) touches a pin (a
    /// sprite with a PIN_TYPES entry), the tip orange (5) then, else blue
    /// (6); on a new press SOLDER_PIN is the pin and
    /// (POINT_X, POINT_Y) where it is (PIN_DX/DY, or found where the tip is
    /// on a gate or chip).
    let tipOnPin = Routine(0xF647, guess: true)

    /// The wire being made, white, from where it started to the tip + (2, 4).
    let drawSolderWire = Routine(0xFAE8, guess: true)

    /// The engine as the disks of `version` have it: in v1.0 some routines
    /// of the language card's $D000 bank are a few bytes further on.
    init(_ version: Version) {
        self.version = version
        let v1_0 = version == .v1_0
        playerInRobot = Routine(v1_0 ? 0xDBA7 : 0xDBAF)
        super.init()
    }
}
