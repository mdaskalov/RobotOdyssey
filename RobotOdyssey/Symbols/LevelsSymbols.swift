import Apple2Kit
import Foundation

/// The engine of the Robotropolis levels 1-5 (side A) by name: the levels'
/// engine pieces at $1A50, $B8E0, $D000 and $F000 and their variables in
/// the world image ($8200-$8EEF), with what only the levels have: the tools,
/// the fourth robot, the player's walk.  Sorted by address.
/// With `GameSymbols`, its parent, all a world of this engine has
/// (RobotOdyssey.sym, RobotOdyssey_v1.0.sym).  Docs/Symbols.md.
nonisolated final class LevelsSymbols: GameSymbols, EngineSymbols, @unchecked Sendable {
    let build = EngineBuild.levels
    let version: Version

    // MARK: the levels' engine piece at $1A50

    let keyTHandler = Routine(0x1A50)
    let eng1AB0 = Routine(0x1AB0)
    let eng1DB6 = Routine(0x1DB6)
    let formatNumbers = Routine(0x1DE1)
    let eng1E3B = Routine(0x1E3B)

    // MARK: robots and circuits, in the world image ($8200-$8EEF)

    // The robot drawing's tables (Docs/Robots.md).
    let grabberDX = Table(0x82D7)
    let grabberDY = Table(0x82DB)

    /// The tools (TAKE_TOOL), 3 each: the object ($00 the player's own
    /// look, $FD the soldering pen, $FC the remote control), the key that
    /// takes it (C, S, R), and the colour and sprite of the tool's tip
    /// (object $FE, on the player: the pen's, blank for the others).
    let toolObjects = Table(0x82F7)
    let toolKeys = Table(0x82FA)
    let toolTipColours = Table(0x82FD)
    let toolTipSprites = Table(0x8300)
    let scanDX = Table(0x831B)
    let sparkDX = Table(0x8329)
    let sparkDY = Table(0x832C)
    let pulseStart = Table(0x8331)
    let pulseColours = Table(0x8334)

    /// The 10 parts drawn inside a robot: sprite pointer low and high bytes, x, y.
    let partSpritesLow = Table(0x833D)
    let partSpritesHigh = Table(0x8347)
    let partX = Table(0x8351)
    let partY = Table(0x835B)

    /// Flame sprite pointers per thruster, for thruster values 1, 2 and 3 on:
    /// 8 bytes each, the 4 low bytes then the 4 high bytes.
    let flameSprites = Table(0x836D)
    let flameDX = Table(0x8385)
    let flameDY = Table(0x8389)
    let dotSprite = Sprite(0x84C4)
    let blankSprite = Sprite(0x84D4)

    /// Three nested squares (robot 3).
    let squareSprites = Sprite(0x84E4)

    /// Two spark patterns (robot 1).
    let sparkSprites = Sprite(0x8514)
    let windowSprite = Sprite(0x8534)
    let antennaSprite = Sprite(0x8544)
    let signalSprite = Sprite(0x8554)

    /// The wires: the object at the other end, then the ends' coordinates,
    /// 256 each; loose wires from +$466 (World.wire).
    let wireTo = Table(0x861C)
    let wireAX = Table(0x871C)
    let wireBX = Table(0x881C)
    let wireAY = Table(0x891C)
    let wireBY = Table(0x8A1C)
    let pinLine = Table(0x8A82, guess: true)

    /// Per sprite: 0 no pin, 1 and 2 a pin at (PIN_DX, PIN_DY) from the
    /// object, $FD, $FE (gates) and $F0 (chips) objects with several.
    let pinTypes = Table(0x8397, guess: true)

    /// The pin each chip's pins are wired to, 8 per chip (chips are objects
    /// $E7-$EE).
    let chipPinObjects = Table(0x8C9E, guess: true)
    let pinDX = Table(0x83D7, guess: true)
    let pinDY = Table(0x8417, guess: true)
    let gateType = Table(0x8CB7, guess: true)

    /// The tool in the player's hand, from TOOL_OBJECTS (TAKE_TOOL at
    /// $BE6D): $00 none, $FD the soldering pen (Docs/CopyProtection.md), $FC
    /// the remote control.
    let toolMode = Byte(0x8DAA, guess: true)

    /// The remote control's switch, the player's colour as its button left
    /// it (REMOTE_CONTROL): 5 (orange) the robots and the circuits run, 7
    /// (white) they stand still.
    let remoteSwitch = Byte(0x8DAB)

    /// The robots' state: 4 grabbers per robot, then $1A bytes per robot
    /// (`Robot.stateSize`) with the thrusters, bumper colours, battery and switch.
    let robotGrabbers = Table(0x8DBD)
    let robotState = Table(0x8DCD)
    let robotThrusters = Table(0x8DD9)
    let robotBumpers = Table(0x8DDD)
    let robotBattery = Table(0x8DE5)
    let robotSwitch = Table(0x8DE6)

    /// 0 without a button, 1 on a new press, 2 once the grab code is done.
    let grabState = Byte(0x8E3E)

    /// The pin a wire was started at (SOLDER_WIRE; 0 none), and its PIN_TYPES entry.
    let solderPin = Byte(0x8E40, guess: true)
    let solderPinType = Byte(0x8E41, guess: true)

    /// Where the wire started, and the room: the player leaving it cuts the wire.
    let solderX = Byte(0x8E46, guess: true)
    let solderY = Byte(0x8E47, guess: true)
    let solderRoom = Byte(0x8E48, guess: true)

    // The robot drawing's variables: the robot being drawn and its parts.
    let drawnGrabbers = Table(0x8E7E)
    let partIndex = Byte(0x8E82)

    /// This tick's move, kept by KEEP_MOVE.
    let keptDX = Byte(0x8E88)
    let keptDY = Byte(0x8E89)
    let playerRobot = Byte(0x8E95, guess: true)
    let antennaSignal = Byte(0x8E96)
    let antennaColour = Byte(0x8E97)
    let scanPosition = Byte(0x8E98)
    let sparkToggle = Byte(0x8E99)
    let rainbowColour = Byte(0x8E9A)
    let rainbowStep = Byte(0x8E9B)
    let rainbowX = Byte(0x8E9C)
    let rainbowBit = Byte(0x8E9D)
    let pulsePhase = Byte(0x8E9E)
    let rainbowRow = Byte(0x8E9F)
    let rainbowBits = Byte(0x8EA0)
    let randomModulus = Byte(0x8EA1)
    let partsLoop = Byte(0x8EA2)
    let drawnBumpers = Table(0x8EB2)
    let drawnThrusters = Table(0x8EB6)
    let drawnSwitch = Byte(0x8EBE)
    let robotX = Byte(0x8EBF)
    let robotY = Byte(0x8EC0)

    /// A sprite the battery gauge's bar is built in.
    let batteryBar = Table(0x8EC4)

    /// The battery's charge, then the colour of the interior parts.
    let drawnBattery = Byte(0x8ED4)

    /// One byte, a temporary of both the pulsing robot and the walk.
    let pulseIndex = Byte(0x8ED6)
    let walkTemp = Byte(0x8ED6)

    /// The player's walking frame, 0-7.
    let walkFrame = Byte(0x8ED7)

    /// The object a sentry holds ($FF none; the levels' and the Toolkit's
    /// sentry code, Level 1's L1_SENTRIES): Level 1's main loop skips
    /// READ_INPUT while it is the player (0) and calls $FE25 only while it is
    /// $FF; the thrusters don't move the robot it is ($D1FD).
    let sentryHeld = Byte(0x8ED8)

    /// Each level's own code and data from here to $94FF.
    let levelData = Table(0x8EF0)

    // MARK: the levels' engine piece at $B8E0

    /// GRAB_AND_CARRY's hook (GRAB_HOOK), every tick: the wire ends on the
    /// pins of HELD_OBJECT and of the objects that follow it (a gate's, a
    /// chip's...) move by KEPT_DX/DY, the player's move, as FOLLOW_AT moves
    /// the object by it; carried onto the room's edge (x + the move 0 or
    /// $84 on, y 0 or $AF on) or out of CARRY_ROOM, a pin's wires are cut
    /// (UNSOLDER).  With nothing held CARRY_ROOM goes to 0.  The kit's and
    /// the lab's are in their $F000 pieces.
    let carryWires = Routine(0xB8E6, guess: true)
    let engB8ED = Routine(0xB8ED)

    /// The room HELD_OBJECT was taken in (CARRY_WIRES; 0 nothing held).
    let carryRoom = Byte(0x8E55, guess: true)

    /// The tools, with nothing held: a key of TOOL_KEYS, or a new press of
    /// the button on a tool lying about (TOUCHED_TOOL), takes that tool (its
    /// own again puts it away): the player and the tool object swap sprite
    /// and colour (SWAP_WITH_PLAYER), so the player looks like the tool and
    /// the tool object keeps the player's look; the tip, object $FE, takes
    /// the tool's (TOOL_TIP_COLOURS, TOOL_TIP_SPRITES).
    let takeTool = Routine(0xBDE1)

    /// TOOL_OBJECTS' index of the tool asked for.
    let toolIndex = Byte(0x8E3F)

    /// TOOL_INDEX = 2 or 1 if the player touches the remote control or the
    /// pen (OBJECTS_TOUCH), else 0.
    let touchedTool = Routine(0xBE76)
    let putToolAway = Routine(0xBE97)

    /// Swaps the sprite and colour of the player (object 0) and object Y.
    let swapWithPlayer = Routine(0xBEA3)

    /// GRAB_STATE from the buttons; the kit's and the lab's own copies
    /// (their code unchecked, so the native runs in the levels only).
    let grabButton = Routine(0xBEBC, code: 0xBEBC ..< 0xBED6, md5: "901b150e06b79c82488a264e17b0a4d8")

    /// With the remote control in hand, a new press of the button (not on
    /// the remote's object) toggles the player's colour and REMOTE_SWITCH
    /// between 5 and 7.
    let remoteControl = Routine(0xBED6)

    /// The player's 8 walking frames.
    let playerSprites = Table(0xBF30)

    // MARK: language card bank 2 at $D000 (moved in v1.0)

    let robotsReset = Routine(0xD000, guess: true)
    let drawRobots = Routine(0xD2BC, code: 0xD2BC ..< 0xD72B, md5: "5447b8f3858ebea8813956241469839f")
    let drawRobot2Scan = Routine(0xD2C8)
    let drawRobot1Sparks = Routine(0xD359)
    let sparkPosition = Routine(0xD3F5)
    let randomBelowA = Routine(0xD414)
    let random = Routine(0xD429)
    let randomStep = Routine(0xD434)
    let drawBlank = Routine(0xD442)
    let drawRobot0Rainbow = Routine(0xD44D)
    let drawRobot3Pulse = Routine(0xD4CC)
    let drawRobotParts = Routine(0xD573)
    let drawRainbow = Routine(0xD6AB)
    let drawRobotInterior: Routine
    let drawBattery = Routine(0xD783)
    let drawInteriorParts: Routine
    let robotsThrusters: Routine
    let engDA44: Routine
    let engDA90: Routine

    /// The last call before the draw phase (`DrawPhase`).
    let playerInRobot = Routine(0xDD59)
    let engDDD0 = Routine(0xDDD0)
    let robots4Update: Routine
    let crystals: Routine
    let crystals2: Routine
    let playerWalkSprite: Routine

    // MARK: language card $E000-$FFFF

    let gatesEval = Routine(0xF04B, guess: true)
    let wiresPropagate = Routine(0xF0CC)
    let sensors = Routine(0xF44D, guess: true)
    let chipsEval = Routine(0xF56B, guess: true)
    let engF5A9 = Routine(0xF5A9)

    /// The soldering pen, called each tick while the player holds it and the
    /// copy protection passed (Docs/CopyProtection.md).  SOLDER_TOUCH acts on
    /// what the pen touches while no wire is started; SOLDER_WIRE starts a
    /// wire at the first touch (with the solder sound) and makes it at the
    /// second.
    let solderTouch = Routine(0xF5C2, guess: true)

    /// Cuts the wire of pin SOLDER_PIN (of type SOLDER_PIN_TYPE): what a
    /// new press does on a pin with a wire, with the solder sound.
    let unsolder = Routine(0xF5D3, guess: true)
    let solderWire = Routine(0xF7BE, guess: true)

    /// X not 0 if pin A is taken: a wire's target (WIRE_TO), a loose
    /// wire's, or on a chip (CHIP_PIN_OBJECTS, X the chip's object).
    let pinTaken = Routine(0xF78C, guess: true)

    /// Z clear if the pen's tip (object $FE, TOUCH_ANY) touches a pin (a
    /// sprite with a PIN_TYPES entry), the tip orange (5) then, else blue
    /// (6); on a new press SOLDER_PIN is the pin and
    /// (POINT_X, POINT_Y) where it is (PIN_DX/DY, or found where the tip is
    /// on a gate or chip).
    let tipOnPin = Routine(0xF86A, guess: true)

    /// The wire being made, white, from where it started to the tip + (2, 4).
    let drawSolderWire = Routine(0xFC2C, guess: true)
    let drawWires = Routine(0xFC62)
    let keepMove = Routine(0xFE18, code: 0xFE18 ..< 0xFE25, md5: "1544988aa9cbb3fa4337cfe931fb8fd9")
    let engFE25 = Routine(0xFE25)

    /// The engine as the disks of `version` have it: in v1.0 some routines
    /// of the language card's $D000 bank are a few bytes further on.
    init(_ version: Version) {
        self.version = version
        let v1_0 = version == .v1_0
        drawRobotInterior = v1_0
            ? Routine(0xD72B, code: 0xD72B ..< 0xD834, md5: "85a132191621633fdbb838215623f744")
            : Routine(0xD72B, code: 0xD72B ..< 0xD832, md5: "cea4338383bb52042f5d15c5c267cde1")
        drawInteriorParts = Routine(v1_0 ? 0xD7D1 : 0xD7D0)
        robotsThrusters = Routine(v1_0 ? 0xD834 : 0xD832, guess: true)
        engDA44 = Routine(v1_0 ? 0xDA46 : 0xDA44)
        engDA90 = Routine(v1_0 ? 0xDA93 : 0xDA90)
        robots4Update = Routine(v1_0 ? 0xDE11 : 0xDE10, guess: true)
        crystals = Routine(v1_0 ? 0xDE96 : 0xDE95, guess: true)
        crystals2 = Routine(v1_0 ? 0xDF82 : 0xDF81, guess: true)
        playerWalkSprite = v1_0
            ? Routine(0xDFA4, code: 0xDFA4 ..< 0xDFFF, md5: "4914207a999e6cbaf578c4a2dfc736cf")
            : Routine(0xDFA3, code: 0xDFA3 ..< 0xDFFE, md5: "b44ec2e623245f6dbcd62bf38e665caa")
        super.init()
    }
}
