import Foundation

/// One of the 256 entries of the object table ($6000-$69FF, one array per field).
struct GameObject: Identifiable, Hashable {
    let id: Int
    let next, sprite, color, room, x, y, link, dx, dy, flags: Int
}

/// One of the 64 rooms ($6E00-$6FFF, one 64-byte array per field, walls at $7000).
struct Room: Identifiable {
    enum Direction: CaseIterable { case up, down, left, right }

    let id: Int
    let firstObject: Int
    let floorColor: Int
    let wallColor: Int
    let up, down, left, right: Int
    /// 12 rows x 20 columns, row 0 at the top of the screen.
    let walls: [[Bool]]

    func link(_ d: Direction) -> Int {
        switch d {
        case .up: up
        case .down: down
        case .left: left
        case .right: right
        }
    }
}

/// One of the 128 text entries ($7880-$7C7F, strings from $7C80).
struct RoomText: Identifiable {
    let id: Int
    let room, x, y, style, color: Int
    /// Raw Apple characters (high bit set, $8D = new line).
    let bytes: [UInt8]

    var string: String {
        String(bytes.map { $0 & 0x7F == 0x0D ? "\n" : Character(UnicodeScalar($0 & 0x7F)) })
    }
}

/// A wire drawn from (ax, ay) to (bx, by); `to` is the object at the other end.
struct Wire {
    let to, ax, ay, bx, by: Int
}

/// 6502 code in the wall bytes of an unused room: part of the routine at `entry`,
/// which the world's code calls with JSR/JMP at `caller`.
struct RoomCode: Hashable {
    let caller, entry: Int
}

/// A world: the memory image $6000-$94FF plus the engine tables needed to draw it.
/// See Docs/WorldFormat.md for the layout; its tables by name are GameSymbols'.
struct World: Identifiable {
    static let roomCount = 64
    static let objectCount = 256
    static let textCount = 128
    static let nowhere = 0x3F
    static let noObject = 0xFF

    let id: String
    let name: String
    let kind: WorldKind
    /// Full 64K memory image (world at $6000, engine at $9500/$B8E0/$D000/$F000,
    /// code at $0803) with language card bank 2 at $D000.
    let mem: [UInt8]
    /// Language card bank 1 ($D000-$DFFF): engine data, chips.
    let bank1: [UInt8]
    /// Rooms whose wall bytes hold 6502 code instead of walls.
    let codeRooms: [Int: RoomCode]
    /// The engine loaded with the world.
    let engine: EngineBuild
    /// The loader's check of the engine code, for the disks' version (nil:
    /// unknown, so everything runs as 6502 code).
    let codeCheck: CodeCheck?

    /// `codeRooms` is found in `mem` unless given.
    init(id: String, name: String, kind: WorldKind, mem: [UInt8], bank1: [UInt8]? = nil,
         codeRooms: [Int: RoomCode]? = nil, engine: EngineBuild = .levels, codeCheck: CodeCheck? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.mem = mem
        self.bank1 = bank1 ?? [UInt8](repeating: 0, count: 0x1000)
        self.codeRooms = codeRooms ?? World.findCodeRooms(in: mem)
        self.engine = engine
        self.codeCheck = codeCheck
    }

    @inline(__always) private func m(_ table: KeyPath<GameSymbols, Table>, _ i: Int) -> Int { Int(mem[table, i]) }

    // MARK: objects

    func object(_ i: Int) -> GameObject {
        GameObject(id: i, next: m(\.objNext, i), sprite: m(\.objSprite, i), color: m(\.objColour, i),
                   room: m(\.objRoom, i), x: m(\.objX, i), y: m(\.objY, i), link: m(\.objLink, i),
                   dx: m(\.objLinkDX, i), dy: m(\.objLinkDY, i), flags: m(\.objFlags, i))
    }

    /// Objects in drawing order: the room's linked list, then any others in that room.
    func objectsInRoom(_ room: Int) -> [Int] {
        var order: [Int] = []
        var seen = Set<Int>()
        var o = m(\.roomFirstObject, room)
        while o != World.noObject, !seen.contains(o), m(\.objRoom, o) == room {
            seen.insert(o)
            order.append(o)
            o = m(\.objNext, o)
        }
        order += (0 ..< World.objectCount).filter { !seen.contains($0) && m(\.objRoom, $0) == room }
        return order
    }

    /// Objects exactly as the engine draws them (DRAW_ROOM_OBJECTS): the
    /// room's list from ROOM_FIRST_OBJECT until $FF, at most 255 objects.
    func drawList(_ room: Int) -> [Int] {
        var order: [Int] = []
        var o = m(\.roomFirstObject, room)
        while o != World.noObject, order.count < 255 {
            order.append(o)
            o = m(\.objNext, o)
        }
        return order
    }

    /// 16 rows, row 0 at the bottom; bit 6 is the leftmost of 7 pixels.
    func sprite(_ n: Int) -> ArraySlice<UInt8> {
        let base = GameSymbols.address(\.sprites) + (n & 0x3F) * 16
        return mem[base ..< base + 16]
    }

    /// The wire tables (WIRE_TO, ...): the levels keep them in the world
    /// image, Robot Anatomy/Toolkit and the lab in the world's code.
    private func wireTable(_ t: KeyPath<GameSymbols, Table>) -> Int {
        GameSymbols.map[keyPath: t].address(engine)!
    }

    func wire(_ o: Int) -> Wire? {
        guard mem[wireTable(\.wireTo) + o] != 0 else { return nil }
        return Wire(to: Int(mem[wireTable(\.wireTo) + o]), ax: Int(mem[wireTable(\.wireAX) + o]),
                    ay: Int(mem[wireTable(\.wireAY) + o]), bx: Int(mem[wireTable(\.wireBX) + o]),
                    by: Int(mem[wireTable(\.wireBY) + o]))
    }

