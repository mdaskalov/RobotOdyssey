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
    let segments: [Segment]
    let code: [Segment]
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

    static let worlds: [WorldDefinition] = [
        WorldDefinition(id: "level1", name: "Level 1 – City Sewer", side: .a, kind: .level,
                        segments: [Segment(.a, 306, 0x6000, pages: 34, last: 0),
                                   Segment(.a, 253, 0x8200, pages: 12, last: 217),
                                   Segment(.a, 357, 0x8EF0, pages: 5, last: 2)],
                        code: [Segment(.a, 340, 0x0803, pages: 16, last: 223)]),
        WorldDefinition(id: "level2", name: "Level 2 – Subway", side: .a, kind: .level, base: "level1",
                        segments: [Segment(.a, 363, 0x6E40, pages: 19, last: 192),
                                   Segment(.a, 400, 0x8EF0, pages: 1, last: 63)],
                        code: [Segment(.a, 383, 0x0803, pages: 16, last: 103)]),
        WorldDefinition(id: "level3", name: "Level 3 – Town", side: .a, kind: .level, base: "level2",
                        segments: [Segment(.a, 402, 0x6E40, pages: 19, last: 192),
                                   Segment(.a, 441, 0x8EF0, pages: 5, last: 249)],
                        code: [Segment(.a, 422, 0x0803, pages: 18, last: 44)]),
        WorldDefinition(id: "level4", name: "Level 4 – Master Computer Center", side: .a, kind: .level, base: "level3",
                        segments: [Segment(.a, 447, 0x6E40, pages: 19, last: 192),
                                   Segment(.a, 484, 0x8EF0, pages: 5, last: 97)],
                        code: [Segment(.a, 467, 0x0803, pages: 16, last: 98)]),
        WorldDefinition(id: "level5", name: "Level 5 – Skyways", side: .a, kind: .level, base: "level4",
                        segments: [Segment(.a, 490, 0x6E40, pages: 19, last: 192),
                                   Segment(.a, 529, 0x8EF0, pages: 5, last: 217)],
                        code: [Segment(.a, 510, 0x0803, pages: 18, last: 42)]),
        WorldDefinition(id: "anatomy", name: "Robot Anatomy", side: .b, kind: .tutorial, wireTables: 0x14C0,
                        segments: [Segment(.b, 396, 0x6000, pages: 53, last: 0)],
                        code: [Segment(.b, 348, 0x14C0, pages: 11, last: 64),
                               Segment(.b, 449, 0x0803, pages: 4, last: 99),
                               Segment(.b, 454, 0x14C0, pages: 6, last: 121)]),
        WorldDefinition(id: "toolkit", name: "Toolkit", side: .b, kind: .tutorial, wireTables: 0x14C0,
                        segments: [Segment(.b, 461, 0x6000, pages: 53, last: 0)],
                        code: [Segment(.b, 348, 0x14C0, pages: 11, last: 64),
                               Segment(.b, 514, 0x0803, pages: 9, last: 176),
                               Segment(.b, 524, 0x14C0, pages: 6, last: 20)]),
        WorldDefinition(id: "labtutorial", name: "Innovation Lab Tutorial", side: .b, kind: .tutorial, wireTables: 0x0B00,
                        segments: [Segment(.b, 284, 0x6000, pages: 53, last: 0)],
                        code: [Segment(.b, 337, 0x0803, pages: 2, last: 251),
                               Segment(.b, 168, 0x0B00, pages: 20, last: 225),
                               Segment(.b, 340, 0x0B00, pages: 8, last: 0)]),
        WorldDefinition(id: "lab", name: "Innovation Lab", side: .b, kind: .lab, wireTables: 0x0B00,
                        segments: [Segment(.b, 228, 0x6000, pages: 53, last: 0)],
                        code: [Segment(.b, 281, 0x0803, pages: 2, last: 248),
                               Segment(.b, 168, 0x0B00, pages: 20, last: 225)]),
    ]

    static func world(_ id: String) -> WorldDefinition? { worlds.first { $0.id == id } }

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
enum DiskRole {
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
