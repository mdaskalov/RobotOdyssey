import Apple2Kit
import Foundation

/// The engine of Robot Anatomy and Toolkit (side B) by name: its pieces at
/// $B900, $D000 and $F000, its robot state and tables in the world's code at
/// $14C0.  In the levels' order, name by name what `LevelsSymbols` has
/// elsewhere (what a name stands for is told there).
/// With `GameSymbols`, its parent, all a world of this engine has
/// (RobotOdysseyKit.sym).  Docs/Symbols.md.
nonisolated final class KitSymbols: GameSymbols, EngineSymbols, @unchecked Sendable {
    let build = EngineBuild.kit
    let version: Version

    // MARK: robots and circuits, in the world's code ($14C0-$1FFF)

    // The robot drawing's tables (Docs/Robots.md).
    let grabberDX = Table(0x1CC4)
    let grabberDY = Table(0x1CC8)
    let scanDX = Table(0x1D04)
    let sparkDX = Table(0x1D12)
    let sparkDY = Table(0x1D15)

    /// The 10 parts drawn inside a robot: sprite pointer low and high bytes, x, y.
    let partSpritesLow = Table(0x1D1A)
    let partSpritesHigh = Table(0x1D24)
    let partX = Table(0x1D2E)
    let partY = Table(0x1D38)

    /// Flame sprite pointers per thruster, for thruster values 1, 2 and 3 on:
    /// 8 bytes each, the 4 low bytes then the 4 high bytes.
    let flameSprites = Table(0x1D4A)
    let flameDX = Table(0x1D62)
    let flameDY = Table(0x1D66)
    let dotSprite = Sprite(0x1E98)
    let blankSprite = Sprite(0x1EA8)

    /// Two spark patterns (robot 1).
    let sparkSprites = Sprite(0x1EB8)
    let windowSprite = Sprite(0x1ED8)
    let antennaSprite = Sprite(0x1EE8)
    let signalSprite = Sprite(0x1EF8)

    /// The wires: the object at the other end, then the ends' coordinates,
    /// 256 each; loose wires from +$466 (World.wire).
    let wireTo = Table(0x14C0)
    let wireAX = Table(0x15C0)
    let wireBX = Table(0x16C0)
    let wireAY = Table(0x17C0)
    let wireBY = Table(0x18C0)

    /// Per sprite: 0 no pin, 1 and 2 a pin at (PIN_DX, PIN_DY) from the
    /// object, $FD, $FE (gates) and $F0 (chips) objects with several.
    let pinTypes = Table(0x1D74, guess: true)
    let pinDX = Table(0x1DB4, guess: true)
    let pinDY = Table(0x1DF4, guess: true)

    /// The tool in the player's hand, from TOOL_OBJECTS (TAKE_TOOL at
    /// $BE6D): $00 none, $FD the soldering pen (Docs/CopyProtection.md), $FC
    /// the remote control.
    let toolMode = Byte(0x1ACE, guess: true)

    /// The robots' state: 4 grabbers per robot, then $1A bytes per robot
    /// (`Robot.stateSize`) with the thrusters, bumper colours, battery and switch.
    let robotGrabbers = Table(0x1ADF)
    let robotState = Table(0x1AEB)
    let robotThrusters = Table(0x1AF7)
    let robotBumpers = Table(0x1AFB)
    let robotBattery = Table(0x1B03)
    let robotSwitch = Table(0x1B04)

    /// 0 without a button, 1 on a new press, 2 once the grab code is done.
    let grabState = Byte(0x1B40)

    /// The pin a wire was started at (SOLDER_WIRE; 0 none), and its PIN_TYPES entry.
    let solderPin = Byte(0x1B42, guess: true)
    let solderPinType = Byte(0x1B43, guess: true)

    /// Where the wire started, and the room: the player leaving it cuts the wire.
    let solderX = Byte(0x1B48, guess: true)
    let solderY = Byte(0x1B49, guess: true)
    let solderRoom = Byte(0x1B4A, guess: true)

    // The robot drawing's variables: the robot being drawn and its parts.
    let drawnGrabbers = Table(0x1B97)
    let partIndex = Byte(0x1BE7)

    /// This tick's move, kept by KEEP_MOVE.
    let keptDX = Byte(0x1BE8)
    let keptDY = Byte(0x1BE9)
    let antennaSignal = Byte(0x1BA7)
    let antennaColour = Byte(0x1BA8)
    let scanPosition = Byte(0x1BA9)
    let sparkToggle = Byte(0x1BAA)
    let rainbowColour = Byte(0x1BAB)
    let rainbowStep = Byte(0x1BAC)
    let rainbowX = Byte(0x1BAD)
    let rainbowBit = Byte(0x1BAE)
    let rainbowRow = Byte(0x1BAF)
    let rainbowBits = Byte(0x1BB0)
    let randomModulus = Byte(0x1BB1)
    let partsLoop = Byte(0x1BB2)
    let drawnBumpers = Table(0x1BC2)
    let drawnThrusters = Table(0x1BC6)
    let drawnSwitch = Byte(0x1BCE)
    let robotX = Byte(0x1BCF)
    let robotY = Byte(0x1BD0)

    /// A sprite the battery gauge's bar is built in.
    let batteryBar = Table(0x1BD5)

    /// The battery's charge, then the colour of the interior parts.
    let drawnBattery = Byte(0x1BE5)

    // MARK: carrying and grabbing (in the levels the piece at $B8E0)

    /// GRAB_AND_CARRY's hook (GRAB_HOOK), every tick: the wire ends on the
    /// pins of HELD_OBJECT and of the objects that follow it (a gate's, a
    /// chip's...) move by KEPT_DX/DY, the player's move, as FOLLOW_AT moves
    /// the object by it; carried onto the room's edge (x + the move 0 or
    /// $84 on, y 0 or $AF on) or out of CARRY_ROOM, a pin's wires are cut
    /// (UNSOLDER).  With nothing held CARRY_ROOM goes to 0.  The kit's and
    /// the lab's are in their $F000 pieces.
    let carryWires = Routine(0xF367, guess: true)

    /// The room HELD_OBJECT was taken in (CARRY_WIRES; 0 nothing held).
    let carryRoom = Byte(0x1B58, guess: true)

    /// GRAB_STATE from the buttons; the kit's and the lab's own copies
    /// (their code unchecked, so the native runs in the levels only).
    let grabButton = Routine(0xBEDB)

    // MARK: language card bank 2 at $D000 (moved in v1.0)

    let drawRobots = Routine(0xD2AB, code: 0xD2AB ..< 0xD674, md5: "58cfaa0bf4b3df5a27c2aa5165d16520")
    let drawRobot2Scan = Routine(0xD2B5)
    let drawRobot1Sparks = Routine(0xD347)
    let sparkPosition = Routine(0xD3EC)
    let randomBelowA = Routine(0xD40B)
    let random = Routine(0xD420)
    let randomStep = Routine(0xD42B)
    let drawRobot0Rainbow = Routine(0xD439)
    let drawRobotParts = Routine(0xD4BC)
    let drawRainbow = Routine(0xD5F4)
    let drawRobotInterior = Routine(0xD674, code: 0xD674 ..< 0xD768, md5: "ad6199bae84669dd1309f417d8a6f25c")
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
    let solderTouch = Routine(0xF1AF, guess: true)

    /// Cuts the wire of pin SOLDER_PIN (of type SOLDER_PIN_TYPE): what a
    /// new press does on a pin with a wire, with the solder sound.
    let unsolder = Routine(0xF1C0, guess: true)
    let solderWire = Routine(0xF652, guess: true)

    /// Z clear if the pen's tip (object $FE, TOUCH_ANY) touches a pin (a
    /// sprite with a PIN_TYPES entry), the tip orange (5) then, else blue
    /// (6); on a new press SOLDER_PIN is the pin and
    /// (POINT_X, POINT_Y) where it is (PIN_DX/DY, or found where the tip is
    /// on a gate or chip).
    let tipOnPin = Routine(0xF6F2, guess: true)

    /// The wire being made, white, from where it started to the tip + (2, 4).
    let drawSolderWire = Routine(0xFA78, guess: true)

    /// The engine as the disks of `version` have it: in v1.0 some routines
    /// of the language card's $D000 bank are a few bytes further on.
    init(_ version: Version) {
        self.version = version
        let v1_0 = version == .v1_0
        playerInRobot = Routine(v1_0 ? 0xDC11 : 0xDC16)
        super.init()
    }
}
