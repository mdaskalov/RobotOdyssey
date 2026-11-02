import Foundation

/// The loader by name: boot stage 2 (track 0, at $4F00-$5DFF) and the
/// loader and menu dispatch (track 1, at $4000-$4EFF).  The app runs them as
/// 6502 code once a world hands back to the loader (`Loader`, with a native
/// boot, RWTS and copy checks); the worlds the app starts itself it loads
/// the way the loader does (`WorldBuilder`).  During play this area is
/// hi-res page 2, so its names are a map of their own
/// (RobotOdysseyLoader.sym).  The same addresses in v1.0 and v1.1; the
/// versions differ in eight file lengths, so the file table tells the
/// version.  The loader's code is left unchecked: every cracked dump patches
/// it differently (Docs/DiskLayout.md).
nonisolated final class LoaderSymbols: Sendable {
    static let map = LoaderSymbols()

    /// Track 1: the disk pages loaded to $4000-$4EFF.
    static let track1 = (page: 16, address: 0x4000, length: 0xF00)

    /// The disk the loader asks for (`DiskDrive.Disk`): 0 side A, 1 side B,
    /// 2 a storage disk; also the side the menu was loaded from.
    let wantedSide = Byte(0x0E)
    /// The letter chosen in a directory, from 0 (A).
    let chosenSlot = Byte(0x0F)
    // The copy protection (Docs/CopyProtection.md): bit 7 set when the check passed.
    let menuCheckResult = Byte(0x02CE)
    let bootCheckResult = Byte(0x03FE)
    /// 1 for each entry of the directory shown that is used.
    let slotsUsed = Table(0x03E0)
    /// The menu program's bytecode interpreter: `JSR MENU_BYTECODE` and inline
    /// bytecode (Docs/DiskLayout.md, *Menu bytecode*); Robotropolis' intro is
    /// bytecode too.
    let menuBytecode = Routine(0x0803)

    let loaderStart = Routine(0x4000)
    /// The menu's choice in A (MENU_CHOICE).
    let loaderRestart = Routine(0x4003)
    let menuDispatch = Routine(0x4040)
    /// Request 1: loads the menu from the side in the drive and starts it
    /// without the title ($6003; request 0 with it, $6000).
    let toMenu = Routine(0x4049)
    /// The request handlers by MENU_MODE, minus one (RTS).
    let requestLow = Table(0x408B)
    let requestHigh = Table(0x4092)
    /// Request 2: checks the side, loads level NEXT_LEVEL (LOAD_LEVEL2...)
    /// and starts it with the objects as they are (START_WORLD).
    let nextLevelRequest = Routine(0x4099)
    let nextLevelLow = Table(0x40AE)
    let nextLevelHigh = Table(0x40B3)
    let loadLevel2 = Routine(0x40B9)
    let loadLevel3 = Routine(0x40C5)
    let loadLevel4 = Routine(0x40D1)
    let loadLevel5 = Routine(0x40DD)
    let loadEnding = Routine(0x40E9, guess: true)
    /// Request 4: asks for the storage disk, shows its games, asks for a
    /// letter and a name, then SAVE_GAME_WRITE.
    let saveGame = Routine(0x410B)
    /// The header ($5E00: chip table, four engine variables, WORLD_INDEX),
    /// then the directory, header, $D000-$EFFF (bank 1), the world and
    /// $0B00-$1FFF to the slot.
    let saveGameWrite = Routine(0x4166)
    /// Request 6: saves chip NEXT_LEVEL on a storage disk, as SAVE_GAME a game.
    let saveChip = Routine(0x41AD)
    /// Request 5: asks for a disk with saved chips (side 2's library or a
    /// storage disk), loads the chip chosen into chip NEXT_LEVEL.
    let loadChip = Routine(0x427F)
    /// Back to the world after saving or loading a chip: shifts the boot
    /// check's result into COPY_PROTECTION_OK ($9C4E), asks for the world's
    /// side, then RESTORE_LOAD_CODE.
    let returnToWorld = Routine(0x434D)
    /// Reloads the code of world WORLD_INDEX (LOAD_CODE_L1...) and starts it.
    let restoreLoadCode = Routine(0x435E)
    let loadCodeL1 = Routine(0x437E)
    let loadCodeL2 = Routine(0x4386)
    let loadCodeL3 = Routine(0x438E)
    let loadCodeL4 = Routine(0x4396)
    let loadCodeL5 = Routine(0x439E)
    let loadCodeLab = Routine(0x43A6)
    /// LOADER_RESTART: WORLD_INDEX from the menu's choice (0 Robotropolis,
    /// else choice + 4); for Robotropolis asks Return (go) or O (a saved
    /// game), the others start at once (START_CHOSEN_WORLD).
    let menuChoice = Routine(0x43AE)
    /// O: asks for the storage disk, then RESTORE_GAME.
    let restorePrompt = Routine(0x4435)
    /// Shows the games, asks for a letter, loads the header and, if it is a
    /// game of the world chosen, the game: $0B00-$1FFF, the world, $D000-$EFFF;
    /// then the engine from the program disk and the header's values back.
    let restoreGame = Routine(0x443A)
    let jumpAY = Routine(0x44B0)
    /// COPY_PROTECTION_OK = BOOT_CHECK_RESULT AND MENU_CHECK_RESULT, restoring
    /// a game and starting a world.
    let copyFlagRestore = Routine(0x452D)
    /// Checks the side, loads world WORLD_INDEX (the levels after the menu's
    /// story), COPY_FLAG_START, START_WORLD.
    let startChosenWorld = Routine(0x4539)
    /// For Robotropolis: `JSR $6000`, the intro (loaded with the menu's
    /// interpreter, its pictures at $6300: bytecode with tunes, ended by a key
    /// press).  The app steps over it (`Loader`).
    let playIntro = Routine(0x4550)
    let copyFlagStart = Routine(0x4563)
    /// Language card bank 2, the keyboard strobe cleared, JMP WORLD_START.
    let startWorld = Routine(0x456C)
    /// START_CHOSEN_WORLD's loaders by WORLD_INDEX.
    let worldLoadLow = Table(0x4574)
    let worldLoadHigh = Table(0x4579)
    let loadEngine = Routine(0x4582)
    let loadLevel1 = Routine(0x4595)
    let loadLab = Routine(0x45C4)
    let loadAnatomy = Routine(0x45E2)
    let loadToolkit = Routine(0x45F8)
    let loadLabTutorial = Routine(0x460E)
    /// The chip tables LOAD_LEVEL1 and LOAD_LAB_TUTORIAL copy to $F008/$F018
    /// (GameCatalog's ChipSetup).
    let level1ChipTable = Table(0x4654)
    let labTutorialChipTable = Table(0x465C)
    /// Copies the block that the 6 inline bytes give (source, destination,
    /// bytes in the last page, pages): COPY_MEMORY.
    let copyInline = Routine(0x466C)
    /// Copies 1 page and $2B bytes from ($02) to A:Y.
    let copyChipName = Routine(0x4688)
    let copyMemory = Routine(0x4694)
    /// The next inline byte after the JSR (pointer $00/$01).
    let nextInline = Routine(0x46B8)
    /// Points the file entries of a saved game ($4DA4-$4DB7) at slot CHOSEN_SLOT.
    let gameSlotFiles = Routine(0x46C3)
    /// The same for a chip slot ($4D6A-$4D71).
    let chipSlotFiles = Routine(0x4704)
    /// A:X, Y: where chip NEXT_LEVEL's program is in the language card.
    let chipAddress = Routine(0x4732)
    /// Waits for a key; carry set for Esc.
    let getKey = Routine(0x473F)
    /// Waits for Return (carry clear) or Esc (set).
    let waitReturn = Routine(0x4752)
    /// Asks for a letter: A-D (games, $475D) or the chips' ($4761) into
    /// CHOSEN_SLOT; Esc: carry set.
    let chooseGameLetter = Routine(0x475D)
    let chooseChipLetter = Routine(0x4761)
    /// Reads a name of up to 18 letters into CHOSEN_SLOT's directory entry,
    /// with a blinking cursor (CURSOR); Esc: carry set.
    let inputName = Routine(0x4784)
    /// Clears hi-res page 1 and shows graphics, full screen, hi-res (not the page).
    let clearScreen = Routine(0x4824)
    /// CLEAR_SCREEN, then PRINT_AT.
    let clearPrint = Routine(0x4845)
    /// Prints the inline text (last letter with bit 7 set) at row A, column Y
    /// ($4850: column Y; $4852: where the last ended) with CHAR_OUT.
    let printAt = Routine(0x484E)
    let printInline = Routine(0x4852)
    let cursor = Routine(0x4872)
    /// "and press RETURN", two rows down.
    let pressReturn = Routine(0x4887)
    /// "game" or "lab" by WORLD_INDEX.
    let gameOrLab = Routine(0x48A5)
    /// "Insert Robot Odyssey " at row A, column Y.
    let insertRobotOdyssey = Routine(0x48E6)
    /// The game directory (4 entries) and the chip directories (side 2's
    /// library: 14, a storage disk: 5), with a letter before each name.
    let showGames = Routine(0x4924)
    let showChips = Routine(0x4939)
    /// If CHOSEN_SLOT is used, asks whether to replace it (Y/N).
    let replaceOld = Routine(0x49D9)
    /// A = SLOTS_USED of CHOSEN_SLOT.
    let slotUsed = Routine(0x4A1A)
    /// Loads files by their entries in FILE_TABLE (`JSR LOAD_FILES` and
    /// inline: count, command (1 read, 2 write, 4 format), pointers), sector
    /// by sector with RWTS.
    let loadFiles = Routine(0x4A20)
    /// After an RWTS error: format, write-protect or disk error, and Return to try again.
    let diskError = Routine(0x4AD2)
    /// WANTED_SIDE for WORLD_INDEX: 0 for the levels, 1 for the others.
    let sideOfWorld = Routine(0x4B72)
    /// WANTED_SIDE for the world, then AWAIT_SIDE.
    let checkDiskSide = Routine(0x4B80)
    /// Reads the side in the drive (READ_SIDE_ID) until it is WANTED_SIDE,
    /// asking to insert it and waiting for Return each time; Esc gives up
    /// (carry set).  Where the app's drive takes the disk asked for.
    let awaitSide = Routine(0x4B85)
    /// Track 0 sector 0 to $5F00: A = the side number ($5FFB), Z set when
    /// $5FFC is its EOR $A5; carry set on a disk error.
    let readSideID = Routine(0x4B9C)
    let sideIDFile = Table(0x4BAF)
    /// Asks for the storage disk ($4BB5) or side A ($4BB7), waits for
    /// Return, then AWAIT_SIDE.
    let askStorage = Routine(0x4BB5)
    let askSide = Routine(0x4BB7)
    /// "and press RETURN", then as ASK_SIDE.
    let confirmSide = Routine(0x4BBA)
    /// Asks for the storage disk, or a blank one and C for a new storage disk (NEW_STORAGE_DISK).
    let askStorageOrNew = Routine(0x4BC4)
    /// Clears the screen and asks to insert disk A (WANTED_SIDE): side 1,
    /// side 2, the STORAGE disk.
    let showInsertDisk = Routine(0x4BD0)
    /// "OR to Create a New STORAGE disk..." and waits for Return, Esc or C.
    let orNewStorage = Routine(0x4C0F)
    /// A warning, then formats the disk in the drive (LOAD_FILES with no
    /// files, command 4) and writes NEW_STORAGE_FILES.
    let newStorageDisk = Routine(0x4C79)
    /// The new storage disk's boot sector (STORAGE_BOOT to track 0 sector 0)
    /// and its game and chip directories (2 pages of spaces from $5E00 to track 2).
    let newStorageFiles = Table(0x4D07)
    /// Empties the chips in A's mask (bit 7: chip 0).
    let clearChips = Routine(0x4D13)
    let emptyChip = Table(0x4D44)
    /// Offset of each entry in a directory page: 18 bytes each.
    let directoryOffsets = Table(0x4D50)
    /// 6-byte entries up to $4EE9: track, sector, address, bytes in the last
    /// page, full pages (GameCatalog has them as segments).
    let fileTable = Table(0x4D5E)
    /// Track and sector of each game slot's first page (its bank 1, $D000).
    let gameSlotTracks = Table(0x4DBC)
    let gameSlotSectors = Table(0x4DC0)
    let boot2 = Routine(0x4F00)
    /// Sets up CHAR_OUT.
    let charInit = Routine(0x4F03)
    /// Prints character A (Apple code) on hi-res page 1 at CH/CV ($24/$25)
    /// in the window ($20-$23); $87 beeps, $88 back, $8D new line...
    let charOut = Routine(0x4F06)
    /// Written to a new storage disk's track 0 sector 0: a boot sector that
    /// asks for the program disk; side number 2 at $54FB (`DiskDrive`).
    let storageBoot = Table(0x5400)
    let rwtsIOB = Table(0x59E8)
    let rwts = Routine(0x5A00)
    let rwtsSkew = Table(0x5CB8)
    let boot2Entry = Routine(0x5D00)
    /// The check at boot, inline in boot stage 2; the menu runs a copy
    /// (`JSR MENU_COPY_CHECK`, the result in the carry), part of the menu
    /// program at $6000.  Each compares 8 nibbles with its signature, last byte
    /// first.
    let bootCopyCheck = Routine(0x5D58)
    /// Motor off, the check's carry into BOOT_CHECK_RESULT, JMP LOADER_START.
    let bootCopyDone = Routine(0x5DD3)
    let bootCopySignature = Table(0x5DDC)
    let bootDelay = Routine(0x5DE4)
    /// The menu program at $6000 (and $0803): the title, then the menu
    /// (MENU_ITEMS); $6003 the menu without the title.  Both run the copy check.
    let menuTitle = Routine(0x6000)
    let menuWithoutTitle = Routine(0x6003)
    /// The menu's choice, 0-4 (Robotropolis, Innovation Lab, Robot Anatomy,
    /// Toolkit, Chip Design); the side the menu was loaded from sets it.
    let menuSelection = Byte(0x6006)
    let menuItems = Routine(0x604E)
    /// Highlights MENU_SELECTION and waits for input: space or → the next,
    /// ← the one before, Return LOADER_RESTART with it.
    let menuLoop = Routine(0x606B)
    /// Waits for the keyboard or the joystick (A: 1 back, 2 next, 3 Return).
    let menuInput = Routine(0x60DB)
    /// One look at the joystick and the keyboard, stirring RANDOM ($4E/$4F).
    /// Ctrl-A, Ctrl-L, T set WALLS_KEY to Ctrl-E; Esc: MENU_ESCAPE.
    let menuReadDevices = Routine(0x619B)
    /// A tune, then `JMP (RESET_VECTOR)`: the Apple boots again and the
    /// loader, whose request doesn't check out, starts with the title.
    let menuEscape = Routine(0x6224)
    let menuCopyCheck = Routine(0x6255)
    let menuCopySignature = Table(0x62F0)
    /// The disk controller's boot ROM (slot 6), where RESET_VECTOR leads:
    /// boots the disk in the drive (`Loader.boot`).
    let slot6Boot = Routine(0xC600)

    /// MD5 of the file table's entries ($4D5E-$4EE9) by version: the same on
    /// both sides and in every known dump of a version.
    static let fileTableEnd = 0x4EEA
    static let fileTableMD5: [Version: String] = [
        .v1_0: "7c6bd53ffcb6678f70924004aef26c27",
        .v1_1: "73210005c79882515ea055fa76a8faca",
    ]

    /// The address of a loader symbol (the same in every version).
    static func address<S: Symbol>(_ s: KeyPath<LoaderSymbols, S>) -> Int {
        map[keyPath: s].address.everywhere!
    }

    /// The version of a program disk side, by its loader's file table; nil if unknown.
    static func version(of disk: DiskImage) -> Version? {
        let track = disk.read(page: track1.page, length: track1.length)
        let start = address(\.fileTable) - track1.address
        let md5 = DiskImage.md5(track[start ..< fileTableEnd - track1.address])
        return fileTableMD5.first { $0.value == md5 }?.key
    }
}