    /// Wire of a loose wire object $D1-$DF (PIN_LINE... in the levels).
    func looseWire(_ o: Int) -> (ax: Int, ay: Int, bx: Int, by: Int)? {
        let w = wireTable(\.wireTo) + 0x466 + o
        guard mem[w] != 0 else { return nil }
        return (Int(mem[w + 0x0F]), Int(mem[w + 0x2D]), Int(mem[w + 0x1E]), Int(mem[w + 0x3C]))
    }

    /// ROBOT_BODY and ROBOT_INTERIOR: body object and interior room of each of the 4 robots.
    var robots: [(object: Int, interior: Int)] {
        (0 ..< 4).map { (m(\.robotBody, $0), m(\.robotInterior, $0)) }
    }

    // MARK: rooms

    func room(_ r: Int) -> Room {
        Room(id: r, firstObject: m(\.roomFirstObject, r), floorColor: m(\.roomFloorColour, r),
             wallColor: m(\.roomWallColour, r), up: m(\.roomUp, r), down: m(\.roomDown, r),
             left: m(\.roomLeft, r), right: m(\.roomRight, r), walls: walls(r))
    }

    /// 30 bytes per room: 3 bands of 4 rows; one nibble per column, bit 0 = top row of the band.
    func walls(_ r: Int) -> [[Bool]] {
        let base = GameSymbols.address(\.roomWalls) + r * 30
        var grid = Array(repeating: Array(repeating: false, count: 20), count: 12)
        for band in 0 ..< 3 {
            for col in 0 ..< 20 {
                let nibble = (Int(mem[base + band * 10 + col / 2]) >> (4 * (col & 1))) & 0xF
                for k in 0 ..< 4 { grid[band * 4 + k][col] = nibble >> k & 1 != 0 }
            }
        }
        return grid
    }

    func isRoomUsed(_ r: Int) -> Bool {
        let base = GameSymbols.address(\.roomWalls) + r * 30
        return mem[base ..< base + 30].contains { $0 != 0 } || !objectsInRoom(r).isEmpty || !textsInRoom(r).isEmpty
    }

    /// Rooms whose wall bytes hold a routine that the world's code ($0803-$1FFF,
    /// $8EF0-$94FF) calls with JSR/JMP.  Followed through branches and JSR/JMP
    /// inside the wall table until RTS/RTI/JMP, the routine must contain only
    /// valid opcodes (no BRK), and every room it covers must lead back to itself
    /// on all four sides.  Same as `World.code_rooms` in Data/ro_world.py.
    static func findCodeRooms(in mem: [UInt8]) -> [Int: RoomCode] {
        let walls = GameSymbols.address(\.roomWalls) ..< GameSymbols.address(\.roomWalls) + roomCount * 30
        let exits: [KeyPath<GameSymbols, Table>] = [\.roomUp, \.roomDown, \.roomRight, \.roomLeft]
        var found: [Int: RoomCode] = [:]
        for region in [0x0803 ..< 0x2000, 0x8EF0 ..< 0x9500] {
            for site in region.lowerBound ..< region.upperBound - 2 where mem[site] == 0x20 || mem[site] == 0x4C {
                let entry = Int(mem[site + 1]) | Int(mem[site + 2]) << 8
                guard walls.contains(entry), let code = traceCode(in: mem, from: entry, within: walls) else { continue }
                let rooms = Set(code.map { ($0 - walls.lowerBound) / 30 })
                guard rooms.allSatisfy({ r in exits.allSatisfy { Int(mem[$0, r]) == r } }) else { continue }
                for r in rooms where found[r] == nil { found[r] = RoomCode(caller: site, entry: entry) }
            }
        }
        return found
    }

    /// Addresses of the instruction bytes reachable from `entry` inside `area`,
    /// following branches and JSR/JMP; nil at an invalid opcode or BRK.
    private static func traceCode(in mem: [UInt8], from entry: Int, within area: Range<Int>) -> Set<Int>? {
        var code = Set<Int>()
        var pending = [entry]
        while var pc = pending.popLast() {
            while area.contains(pc), !code.contains(pc) {
                guard let info = CPU6502.table[Int(mem[pc])], info.op != .brk else { return nil }
                let n = CPU6502.length(info.mode)
                code.formUnion(pc ..< pc + n)
                if info.mode == .rel { pending.append(pc + 2 + Int(Int8(bitPattern: mem[pc + 1]))) }
                if info.op == .jsr || (info.op == .jmp && info.mode == .abs) {
                    pending.append(Int(mem[pc + 1]) | Int(mem[pc + 2]) << 8)
                }
                if [.jmp, .rts, .rti].contains(info.op) { break }
                pc += n
            }
        }
        return code
    }

    // MARK: texts

    func text(_ i: Int) -> RoomText {
        var ptr = m(\.textPointerLow, i) | m(\.textPointerHigh, i) << 8
        var bytes: [UInt8] = []
        while mem[ptr] != 0, bytes.count < 1024 {
            bytes.append(mem[ptr])
            ptr += 1
        }
        return RoomText(id: i, room: m(\.textRoom, i), x: m(\.textX, i), y: m(\.textY, i),
                        style: m(\.textStyle, i), color: m(\.textColour, i), bytes: bytes)
    }

    func textsInRoom(_ r: Int) -> [Int] {
        (0 ..< World.textCount).filter { m(\.textRoom, $0) == r && (m(\.textPointerLow, $0) | m(\.textPointerHigh, $0)) != 0 }
    }
}
