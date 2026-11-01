import Foundation

/// A run of disk pages loaded to a memory address (from the track 1 loader table).
struct Segment {
    let side: DiskSide
    let page: Int
    let address: Int
    let length: Int

    init(_ side: DiskSide, _ page: Int, _ address: Int, pages: Int, last: Int) {
        self.side = side
        self.page = page
        self.address = address
        length = pages * 256 + last
    }
}

enum DiskSide: String {
    case a = "A", b = "B"
}

enum WorldKind {
    case level, tutorial, lab, savedGame
}

struct WorldDefinition {
    let id: String
    let name: String
    let side: DiskSide
    let kind: WorldKind
    /// For levels 2-5: the level whose final object table this level inherits.
    var base: String?
    /// Where the world's engine keeps the wire tables (see `World.wireTables`).
    var wireTables = World.levelWireTables
    /// The engine pieces loaded with the world (besides `GameCatalog.engineMain`).
    var engine = GameCatalog.engineLevels
    /// What the loader does to the chips after loading the world.
    var chips = ChipSetup()
    let segments: [Segment]
    let code: [Segment]
}

/// The loader's chip set-up after loading a world (LOAD_LEVEL1 $4595, LOAD_LAB
/// $45C4, LOAD_LAB_TUTORIAL $460E; Robot Anatomy and Toolkit have none).  Chip
/// n lives at $D000 + $400n (chips 0-3 in language card bank 1, 4-7 at
/// $E000-$EFFF) with its program from +8; CHIPS_EVAL ($F56B) runs each program
/// up to opcode 7, so an empty chip is `07 FF FF FF` (CLEAR_CHIPS $4D13).
struct ChipSetup {
    /// Chip programs loaded into bank 1.
    var bank1: [Segment] = []
    /// Bytes stored into the engine's chip table ($F008...).
    var table: [(address: Int, bytes: [UInt8])] = []
    /// Chips emptied; bit 7 is chip 0.
    var cleared: UInt8 = 0

    static let emptyChip: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0x07, 0xFF, 0xFF, 0xFF]

    /// Applies the set-up to a world's memory (bank 2 mapped) and its bank 1.
    func apply(to mem: inout [UInt8], bank1 bank: inout [UInt8], disk: (Segment) throws -> [UInt8]) rethrows {
        for s in bank1 {
            bank.replaceSubrange(s.address - 0xD000 ..< s.address - 0xD000 + s.length, with: try disk(s))
        }
        for (address, bytes) in table {
            mem.replaceSubrange(address ..< address + bytes.count, with: bytes)
        }
        for chip in 0 ..< 8 where cleared << chip & 0x80 != 0 {
            let a = 0xD000 + 0x400 * chip
            if a < 0xE000 {
                bank.replaceSubrange(a - 0xD000 ..< a - 0xD000 + 12, with: ChipSetup.emptyChip)
            } else {
                mem.replaceSubrange(a ..< a + 12, with: ChipSetup.emptyChip)
            }
        }
    }
}

/// Robot Odyssey I for the Apple II, versions 1.0 and 1.1 (two-sided program disk).
/// See Docs/DiskLayout.md.
enum GameCatalog {
    /// Engine part identical on both sides: font ($9500) and colour tables ($9B91).
    static let engineMain = Segment(.a, 129, 0x9500, pages: 35, last: 215)
    static let engineLevels = [Segment(.a, 247, 0x1A50, pages: 5, last: 164),
                               Segment(.a, 266, 0xB8E0, pages: 7, last: 32),
                               Segment(.a, 274, 0xD000, pages: 15, last: 254),
                               Segment(.a, 290, 0xF000, pages: 15, last: 244)]
    /// Engine pieces of Robot Anatomy and Toolkit (with 348 -> $14C0 in their code).
    static let engineKit = [Segment(.b, 360, 0xB900, pages: 6, last: 49),
                            Segment(.b, 367, 0xD000, pages: 15, last: 242),
                            Segment(.b, 383, 0xF000, pages: 12, last: 118)]
    /// Engine pieces of the Innovation Lab and its tutorial.
    static let engineLab = [Segment(.b, 189, 0xB8E0, pages: 6, last: 252),
                            Segment(.b, 196, 0xD000, pages: 15, last: 250),
                            Segment(.b, 212, 0xF000, pages: 15, last: 248)]

