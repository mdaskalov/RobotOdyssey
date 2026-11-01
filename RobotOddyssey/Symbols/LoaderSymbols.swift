import Foundation

/// The loader by name: boot stage 2 (track 0, at $4F00-$5DFF) and the
/// loader and menu dispatch (track 1, at $4000-$4EFF), which the app does not
/// run (`WorldBuilder` loads the worlds the way it does).  During play this
/// area is hi-res page 2, so its names are a map of their own
/// (RobotOdysseyLoader.sym).  The same addresses in v1.0 and v1.1; the
/// versions differ in eight file lengths, so the file table tells the
/// version.  The loader's code is left unchecked: every cracked dump patches
/// it differently (Docs/DiskLayout.md).
final class LoaderSymbols: Sendable {
    static let map = LoaderSymbols()

    /// Track 1: the disk pages loaded to $4000-$4EFF.
    static let track1 = (page: 16, address: 0x4000, length: 0xF00)

    let loaderStart = Routine(0x4000)
    let loaderRestart = Routine(0x4003)
    let menuDispatch = Routine(0x4040)
    let loadLevel2 = Routine(0x40B9)
    let loadLevel3 = Routine(0x40C5)
    let loadLevel4 = Routine(0x40D1)
    let loadLevel5 = Routine(0x40DD)
    let loadEnding = Routine(0x40E9, guess: true)
    let saveGameWrite = Routine(0x4193)
    let restoreLoadCode = Routine(0x435E)
    let loadCodeL1 = Routine(0x437E)
    let loadCodeL2 = Routine(0x4386)
    let loadCodeL3 = Routine(0x438E)
    let loadCodeL4 = Routine(0x4396)
    let loadCodeL5 = Routine(0x439E)
    let loadCodeLab = Routine(0x43A6)
    let restoreGame = Routine(0x443A)
    let jumpAY = Routine(0x44B0)
    let startWorld = Routine(0x456C)
    let loadEngine = Routine(0x4582)
    let loadLevel1 = Routine(0x4595)
    let loadLab = Routine(0x45C4)
    let loadAnatomy = Routine(0x45E2)
    let loadToolkit = Routine(0x45F8)
    let loadLabTutorial = Routine(0x460E)
    /// Loads files by their entries in FILE_TABLE (`JSR LOAD_FILES` and inline pointers).
    let loadFiles = Routine(0x4A20)
    let checkDiskSide = Routine(0x4B80)
    let readSideID = Routine(0x4B9C)
    /// Empties the chips in A's mask (bit 7: chip 0).
    let clearChips = Routine(0x4D13)
    /// 6-byte entries up to $4EE9: track, sector, address, bytes in the last
    /// page, full pages (GameCatalog has them as segments).
    let fileTable = Table(0x4D5E)
    let boot2 = Routine(0x4F00)
    let rwtsIOB = Table(0x59E8)
    let rwts = Routine(0x5A00)
    let rwtsSkew = Table(0x5CB8)
    let boot2Entry = Routine(0x5D00)

    /// MD5 of the file table's entries ($4D5E-$4EE9) by version: the same on
    /// both sides and in every known dump of a version.
    static let fileTableEnd = 0x4EEA
    static let fileTableMD5: [Version: String] = [
        .v1_0: "7c6bd53ffcb6678f70924004aef26c27",
        .v1_1: "73210005c79882515ea055fa76a8faca",
    ]

    /// The version of a program disk side, by its loader's file table; nil if unknown.
    static func version(of disk: DiskImage) -> Version? {
        let track = disk.read(page: track1.page, length: track1.length)
        let start = map.fileTable.address.everywhere! - track1.address
        let md5 = DiskImage.md5(track[start ..< fileTableEnd - track1.address])
        return fileTableMD5.first { $0.value == md5 }?.key
    }
}

/// Level 1's own code ($0803-$18FF, $8EF0-$94FF) by name, for the debugger:
/// L1_ in RobotOdyssey.sym.  The same addresses in v1.0 and v1.1.  The other
/// worlds' code is laid out differently and has no names yet.
final class Level1Symbols: Sendable {
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
    let exitNextLevel = Routine(0x0A83)
    let exitMode5 = Routine(0x0A8E)
    let exitMenu = Routine(0x0A99)
    let exitMode4 = Routine(0x0AA1)
    let exitToLoader = Routine(0x0AAC)
    let exitObjects = Table(0x0B7B)
    let exitRooms = Table(0x0B81)
    let exitX = Table(0x0B87)
    let exitY = Table(0x0B8D)
    let exitScript = Routine(0x0B93)
    let tick0C06 = Routine(0x0C06)
    let tick0CA8 = Routine(0x0CA8)
    let tick0F93 = Routine(0x0F93)
    /// Room $2A's code: the way out of the sewer, with its falling tones (GameSounds.exitTones).
    let tick101A = Routine(0x101A)
    let welcomeRoom = Routine(0x10F8, guess: true)
    let tick1305 = Routine(0x1305)
    let tick1740 = Routine(0x1740)
    /// Rooms $03 and $1F (a guess).
    let tick187C = Routine(0x187C)
    /// The sound table, 12 sounds (GameSounds): flags, length, sweep, pitch.
    let soundTableFlags = Table(0x18B2)
    let soundTableLengths = Table(0x18BE)
    let soundTableSweeps = Table(0x18CA)
    let soundTablePitches = Table(0x18D6)
    let animateCreatures = Routine(0x8F69)
}
