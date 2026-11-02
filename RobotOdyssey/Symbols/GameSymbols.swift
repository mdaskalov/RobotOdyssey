import Foundation

/// The game's memory by name: the variables, tables, sprites and routines of
/// the engine and the world image, each with its address in every engine and
/// version, and for the routines that natives replace the fingerprint of their
/// code.  The one place for these addresses: the native routines use them by
/// name (`RAM`), the loader checks the fingerprints (`CodeCheck`), and
/// Data/ro_symbols.sh writes the Mariani .sym files from it.
///
/// A symbol given one address is there in every world and version; one given
/// per engine exists only in those engines.  Only the language card's $D000
/// bank moved between v1.0 and v1.1 (`levelsV1_0`, `kitV1_0`, `labV1_0`).
/// Sorted by address in the levels.  See Docs/Symbols.md.
nonisolated final class GameSymbols: Sendable {
    static let map = GameSymbols()

    // MARK: zero page

    /// The engine's pointer, e.g. to a room's wall bitmap (ROOM_WALLS_PTR).
    let pointer = Word(0x00)
    /// WALL_AT's tile column (0-19) and row (0-11 from the bottom).
    let wallColumn = Byte(0x02)
    let wallRow = Byte(0x03)
    let textPointer = Word(0x0A)
    /// The sprite to draw (16 rows, row 0 at the bottom) and its colour
    /// patterns for even and odd byte columns.
    let spritePointer = Word(0x0D)
    let patternEven = Byte(0x0F)
    let patternOdd = Byte(0x10)
    /// The hi-res line being drawn.
    let linePointer = Word(0x11)
    let spriteBits = Byte(0x13)
    /// Where to draw: y counted from the bottom, x 0-139 (two pixels each).
    let drawY = Byte(0x14)
    let maskTemp = Byte(0x15)
    /// The line high bytes of the page drawn on (FLIP_PAGE sets it).
    let lineHighTable = Word(0x16)
    let drawX = Byte(0x18)
    let jumpVector = Word(0x19)
    /// The random generator, a 16-bit shift register (RANDOM).
    let randomLow = Byte(0x4E)
    let randomHigh = Byte(0x4F)
    /// The sound playing (Docs/Sound.md): PLAY_TONE's half period in loop
    /// iterations, PLAY_NOISE's shift register, the loop iterations left (low
    /// byte, then blocks of 256), PLAY_NOISE's period, and the sweep: every
    /// (sweep & $7F) iterations the period grows by 1 (bit 7 set) or shrinks.
    let tonePeriod = Byte(0x50)
    let noiseLow = Byte(0x51)
    let noiseHigh = Byte(0x52)
    let soundCountLow = Byte(0x53)
    let soundCountHigh = Byte(0x54)
    let noisePeriod = Byte(0x55)
    let soundSweep = Byte(0x56)

    // MARK: between the worlds and the loader

    /// What a world asks of the loader when it hands back (`JMP (RESET_VECTOR)`):
    /// 0 start (title), 1 the menu, 2 the next level (NEXT_LEVEL), 3 start
    /// again, 4 save the game, 5 load chip NEXT_LEVEL, 6 save it.
    let menuMode = Byte(0x02D0)
    /// The level, or the chip, the request is for.
    let nextLevel = Byte(0x02D1)
    /// The world as the loader counts them (GameCatalog.byWorldIndex): 0-4
    /// levels 1-5 (set by each level), 5 the lab, 6-8 Robot Anatomy, Toolkit,
    /// the lab tutorial; saved with a game.
    let worldIndex = Byte(0x02D2)
    /// MENU_MODE EOR $A5, set with it: LOADER_START takes MENU_MODE only
    /// when they match (and engine main is intact), else starts with the title.
    let menuModeCheck = Byte(0x02CF)
    let resetVector = Word(0x03F2)
    /// The key that turns WALLS_ON off and on in the levels (KEY_COMMANDS):
    /// none ($00, the title clears it) unless Ctrl-A, Ctrl-L, T were typed in
    /// the menu: then Ctrl-E ($85).
    let wallsKey = Byte(0x03FF)
    /// Every world's code starts here (Level 1's: Level1Symbols).
    let worldStart = Routine(0x0803)
    /// Every world's: queues sound X of the world's sound table for room A
    /// (the engine's sounds are 0-8, GameSounds).
    let worldSound = Routine(0x0806)

    // MARK: the levels' engine piece at $1A50

    let keyTHandler = Routine(levels: 0x1A50)
    let eng1AB0 = Routine(levels: 0x1AB0)
    let eng1DB6 = Routine(levels: 0x1DB6)
    let formatNumbers = Routine(levels: 0x1DE1)
    let eng1E3B = Routine(levels: 0x1E3B)

    // MARK: the world: objects ($6000-$69FF, 256 each)

    let objNext = Table(0x6000)
    let objSprite = Table(0x6100)
    let objColour = Table(0x6200)
    let objRoom = Table(0x6300)
    let objX = Table(0x6400)
    let objY = Table(0x6500)
    let objLink = Table(0x6600)
    let objLinkDX = Table(0x6700)
    let objLinkDY = Table(0x6800)
    let objFlags = Table(0x6900)
    /// 64 sprites of 16 rows; sprite 0 is the player.
    let sprites = Table(0x6A00)

    // MARK: rooms ($6E00-$6FFF, 64 each; walls: 30 bytes each)

    let roomFirstObject = Table(0x6E00)
    let roomFloorColour = Table(0x6E40)
    let roomWallColour = Table(0x6E80)
    let roomUp = Table(0x6EC0)
    let roomDown = Table(0x6F00)
    let roomRight = Table(0x6F40)
    let roomLeft = Table(0x6F80)
    let roomUnused = Table(0x6FC0)
    let roomWalls = Table(0x7000)
    let world7780 = Table(0x7780, guess: true)

    // MARK: texts ($7880-$7C7F, 128 each; strings from $7C80)

    let textRoom = Table(0x7880)
    let textX = Table(0x7900)
    let textY = Table(0x7980)
    let textStyle = Table(0x7A00)
    let textUnused = Table(0x7A80)
    let textColour = Table(0x7B00)
    let textPointerLow = Table(0x7B80)
    let textPointerHigh = Table(0x7C00)
    let textStrings = Table(0x7C80)

    // MARK: robots and circuits (the kit and the lab keep theirs in their code segments)

    /// The robots' body objects and interior rooms, 4 each.
    let robotBody = Table(0x8200)
    let robotInterior = Table(0x8204)
    // The robot drawing's tables (Docs/Robots.md).
    let grabberDX = Table(levels: 0x82D7, kit: 0x1CC4, lab: 0x14A0)
    let grabberDY = Table(levels: 0x82DB, kit: 0x1CC8, lab: 0x14A4)
    /// The tools (TAKE_TOOL), 3 each: the object ($00 the player's own
    /// look, $FD the soldering pen, $FC the remote control), the key that
    /// takes it (C, S, R), and the colour and sprite of the tool's tip
    /// (object $FE, on the player: the pen's, blank for the others).
    let toolObjects = Table(levels: 0x82F7)
    let toolKeys = Table(levels: 0x82FA)
    let toolTipColours = Table(levels: 0x82FD)
    let toolTipSprites = Table(levels: 0x8300)
    let scanDX = Table(levels: 0x831B, kit: 0x1D04, lab: 0x14E4)
    let sparkDX = Table(levels: 0x8329, kit: 0x1D12, lab: 0x14F2)
    let sparkDY = Table(levels: 0x832C, kit: 0x1D15, lab: 0x14F5)
    let pulseStart = Table(levels: 0x8331)
    let pulseColours = Table(levels: 0x8334)
    /// The 10 parts drawn inside a robot: sprite pointer low and high bytes, x, y.
    let partSpritesLow = Table(levels: 0x833D, kit: 0x1D1A, lab: 0x14FA)
    let partSpritesHigh = Table(levels: 0x8347, kit: 0x1D24, lab: 0x1504)
    let partX = Table(levels: 0x8351, kit: 0x1D2E, lab: 0x150E)
    let partY = Table(levels: 0x835B, kit: 0x1D38, lab: 0x1518)
    /// Flame sprite pointers per thruster, for thruster values 1, 2 and 3 on:
    /// 8 bytes each, the 4 low bytes then the 4 high bytes.
    let flameSprites = Table(levels: 0x836D, kit: 0x1D4A, lab: 0x152A)
    let flameDX = Table(levels: 0x8385, kit: 0x1D62, lab: 0x1542)
    let flameDY = Table(levels: 0x8389, kit: 0x1D66, lab: 0x1546)
    let dotSprite = Sprite(levels: 0x84C4, kit: 0x1E98, lab: 0x6A40)
    let blankSprite = Sprite(levels: 0x84D4, kit: 0x1EA8, lab: 0x6A50)
    /// Three nested squares (robot 3).
    let squareSprites = Sprite(levels: 0x84E4)
    /// Two spark patterns (robot 1).
    let sparkSprites = Sprite(levels: 0x8514, kit: 0x1EB8, lab: 0x6CC0)
    let windowSprite = Sprite(levels: 0x8534, kit: 0x1ED8, lab: 0x6C90)
    let antennaSprite = Sprite(levels: 0x8544, kit: 0x1EE8, lab: 0x6CE0)
    let signalSprite = Sprite(levels: 0x8554, kit: 0x1EF8, lab: 0x6CF0)
    /// The wires: the object at the other end, then the ends' coordinates,
    /// 256 each; loose wires from +$466 (World.wire).
    let wireTo = Table(levels: 0x861C, kit: 0x14C0, lab: 0x0B00)
    let wireAX = Table(levels: 0x871C, kit: 0x15C0, lab: 0x0C00)
    let wireBX = Table(levels: 0x881C, kit: 0x16C0, lab: 0x0D00)
    let wireAY = Table(levels: 0x891C, kit: 0x17C0, lab: 0x0E00)
    let wireBY = Table(levels: 0x8A1C, kit: 0x18C0, lab: 0x0F00)
    let pinLine = Table(levels: 0x8A82, guess: true)
    let gateType = Table(levels: 0x8CB7, guess: true)
    /// The tool in the player's hand, from TOOL_OBJECTS (TAKE_TOOL at
    /// $BE6D): $00 none, $FD the soldering pen (Docs/CopyProtection.md), $FC
    /// the remote control.
    let toolMode = Byte(levels: 0x8DAA, kit: 0x1ACE, lab: 0x128E, guess: true)
    /// The remote control's switch, the player's colour as its button left
    /// it (REMOTE_CONTROL): 5 (orange) the robots and the circuits run, 7
    /// (white) they stand still.
    let remoteSwitch = Byte(levels: 0x8DAB)
    /// The robots' state: 4 grabbers per robot, then $1A bytes per robot
    /// (`Robot.stateSize`) with the thrusters, bumper colours, battery and switch.
    let robotGrabbers = Table(levels: 0x8DBD, kit: 0x1ADF, lab: 0x129F)
    let robotState = Table(levels: 0x8DCD, kit: 0x1AEB, lab: 0x12AB)
    let robotThrusters = Table(levels: 0x8DD9, kit: 0x1AF7, lab: 0x12B7)
    let robotBumpers = Table(levels: 0x8DDD, kit: 0x1AFB, lab: 0x12BB)
    let robotBattery = Table(levels: 0x8DE5, kit: 0x1B03, lab: 0x12C3)
    let robotSwitch = Table(levels: 0x8DE6, kit: 0x1B04, lab: 0x12C4)
    /// 0 without a button, 1 on a new press, 2 once the grab code is done.
    let grabState = Byte(levels: 0x8E3E, kit: 0x1B40, lab: 0x1300)
    // The robot drawing's variables: the robot being drawn and its parts.
    let drawnGrabbers = Table(levels: 0x8E7E, kit: 0x1B97, lab: 0x1358)
    let partIndex = Byte(levels: 0x8E82, kit: 0x1BE7, lab: 0x13A8)
    /// This tick's move, kept by KEEP_MOVE.
    let keptDX = Byte(levels: 0x8E88)
    let keptDY = Byte(levels: 0x8E89)
    let playerRobot = Byte(levels: 0x8E95, guess: true)
    let antennaSignal = Byte(levels: 0x8E96, kit: 0x1BA7, lab: 0x1368)
    let antennaColour = Byte(levels: 0x8E97, kit: 0x1BA8, lab: 0x1369)
    let scanPosition = Byte(levels: 0x8E98, kit: 0x1BA9, lab: 0x136A)
    let sparkToggle = Byte(levels: 0x8E99, kit: 0x1BAA, lab: 0x136B)
    let rainbowColour = Byte(levels: 0x8E9A, kit: 0x1BAB, lab: 0x136C)
    let rainbowStep = Byte(levels: 0x8E9B, kit: 0x1BAC, lab: 0x136D)
    let rainbowX = Byte(levels: 0x8E9C, kit: 0x1BAD, lab: 0x136E)
    let rainbowBit = Byte(levels: 0x8E9D, kit: 0x1BAE, lab: 0x136F)
    let pulsePhase = Byte(levels: 0x8E9E)
    let rainbowRow = Byte(levels: 0x8E9F, kit: 0x1BAF, lab: 0x1370)
    let rainbowBits = Byte(levels: 0x8EA0, kit: 0x1BB0, lab: 0x1371)
    let randomModulus = Byte(levels: 0x8EA1, kit: 0x1BB1, lab: 0x1372)
    let partsLoop = Byte(levels: 0x8EA2, kit: 0x1BB2, lab: 0x1373)
    let drawnBumpers = Table(levels: 0x8EB2, kit: 0x1BC2, lab: 0x1383)
    let drawnThrusters = Table(levels: 0x8EB6, kit: 0x1BC6, lab: 0x1387)
    let drawnSwitch = Byte(levels: 0x8EBE, kit: 0x1BCE, lab: 0x138F)
    let robotX = Byte(levels: 0x8EBF, kit: 0x1BCF, lab: 0x1390)
    let robotY = Byte(levels: 0x8EC0, kit: 0x1BD0, lab: 0x1391)
    /// A sprite the battery gauge's bar is built in.
    let batteryBar = Table(levels: 0x8EC4, kit: 0x1BD5, lab: 0x1396)
    /// The battery's charge, then the colour of the interior parts.
    let drawnBattery = Byte(levels: 0x8ED4, kit: 0x1BE5, lab: 0x13A6)
    /// One byte, a temporary of both the pulsing robot and the walk.
    let pulseIndex = Byte(levels: 0x8ED6)
    let walkTemp = Byte(levels: 0x8ED6)
    /// The player's walking frame, 0-7.
    let walkFrame = Byte(levels: 0x8ED7)
    let flag8ED8 = Byte(levels: 0x8ED8, guess: true)
    /// Each level's own code and data from here to $94FF.
    let levelData = Table(levels: 0x8EF0)

    // MARK: engine main ($9500-$B7D6, one file for every world and version)

    let fontBase = Table(0x9460)
    let font = Table(0x9500)
    /// Hi-res line addresses (low bytes) by y counted from the bottom.
    let lineLowTable = Table(0x9839)
    /// (2x) mod 7 and the byte column of x.
    let xShiftTable = Table(0x9A79)
    let xByteTable = Table(0x9B05)
    /// The colours' patterns (32 colours): 0 and 1 are the sprites' for even
    /// and odd byte columns.
    let colourPattern0 = Table(0x9B91)
    let colourPattern1 = Table(0x9BB1)
    let colourPattern2 = Table(0x9BD1)
    let colourPattern3 = Table(0x9BF1)
    /// The ten keys a world sets: up, down, left, right, button A, button B,
    /// then slowly up, down, left, right.
    let moveKeys = Table(0x9C13)
    let caseMask = Byte(0x9C21)
    /// The move of CUR_OBJECT.
    let moveDX = Byte(0x9C22)
    let moveDY = Byte(0x9C23)
    /// What the player holds, $FF nothing: the first object of the link
    /// chain from GRABBED_OBJECT on, the one GRAB_AND_CARRY moves along.
    let heldObject = Byte(0x9C26)
    /// The object the player took hold of, $FF nothing.
    let grabbedObject = Byte(0x9C27)
    /// FOLLOW_AT's offset from the object followed.
    let followDX = Byte(0x9C24)
    let followDY = Byte(0x9C25)
    let currentRoom = Byte(0x9C2D)
    let destinationRoom = Byte(0x9C2E)
    let currentObject = Byte(0x9C2F)
    let wallsOn = Byte(0x9C30)
    /// The objects OBJECTS_TOUCH compares.
    let touchFirst = Byte(0x9C31)
    let touchSecond = Byte(0x9C32)
    /// Lines and boxes: colour and ends.
    let lineColour = Byte(0x9C34)
    let lineX1 = Byte(0x9C35)
    let lineY1 = Byte(0x9C36)
    let lineX2 = Byte(0x9C37)
    let lineY2 = Byte(0x9C38)
    /// The joystick position ($80 the centre).
    let stickX = Byte(0x9C39)
    let stickY = Byte(0x9C3A)
    /// 1 while pressed.
    let buttonA = Byte(0x9C3B)
    let buttonB = Byte(0x9C3C)
    /// The key of this tick (0: none), 0 once used.
    let lastKey = Byte(0x9C3D)
    /// 0 keyboard, 1 joystick, 2 mouse.
    let inputDevice = Byte(0x9C3E)
    let tileFloorPattern = Table(0x9C3F)
    let tileWallPattern = Table(0x9C43)
    let drawPage = Byte(0x9C47)
    /// The text being drawn.
    let currentTextPointer = Word(0x9C48)
    let currentTextStyle = Byte(0x9C4A)
    let currentTextColour = Byte(0x9C4B)
    let currentTextX = Byte(0x9C4C)
    let currentTextY = Byte(0x9C4D)
    /// Bit 7: the copy protection passed.  The loader sets it when it starts a
    /// world; it is $00 on the disk, and while bit 7 is clear the worlds' main
    /// loops skip the soldering pen (Docs/CopyProtection.md).
    let copyProtectionOK = Byte(0x9C4E)
    /// Every world's start-up clears it right before its main loop.
    let flag9C51 = Byte(0x9C51, guess: true)
    let linkIndex = Byte(0x9C52)
    let moveLinkedObjects = Routine(0x9C53)
    /// Object X to object Y's place moved by (FOLLOW_DX, FOLLOW_DY): as FOLLOW_LINK.
    let followAt = Routine(0x9C7C)
    let followLink = Routine(0x9C88)
    let gfxInit = Routine(0x9CA1)
    let drawSpriteColour = Routine(0x9CC3, code: 0x9CC3 ..< 0x9CD0, md5: "22349f547a0bf905106ac2cc674e28d6")
    let setTileColours = Routine(0x9CD0)
    let drawRoomTiles = Routine(0x9D03)
    let drawRoomObjects = Routine(0x9D18)
    let wallsRoom = Byte(0x9D55)
    let roomWallsPointer = Routine(0x9D56, code: 0x9D56 ..< 0x9D8F, md5: "9d3ef7e0594b390b30ce126c924e103c")
    let setSpritePointer = Routine(0x9D8F)
    let moveObject = Routine(0x9DB3, code: 0x9DB3 ..< 0x9DB9, md5: "35ff7427acc50026bbfe3c1f6fe90e4b")
    let moveObjectXY = Routine(0x9DB9, code: 0x9DB9 ..< 0x9E07, md5: "c1dffdc72b6ca617d34226be7a531859")
    let setObjectRoom = Routine(0x9E07, code: 0x9E07 ..< 0x9E7A, md5: "68312d734af0a24960e495ab4b786f4e")

    // Sound (Docs/Sound.md).
    let playNoise = Routine(0x9E7A, code: 0x9E7A ..< 0x9EBB, md5: "b0e616804d05b5e1b98281274cc89643")
    let playTone = Routine(0x9EBB, code: 0x9EBB ..< 0x9EEA, md5: "bbda16cff042b30ea7bc01f70f49e22e")
    /// The sound queue, 8 slots: length (blocks of 256 loop iterations),
    /// sweep, pitch (the period), flags (bit 7 noise, bit 6 a noise period
    /// that may sweep through 0) and the room it is heard in ($FF: everywhere).
    /// Slot 0 is where the worlds put a sound for QUEUE_SOUND.
    let soundLengths = Table(0x9EEA)
    let soundSweeps = Table(0x9EF2)
    let soundPitches = Table(0x9EFA)
    let soundFlags = Table(0x9F02)
    let soundRooms = Table(0x9F0A)
    /// The first slot queued; 8: none.
    let soundQueue = Byte(0x9F12)
    /// Queues slot 0's sound in front of the others (none once 8 are queued).
    let queueSound = Routine(0x9F13)
    /// Ctrl-S turns the sound off and on.
    let soundOn = Byte(0x9F3B)
    let playSounds = Routine(0x9F3C, code: 0x9F3C ..< 0x9FC1, md5: "957beec0803f140f7e974921ffdf05cd")
    /// VLINE's byte column, PLOT index (colour × 8 + shift) and end y.
    let verticalLineColumn = Byte(0x9FC1)
    let verticalLinePlot = Byte(0x9FC2)
    let verticalLineEnd = Byte(0x9FC3)
    let verticalLine = Routine(0x9FC4, code: 0x9FC4 ..< 0xA02B, md5: "292703a657ddd3e6b25d369dc52ccaa0")
    let clampY = Routine(0xA02B, code: 0xA02B ..< 0xA036, md5: "dc2c7515540d4ad21044f7bf0d804c68")
    let clampX = Routine(0xA036, code: 0xA036 ..< 0xA044, md5: "21f89628df255b8e5b0a8b5ccf6cd09e")
    /// HLINE's lowest x and end x (+1), first and last byte column, the end
    /// byte's mask and pixels, and the colour's patterns for even and odd columns.
    let lineLow = Byte(0xA044)
    let lineEnd = Byte(0xA045)
    let lineFirstColumn = Byte(0xA046)
    let lineLastColumn = Byte(0xA047)
    let lineMask = Byte(0xA048)
    let linePixels = Byte(0xA049)
    let linePatterns = Table(0xA04A)
    let horizontalLine = Routine(0xA04C, code: 0xA04C ..< 0xA12E, md5: "3029b3edd12ee25fd66b67fa3b23845f")
    /// Masks of the pixels a line keeps in its last and first byte, by (2x) mod 7.
    let lineEndMasks = Table(0xA12E)
    let lineStartMasks = Table(0xA135)
    /// Lines' patterns by colour for odd and even byte columns.
    let linePatternsOdd = Table(0xA13C)
    let linePatternsEven = Table(0xA144)
    let plotColour = Byte(0xA14C)
    let plot = Routine(0xA14D, code: 0xA14D ..< 0xA181, md5: "72dc13ce79ae1753c47dea3484392502")
    /// PLOT's masks by colour × 8 + (2x) mod 7: the pixels to set in the byte
    /// and the next one, and the pixels each keeps.
    let plotSet = Table(0xA181)
    let plotSetNext = Table(0xA1C1)
    let plotKeep = Table(0xA201)
    let plotKeepNext = Table(0xA241)
    let drawBox = Routine(0xA281, code: 0xA281 ..< 0xA2A1, md5: "4bcac80c58b19bf90deb6131a8136d06")
    let drawRoomTexts = Routine(0xA2A2)
    let drawText = Routine(0xA2EA)
    let textLineAddress = Routine(0xA3AB)
    let drawBigText = Routine(0xA3E1)
    let bigTextPatternEven = Table(0xA4B9)
    let bigTextPatternOdd = Table(0xA4C1)
    let bitReverseTable = Table(0xA4C9)
    /// Where HELD_OBJECT is from the player (saved with the game).
    let heldDX = Byte(0xA5C9)
    let heldDY = Byte(0xA5CA)
    /// GRABBED_OBJECT at the last press of a button.
    let grabbedAtPress = Byte(0xA5CB)
    /// A button down in each of the last ticks, the latest in bit 0.
    let grabButtonHistory = Byte(0xA5CC)
    /// The player's hand, every tick: a button pressed with something held
    /// drops it (as long as it stays down), with nothing held takes the
    /// object touched, if any; then the world's hook (JSR at $A66D) and
    /// HELD_OBJECT follows the player (FOLLOW_AT).  What follows that through
    /// OBJ_LINK comes along in MOVE_LINKED_OBJECTS.
    let grabAndCarry = Routine(0xA5CD)
    let engA6AD = Routine(0xA6AD)
    /// Z clear when TOUCH_FIRST and TOUCH_SECOND are in the same room with
    /// their boxes overlapping.
    let objectsTouch = Routine(0xA835, guess: true)

    // Input (Docs/Engine.md "Input").
    let mouseMoved = Byte(0xA909)
    let lastPaddleY = Byte(0xA90A)
    let lastPaddleX = Byte(0xA90B)
    let readInput = Routine(0xA90C, code: 0xA90C ..< 0xA934, md5: "778a00d2dda0dcb862303fbbb964f705")
    let keepOnScreen = Routine(0xA934, code: 0xA934 ..< 0xA979, md5: "3063e404b814dba1380f1a74ce43ef31")
    /// The screen's edges a move stops at: right and left, top and bottom.
    let screenEdgesX = Table(0xA979)
    let screenEdgesY = Table(0xA97B)
    let readDevice = Routine(0xA97D, code: 0xA97D ..< 0xA9D2, 0xA9D4 ..< 0xAA25, md5: "e1f8bd88d87b7ac4c928992bd9593c95")
    let readKey = Routine(0xAA25, code: 0xAA25 ..< 0xAA40, md5: "b67ae57dd6501309ef56da8d3a63b146")
    let keyAsStick = Routine(0xAA40, code: 0xAA40 ..< 0xAAC9, md5: "a37ea61769909783565b76f7c91f47ad")
    /// The paddle counts, doubled.
    let paddleX = Byte(0xAAC9)
    let paddleY = Byte(0xAACA)
    let readJoystick = Routine(0xAACB, code: 0xAACB ..< 0xAB54, md5: "3f19d0a2309a2b7e62fccf3e7d9238d5")
    let moveByKey = Routine(0xAB54, code: 0xAB54 ..< 0xAB71, md5: "6cef0982d6a25f8693ae42d818f5a76f")
    /// The move for each 16 joystick positions, by keyboard and by joystick.
    let keyMoveX = Table(0xAB71)
    let keyMoveY = Table(0xAB81)
    let withSign = Routine(0xAB91, code: 0xAB91 ..< 0xABA1, md5: "889b4ead7922abe0b9f29852c880a412")
    let moveByStick = Routine(0xABA1, code: 0xABA1 ..< 0xABBE, md5: "6e15eb5bc1986e67ec94be6227655a77")
    let stickMoveX = Table(0xABBE)
    let stickMoveY = Table(0xABCE)
    let readMouse = Routine(0xABDE, guess: true)
    let clearButtons = Routine(0xAC09, code: 0xAC09 ..< 0xAC12, md5: "35480cf07c7d6d4e594785ec39e6eeb2")
    let detectJoystick = Routine(0xAC24)

    // Object motion (Docs/Engine.md "Input").
    let limitX = Byte(0xACF6)
    let limitY = Byte(0xACF7)
    let limitMove = Routine(0xACF8, code: 0xACF8 ..< 0xAD3D, md5: "c5e4ef4cb0e97387b05d1767024c9d55")
    /// The move STOP_AT_WALLS tries, and the tile column the object is in.
    let tryDX = Byte(0xAD3D)
    let tryDY = Byte(0xAD3E)
    let tileColumn = Byte(0xAD3F)
    let stopAtWalls = Routine(0xAD40, code: 0xAD40 ..< 0xADD3, md5: "715ec6bf8ead734b9d0819a700a4b6a5")
    /// The sizes of the wanted and the tried move.
    let sizeDX = Byte(0xADD3)
    let sizeTryDX = Byte(0xADD4)
    let stopAtTileColumn = Routine(0xADD5, code: 0xADD5 ..< 0xAE20, md5: "128aca115f1dc3ba151cd3861b1ffdc0")
    let magnitude = Routine(0xAE20, code: 0xAE20 ..< 0xAE28, md5: "f833913f97409109d37af85f7a4921eb")
    let sizeDY = Byte(0xAE28)
    let sizeTryDY = Byte(0xAE29)
    let stopAtTileRow = Routine(0xAE2A, code: 0xAE2A ..< 0xAE65, md5: "d9096db12de54203ad6d9ede04e6054f")
    let testResult = Byte(0xAE65)
    let testCorner = Byte(0xAE66)
    /// TEST_MOVE's result bits: off the right edge, off the top.
    let offRightBit = Byte(0xAE67)
    let offTopBit = Byte(0xAE68)
    let testMove = Routine(0xAE69, code: 0xAE67 ..< 0xAEDF, md5: "6c93cc8846b298f532a2435d2ac9633c")
    /// The object box's corners.
    let cornerDX = Table(0xAEDF)
    let cornerDY = Table(0xAEE3)

    // Sprites.
    /// DRAW_SPRITE's row (+1), byte column, line and shift.
    let spriteRow = Byte(0xAEE7)
    let spriteColumn = Byte(0xAEE8)
    let spriteLine = Byte(0xAEE9)
    let spriteShift = Byte(0xAEEA)
    /// The world's drawing routine (its start-up code sets it).
    let drawVector = Word(0xAEEB)
    let flipPage = Routine(0xAEED)
    let drawIndirect = Routine(0xAF1C)
    let drawSprite = Routine(0xAF1F, code: 0xAF1F ..< 0xB2A3, md5: "0466b73b816032d0e46ea5d6e5411950")
    /// The 7 pre-shifted sprite routines, by (2x) mod 7.
    let shiftedSpriteRoutines = Table(0xAF4C)
    /// Their tables turning sprite bits into masks of covered pixels.
    let spriteMasks = Table(0xB2A3)
    let wallGroup = Byte(0xB3A8)
    /// SET_WALL's A: 0 clears the wall, anything else sets it.
    let wallValue = Byte(0xB3A9)
    /// SET_WALL ($B3AA): sets or clears (A) the wall at tile WALL_COLUMN,
    /// WALL_ROW (from the bottom) of the bitmap at POINTER; nothing outside
    /// the room.  The worlds' doors and the Lab's paintbrush; the room links
    /// never change, the walls do.
    let setWall = Routine(0xB3AA)
    let wallGroupOffsets = Table(0xB3F8)
    let wallBits = Table(0xB3FB)
    /// WALL_BITS inverted, for SET_WALL to clear one.
    let wallMasks = Table(0xB403)
    let wallAt = Routine(0xB40B, code: 0xB40B ..< 0xB44F, md5: "a85248b2a7df309026f79291064bb967")
    let tilePatterns = Table(0xB496)
    let loadTilePatterns = Routine(0xB4A2)
    let fillTile = Routine(0xB4DF)

    // MARK: the levels' engine piece at $B8E0

    let engB8E6 = Routine(levels: 0xB8E6)
    let engB8ED = Routine(levels: 0xB8ED)
    /// The tools, with nothing held: a key of TOOL_KEYS, or a new press of
    /// the button on a tool lying about (TOUCHED_TOOL), takes that tool (its
    /// own again puts it away): the player and the tool object swap sprite
    /// and colour (SWAP_WITH_PLAYER), so the player looks like the tool and
    /// the tool object keeps the player's look; the tip, object $FE, takes
    /// the tool's (TOOL_TIP_COLOURS, TOOL_TIP_SPRITES).
    let takeTool = Routine(levels: 0xBDE1)
    /// TOOL_OBJECTS' index of the tool asked for.
    let toolIndex = Byte(levels: 0x8E3F)
    /// TOOL_INDEX = 2 or 1 if the player touches the remote control or the
    /// pen (OBJECTS_TOUCH), else 0.
    let touchedTool = Routine(levels: 0xBE76)
    let putToolAway = Routine(levels: 0xBE97)
    /// Swaps the sprite and colour of the player (object 0) and object Y.
    let swapWithPlayer = Routine(levels: 0xBEA3)
    /// GRAB_STATE from the buttons; the kit's and the lab's own copies
    /// (their code unchecked, so the native runs in the levels only).
    let grabButton = Routine(levels: 0xBEBC, kit: 0xBEDB, lab: 0x185A,
                             code: [.levels(0xBEBC ..< 0xBED6, md5: "901b150e06b79c82488a264e17b0a4d8")])
    /// With the remote control in hand, a new press of the button (not on
    /// the remote's object) toggles the player's colour and REMOTE_SWITCH
    /// between 5 and 7.
    let remoteControl = Routine(levels: 0xBED6)
    /// The player's 8 walking frames.
    let playerSprites = Table(levels: 0xBF30)

    // MARK: the lab's engine piece at $B8E0

    /// PAINTBRUSH ($BEBB, the lab's main loop calls it every tick): holding
    /// the paintbrush (TOOL_MODE $E0) in the maze rooms $0D-$14 turns
    /// WALLS_ON off, and the grab button paints the tile under the player
    /// (SET_WALL): a new press toggles it, held it paints the same value.
    let paintbrush = Routine(lab: 0xBEBB)
    /// POINTER and WALL_COLUMN, WALL_ROW of the tile under the player (x+4, y+8).
    let paintbrushTile = Routine(lab: 0xBF01)
    /// A tile on the room's edge is painted in the linked room too and stays
    /// a wall where the edge has no exit.
    let paintbrushEdges = Routine(lab: 0xBF1A)
    /// The value painted (SET_WALL's A) and WALL_ROW kept while painting the edges.
    let paintValue = Byte(lab: 0x13B1)
    let paintRow = Byte(lab: 0x13B2)
    /// WALL_COLUMN of x A (X_BYTE_TABLE / 2), 0 off the screen.
    let columnOfX = Routine(lab: 0xBFBE)
    /// WALL_ROW of y A (A / 16).
    let rowOfY = Routine(lab: 0xBFD5)

    // MARK: language card bank 2 at $D000 (moved in v1.0)

    let robotsReset = Routine(levels: 0xD000, guess: true)
    let drawRobots = Routine(levels: 0xD2BC, kit: 0xD2AB, lab: 0xD2AB, code: [
        .levels(0xD2BC ..< 0xD72B, md5: "5447b8f3858ebea8813956241469839f"),
        .kit(0xD2AB ..< 0xD674, md5: "58cfaa0bf4b3df5a27c2aa5165d16520"),
        .lab(0xD2AB ..< 0xD674, md5: "249ae8aaef23046e12b763b3c8c68fc6")])
    let drawRobot2Scan = Routine(levels: 0xD2C8, kit: 0xD2B5, lab: 0xD2B5)
    let drawRobot1Sparks = Routine(levels: 0xD359, kit: 0xD347, lab: 0xD347)
    let sparkPosition = Routine(levels: 0xD3F5, kit: 0xD3EC, lab: 0xD3EC)
    let randomBelowA = Routine(levels: 0xD414, kit: 0xD40B, lab: 0xD40B)
    let random = Routine(levels: 0xD429, kit: 0xD420, lab: 0xD420)
    let randomStep = Routine(levels: 0xD434, kit: 0xD42B, lab: 0xD42B)
    let drawBlank = Routine(levels: 0xD442)
    let drawRobot0Rainbow = Routine(levels: 0xD44D, kit: 0xD439, lab: 0xD439)
    let drawRobot3Pulse = Routine(levels: 0xD4CC)
    let drawRobotParts = Routine(levels: 0xD573, kit: 0xD4BC, lab: 0xD4BC)
    let drawRainbow = Routine(levels: 0xD6AB, kit: 0xD5F4, lab: 0xD5F4)
    let drawRobotInterior = Routine(levels: 0xD72B, kit: 0xD674, lab: 0xD674, code: [
        .levels(.v1_1, 0xD72B ..< 0xD832, md5: "cea4338383bb52042f5d15c5c267cde1"),
        .levels(.v1_0, 0xD72B ..< 0xD834, md5: "85a132191621633fdbb838215623f744"),
        .kit(0xD674 ..< 0xD768, md5: "ad6199bae84669dd1309f417d8a6f25c"),
        .lab(0xD674 ..< 0xD768, md5: "eea7722c44735bfdf275fde18d3e9cb9")])
    let drawBattery = Routine(levels: 0xD783, kit: 0xD6B7, lab: 0xD6B7)
    let drawInteriorParts = Routine(levels: 0xD7D0, kit: 0xD705, lab: 0xD705, levelsV1_0: 0xD7D1)
    let robotsThrusters = Routine(levels: 0xD832, levelsV1_0: 0xD834, guess: true)
    let engDA44 = Routine(levels: 0xDA44, levelsV1_0: 0xDA46)
    let engDA90 = Routine(levels: 0xDA90, levelsV1_0: 0xDA93)
    /// The last call before the draw phase (`DrawPhase`).
    let playerInRobot = Routine(levels: 0xDD59, kit: 0xDC16, lab: 0xDBAF, kitV1_0: 0xDC11, labV1_0: 0xDBA7)
    let engDDD0 = Routine(levels: 0xDDD0)
    let robots4Update = Routine(levels: 0xDE10, levelsV1_0: 0xDE11, guess: true)
    let crystals = Routine(levels: 0xDE95, levelsV1_0: 0xDE96, guess: true)
    let crystals2 = Routine(levels: 0xDF81, levelsV1_0: 0xDF82, guess: true)
    let playerWalkSprite = Routine(levels: 0xDFA3, levelsV1_0: 0xDFA4, code: [
        .levels(.v1_1, 0xDFA3 ..< 0xDFFE, md5: "b44ec2e623245f6dbcd62bf38e665caa"),
        .levels(.v1_0, 0xDFA4 ..< 0xDFFF, md5: "4914207a999e6cbaf578c4a2dfc736cf")])

    // MARK: language card $E000-$FFFF

    /// The chips' pin directions, 8 per chip (0 unused, 1 in, 2 out).
    let chipPins = Table(0xF008)
    let gatesEval = Routine(levels: 0xF04B, guess: true)
    let wiresPropagate = Routine(levels: 0xF0CC)
    let sensors = Routine(levels: 0xF44D, guess: true)
    let chipsEval = Routine(levels: 0xF56B, guess: true)
    let engF5A9 = Routine(levels: 0xF5A9)
    /// The soldering pen, called each tick while the player holds it and the
    /// copy protection passed (Docs/CopyProtection.md).  SOLDER_TOUCH acts on
    /// what the pen touches while no wire is started; SOLDER_WIRE starts a
    /// wire at the first touch (with the solder sound) and makes it at the
    /// second.
    let solderTouch = Routine(levels: 0xF5C2, guess: true)
    let solderWire = Routine(levels: 0xF7BE, guess: true)
    let drawWires = Routine(levels: 0xFC62)
    let keepMove = Routine(levels: 0xFE18, code: [.levels(0xFE18 ..< 0xFE25, md5: "1544988aa9cbb3fa4337cfe931fb8fd9")])
    let engFE25 = Routine(levels: 0xFE25)
}

nonisolated extension GameSymbols {
    /// The address of a symbol that is at the same place in every world and version.
    static func address<S: Symbol>(_ s: KeyPath<GameSymbols, S>) -> Int {
        guard let a = map[keyPath: s].address.everywhere else { fatalError("\(s) differs between the engines") }
        return a
    }

    /// Every symbol with its .sym name, in declaration order.
    static let named = namedSymbols(of: map)

    /// The .sym name of a routine.
    static func name(of routine: KeyPath<GameSymbols, Routine>) -> String {
        let address = map[keyPath: routine].address
        return named.first { ($0.symbol as? Routine)?.address == address }?.name ?? "?"
    }

    /// The .sym name of the `kind` of symbol (a routine, a sprite...) at
    /// `address` in `variant`; with none (a version the loader doesn't know)
    /// only symbols at the same place everywhere count.
    static func name<S: Symbol>(_ kind: S.Type, at address: Int, in variant: Variant?) -> String? {
        named.first { n in
            n.symbol is S && (variant.map { n.symbol.address($0) } ?? n.symbol.address.everywhere) == address
        }?.name
    }
}