    /// Level 1 gets two chips (pages 167 -> $D000, 165 -> $D400; the Level 1 save
    /// state has exactly these, $D400 changed by play) and empties the others.
    /// Levels 2-5 load neither engine nor chips: Level 1's set-up carries over.
    static let levelChips = ChipSetup(
        bank1: [Segment(.a, 167, 0xD000, pages: 1, last: 170), Segment(.a, 165, 0xD400, pages: 1, last: 131)],
        table: [(0xF008, [0x01, 0x01, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x01, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02])],
        cleared: 0x3F)

    static let worlds: [WorldDefinition] = [
        WorldDefinition(id: "level1", name: "Level 1 – City Sewer", side: .a, kind: .level, chips: levelChips,
                        segments: [Segment(.a, 306, 0x6000, pages: 34, last: 0),
                                   Segment(.a, 253, 0x8200, pages: 12, last: 217),
                                   Segment(.a, 357, 0x8EF0, pages: 5, last: 2)],
                        code: [Segment(.a, 340, 0x0803, pages: 16, last: 223)]),
        WorldDefinition(id: "level2", name: "Level 2 – Subway", side: .a, kind: .level, base: "level1",
                        chips: levelChips,
                        segments: [Segment(.a, 363, 0x6E40, pages: 19, last: 192),
                                   Segment(.a, 400, 0x8EF0, pages: 1, last: 63)],
                        code: [Segment(.a, 383, 0x0803, pages: 16, last: 103)]),
        WorldDefinition(id: "level3", name: "Level 3 – Town", side: .a, kind: .level, base: "level2",
                        chips: levelChips,
                        segments: [Segment(.a, 402, 0x6E40, pages: 19, last: 192),
                                   Segment(.a, 441, 0x8EF0, pages: 5, last: 249)],
                        code: [Segment(.a, 422, 0x0803, pages: 18, last: 44)]),
        WorldDefinition(id: "level4", name: "Level 4 – Master Computer Center", side: .a, kind: .level, base: "level3",
                        chips: levelChips,
                        segments: [Segment(.a, 447, 0x6E40, pages: 19, last: 192),
                                   Segment(.a, 484, 0x8EF0, pages: 5, last: 97)],
                        code: [Segment(.a, 467, 0x0803, pages: 16, last: 98)]),
        WorldDefinition(id: "level5", name: "Level 5 – Skyways", side: .a, kind: .level, base: "level4",
                        chips: levelChips,
                        segments: [Segment(.a, 490, 0x6E40, pages: 19, last: 192),
                                   Segment(.a, 529, 0x8EF0, pages: 5, last: 217)],
                        code: [Segment(.a, 510, 0x0803, pages: 18, last: 42)]),
        WorldDefinition(id: "anatomy", name: "Robot Anatomy", side: .b, kind: .tutorial, wireTables: 0x14C0,
                        engine: engineKit,
                        segments: [Segment(.b, 396, 0x6000, pages: 53, last: 0)],
                        code: [Segment(.b, 348, 0x14C0, pages: 11, last: 64),
                               Segment(.b, 449, 0x0803, pages: 4, last: 99),
                               Segment(.b, 454, 0x14C0, pages: 6, last: 121)]),
        WorldDefinition(id: "toolkit", name: "Toolkit", side: .b, kind: .tutorial, wireTables: 0x14C0,
                        engine: engineKit,
                        segments: [Segment(.b, 461, 0x6000, pages: 53, last: 0)],
                        code: [Segment(.b, 348, 0x14C0, pages: 11, last: 64),
                               Segment(.b, 514, 0x0803, pages: 9, last: 176),
                               Segment(.b, 524, 0x14C0, pages: 6, last: 20)]),
        WorldDefinition(id: "labtutorial", name: "Innovation Lab Tutorial", side: .b, kind: .tutorial, wireTables: 0x0B00,
                        engine: engineLab,
                        // Chips 0 and 2 (the loader patches 165's address to $D800).
                        chips: ChipSetup(bank1: [Segment(.b, 165, 0xD800, pages: 1, last: 131),
                                                 Segment(.b, 167, 0xD000, pages: 0, last: 19)],
                                         table: [(0xF008, [0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
                                                 (0xF018, [0x02, 0x01, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02])],
                                         cleared: 0x5F),
                        segments: [Segment(.b, 284, 0x6000, pages: 53, last: 0)],
                        code: [Segment(.b, 337, 0x0803, pages: 2, last: 251),
                               Segment(.b, 168, 0x0B00, pages: 20, last: 225),
                               Segment(.b, 340, 0x0B00, pages: 8, last: 0)]),
        WorldDefinition(id: "lab", name: "Innovation Lab", side: .b, kind: .lab, wireTables: 0x0B00,
                        engine: engineLab,
                        chips: ChipSetup(cleared: 0xFF),
                        segments: [Segment(.b, 228, 0x6000, pages: 53, last: 0)],
                        code: [Segment(.b, 281, 0x0803, pages: 2, last: 248),
                               Segment(.b, 168, 0x0B00, pages: 20, last: 225)]),
    ]

    static func world(_ id: String) -> WorldDefinition? { worlds.first { $0.id == id } }

    /// File lengths of v1.0's loader table where they differ from v1.1's (the
    /// lengths above), by side and first page.  The level engine's last byte
    /// ($DFFE) is code in v1.0.
    static let lengthsV10: [DiskSide: [Int: Int]] = [
        .a: [274: 15 * 256 + 255,       // level engine $D000
             383: 16 * 256 + 26,        // Level 2 code
             400: 1 * 256 + 62,         // Level 2 $8EF0
             422: 18 * 256 + 30,        // Level 3 code
             441: 5 * 256 + 248,        // Level 3 $8EF0
             467: 16 * 256 + 95],       // Level 4 code
        .b: [367: 15 * 256 + 237,       // Robot Anatomy/Toolkit engine $D000
             196: 15 * 256 + 242],      // lab engine $D000
    ]

    /// Version fingerprints: MD5 of game code that the various cracked dumps
    /// leave untouched (side A pages 383-399 = Level 2 code, side B pages
    /// 196-211 = lab engine).  See the README next to the disk images.
    static let fingerprints: [(side: DiskSide, pages: Range<Int>, md5: String, version: String)] = [
        (.a, 383 ..< 400, "746986a031c024ecfe2dc5d4e7a8babe", "1.0"),
        (.a, 383 ..< 400, "2ccd4a7f20f79a58293bd5543566e024", "1.1"),
        (.b, 196 ..< 212, "3ddfbca61cfecb97a18af2d8221122d4", "1.0"),
        (.b, 196 ..< 212, "01ccdab608976ab81aedc559afa4f11c", "1.1"),
    ]
}

/// What a disk image is, determined from its contents.
enum DiskRole: Equatable {
    case programSide(DiskSide, version: String)
    case storage
    case unknown
}

extension DiskImage {
    /// A world loaded at $6000 has its text pointer table at +$1B80/+$1C00 starting with $7C80.
    func hasWorld(atPage page: Int) -> Bool {
        let p = read(page: page + 0x1B, length: 0x200)
        return p[0x80] == 0x80 && p[0x100] == 0x7C
    }

    var role: DiskRole {
        let side: DiskSide? = hasWorld(atPage: 306) ? .a : (hasWorld(atPage: 228) && hasWorld(atPage: 396) ? .b : nil)
        if let side {
            let version = GameCatalog.fingerprints.first { f in
                f.side == side && DiskImage.md5(read(page: f.pages.lowerBound, length: f.pages.count * 256)) == f.md5
            }?.version
            return .programSide(side, version: version ?? "1.x")
        }
        // Storage diskettes boot with a "please insert the program disk" sector.
        if data.prefix(6) == [0x01, 0xA6, 0x2B, 0xBD, 0x88, 0xC0] { return .storage }
        return .unknown
    }
}
