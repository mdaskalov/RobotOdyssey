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

/// A world: the memory image $6000-$94FF plus the engine tables needed to draw it.
/// See Docs/WorldFormat.md for the layout.
struct World: Identifiable {
    static let roomCount = 64
    static let objectCount = 256
    static let textCount = 128
    static let nowhere = 0x3F
    static let noObject = 0xFF

    let id: String
    let name: String
    let kind: WorldKind
    /// Full 64K memory image (world at $6000, engine font at $9500, colours at $9B91, code at $0803).
    let mem: [UInt8]

    @inline(__always) private func m(_ addr: Int) -> Int { Int(mem[addr]) }

    // MARK: objects

    func object(_ i: Int) -> GameObject {
        let f = (0 ..< 10).map { m(0x6000 + $0 * 0x100 + i) }
        return GameObject(id: i, next: f[0], sprite: f[1], color: f[2], room: f[3], x: f[4], y: f[5],
                          link: f[6], dx: f[7], dy: f[8], flags: f[9])
    }

    /// Objects in drawing order: the room's linked list, then any others in that room.
    func objectsInRoom(_ room: Int) -> [Int] {
        var order: [Int] = []
        var seen = Set<Int>()
        var o = m(0x6E00 + room)
        while o != World.noObject, !seen.contains(o), m(0x6300 + o) == room {
            seen.insert(o)
            order.append(o)
            o = m(0x6000 + o)
        }
        order += (0 ..< World.objectCount).filter { !seen.contains($0) && m(0x6300 + $0) == room }
        return order
    }

    /// Objects exactly as the engine draws them ($9D18): the room's list from
    /// $6E00 until $FF, at most 255 objects.
    func drawList(_ room: Int) -> [Int] {
        var order: [Int] = []
        var o = m(0x6E00 + room)
        while o != World.noObject, order.count < 255 {
            order.append(o)
            o = m(0x6000 + o)
        }
        return order
    }

    /// 16 rows, row 0 at the bottom; bit 6 is the leftmost of 7 pixels.
    func sprite(_ n: Int) -> ArraySlice<UInt8> {
        let base = 0x6A00 + (n & 0x3F) * 16
        return mem[base ..< base + 16]
    }

    func wire(_ o: Int) -> Wire? {
        guard mem[0x861C + o] != 0 else { return nil }
        return Wire(to: m(0x861C + o), ax: m(0x871C + o), ay: m(0x891C + o), bx: m(0x881C + o), by: m(0x8A1C + o))
    }

    /// Robot table at $8200: body object and interior room of each of the 4 robots.
    var robots: [(object: Int, interior: Int)] {
        (0 ..< 4).map { (m(0x8200 + $0), m(0x8204 + $0)) }
    }

    // MARK: rooms

    func room(_ r: Int) -> Room {
        let f = (0 ..< 7).map { m(0x6E00 + $0 * 0x40 + r) }
        return Room(id: r, firstObject: f[0], floorColor: f[1], wallColor: f[2],
                    up: f[3], down: f[4], left: f[6], right: f[5], walls: walls(r))
    }

    /// 30 bytes per room: 3 bands of 4 rows; one nibble per column, bit 0 = top row of the band.
    func walls(_ r: Int) -> [[Bool]] {
        let base = 0x7000 + r * 30
        var grid = Array(repeating: Array(repeating: false, count: 20), count: 12)
        for band in 0 ..< 3 {
            for col in 0 ..< 20 {
                let nibble = (m(base + band * 10 + col / 2) >> (4 * (col & 1))) & 0xF
                for k in 0 ..< 4 { grid[band * 4 + k][col] = nibble >> k & 1 != 0 }
            }
        }
        return grid
    }

    func isRoomUsed(_ r: Int) -> Bool {
        let base = 0x7000 + r * 30
        return mem[base ..< base + 30].contains { $0 != 0 } || !objectsInRoom(r).isEmpty || !textsInRoom(r).isEmpty
    }

    // MARK: texts

    func text(_ i: Int) -> RoomText {
        var ptr = m(0x7B80 + i) | m(0x7C00 + i) << 8
        var bytes: [UInt8] = []
        while mem[ptr] != 0, bytes.count < 1024 {
            bytes.append(mem[ptr])
            ptr += 1
        }
        return RoomText(id: i, room: m(0x7880 + i), x: m(0x7900 + i), y: m(0x7980 + i),
                        style: m(0x7A00 + i), color: m(0x7B00 + i), bytes: bytes)
    }

    func textsInRoom(_ r: Int) -> [Int] {
        (0 ..< World.textCount).filter { m(0x7880 + $0) == r && (m(0x7B80 + $0) | m(0x7C00 + $0)) != 0 }
    }
}