/// Level 1's own code ($0803-$18FF, $8EF0-$94FF) by name, for the debugger:
/// L1_ in RobotOdyssey.sym.  The same addresses in v1.0 and v1.1.  The other
/// worlds' code is laid out differently and has no names yet.
nonisolated final class Level1Symbols: Sendable {
    static let map = Level1Symbols()

    let initialise = Routine(0x0816)
    /// One iteration per tick.
    let mainLoop = Routine(0x0841)
    let mainLoopEnd = Routine(0x091C)
    let heldChanged = Routine(0x0920, guess: true)
    /// Queues sound X of the sound table for room A (WORLD_SOUND jumps here).
    let queueTableSound = Routine(0x0944)
    let keyCommands = Routine(0x0963)
    let showTextRoom = Routine(0x0A07)
    let waitKey = Routine(0x0A77)
    /// The requests to the loader (MENU_MODE): 2 the next level (Y), 5 load
    /// chip Y, 1 the menu, 4 save the game; then EXIT_TO_LOADER.
    let exitNextLevel = Routine(0x0A83)
    let exitLoadChip = Routine(0x0A8E)
    let exitMenu = Routine(0x0A99)
    let exitSaveGame = Routine(0x0AA1)
    /// MENU_MODE_CHECK, WORLD_INDEX 0, JMP (RESET_VECTOR).
    let exitToLoader = Routine(0x0AAC)
    /// Out of the sewer (room $2A's code jumps here): the loose objects
    /// outside the robots go to room $3F, the black crystal ($04) too, also
    /// from a robot's grabber; then EXIT_SCRIPT.
    let leaveSewer = Routine(0x0AC9)
    let exitObjects = Table(0x0B7B)
    let exitRooms = Table(0x0B81)
    let exitX = Table(0x0B87)
    let exitY = Table(0x0B8D)
    let exitScript = Routine(0x0B93)
    let tick0C06 = Routine(0x0C06)
    /// The Ampire Bot's move, by AMPIRE_STATE: 0 waits in room $10 for the
    /// player or a target, 1 comes down, 2 patrols rooms $10 $0F $21 $15 $12
    /// $11, 3 goes for its target (into the target's room at once), 4 drains
    /// it for 20 ticks (then 2 and a rest), 5 foiled by the black crystal:
    /// stands still for good (Engine.md, Level 1: the Ampire Bot).
    let ampireBot = Routine(0x0CA8)
    /// The first of AMPIRE_TARGETS in its room it can drain (A = the object),
    /// else A = 0.
    let findAmpireTarget = Routine(0x0F50)
    /// Draws the Ampire Bot in the current room, with a zap to its target
    /// while it drains.
    let drawAmpireBot = Routine(0x0F93)
    /// Counts down AMPIRE_REST_TICKS, then AMPIRE_REST.
    let countAmpireRest = Routine(0x1007)
    /// Room $2A's code: the way out of the sewer, with its falling tones (GameSounds.exitTones).
    let tick101A = Routine(0x101A)
    /// Each tick until SHUFFLED: while the player is in room $28 or $02 it
    /// counts SHUFFLE_TICKS3/6 on and draws SHUFFLE_PAIR and SHUFFLE_CRYSTAL
    /// (RANDOM_BELOW_A); the first tick elsewhere it places the key $FA in a
    /// robot's interior, $F6/$03 in rooms $22/$23, chip $E7 and the black
    /// crystal $04 in the maze, and sets SHUFFLED (Engine.md, Level 1).
    let shuffleObjects = Routine(0x10F8)
    /// x = A for object Y, then PLACE_OBJECT.
    let placeObjectAtX = Routine(0x11AC)
    /// Object Y into room X (SET_OBJECT_ROOM).
    let placeObject = Routine(0x11AF)
    /// The key's rooms, by SHUFFLE_TICKS3: $09 $0A $0B (the interiors of
    /// robots $F0 $F2 $F4).
    let shuffleKeyRooms = Table(0x11B9)
    /// The maze rooms of chip $E7 and the black crystal: $08 $0C $07 $06 $17 $16.
    let shuffleMazeRooms = Table(0x11BC)
    let shuffleChipX = Table(0x11C2)
    let shuffleChipY = Table(0x11C8)
    let shuffleCrystalX = Table(0x11CE)
    let shuffleCrystalY = Table(0x11D4)
    /// Where SHUFFLE_PAIR's pair starts in SHUFFLE_PAIRS: 0 or 2.
    let shufflePairStart = Table(0x11DA)
    /// $F6 $03 $03 $F6: the first goes to room $22, the second to room $23.
    let shufflePairs = Table(0x11DC)
    /// The Ampire Bot's 4 frames: sprite pointers, low and high bytes.
    let ampireFramesLow = Table(0x1212)
    let ampireFramesHigh = Table(0x1216)
    /// What it drains, tried from the last: $F6 (the energy crystal, while
    /// not white), robots $F0 $F2 $F4 (while their battery isn't empty), $04
    /// (the black crystal, while robot $F4's isn't: it shares $F4's branch).
    let ampireTargets = Table(0x121A)
    let tick1305 = Routine(0x1305)
    let tick1740 = Routine(0x1740)
    /// Rooms $03 and $1F (a guess).
    let tick187C = Routine(0x187C)
    /// The sound table, 12 sounds (GameSounds): flags, length, sweep, pitch.
    let soundTableFlags = Table(0x18B2)
    let soundTableLengths = Table(0x18BE)
    let soundTableSweeps = Table(0x18CA)
    let soundTablePitches = Table(0x18D6)
    /// 0 on the disk; 1 once SHUFFLE_OBJECTS has placed the objects (kept in
    /// a saved game, so a restored one isn't shuffled again).
    let shuffled = Byte(0x8F46)
    /// Ticks in the start rooms modulo 3 (the key's room) and modulo 6 (chip
    /// $E7's spot).
    let shuffleTicks3 = Byte(0x8F47)
    let shuffleTicks6 = Byte(0x8F48)
    /// RANDOM_BELOW_A 2: $F6/$03 in rooms $22/$23 (0) or the other way round.
    let shufflePair = Byte(0x8F49)
    /// RANDOM_BELOW_A 6: the black crystal's spot.
    let shuffleCrystal = Byte(0x8F4A)
    /// The Ampire Bot (AMPIRE_BOT): ticks it has drained its target (20 drain it).
    let ampireDrain = Byte(0x8F4B)
    /// Animation frame, 3 down to 0.
    let ampireFrame = Byte(0x8F4C)
    /// 6 blue; 1 green once the black crystal foiled it.
    let ampireColour = Byte(0x8F4D)
    /// The colour drawn last: orange (5) every other tick while it rests.
    let ampireColourDrawn = Byte(0x8F4E)
    let ampireX = Byte(0x8F4F)
    let ampireY = Byte(0x8F50)
    /// After a drain 2, counted down once AMPIRE_REST_TICKS ($C8) are; while
    /// not 0 it takes no target in its patrol.
    let ampireRest = Byte(0x8F51)
    let ampireRestTicks = Byte(0x8F52)
    /// 0-5, see AMPIRE_BOT.
    let ampireState = Byte(0x8F53)
    let ampireRoom = Byte(0x8F54)
    let ampireTarget = Byte(0x8F55)
    let ampireTargetX = Byte(0x8F56)
    let ampireTargetY = Byte(0x8F57)
    let animateCreatures = Routine(0x8F69)
}
