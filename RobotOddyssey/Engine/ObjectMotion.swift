import Foundation

/// Native port of the engine's object movement, shared by every world: the
/// player's input ($A90C, PlayerInput), the robots and the worlds' own code
/// move objects with it.  Move an object across room edges ($9DB3, $9DB9),
/// put it into another room's object list ($9E07), the rooms' wall bitmaps
/// ($9D56, $B40B), stop a move at walls ($AD40) and at the screen's edges
/// ($A934), limit its speed ($ACF8).
///
/// Other code calls these with parameters in registers and may use what they
/// leave there, so each leaves memory *and* A, X, Y and the flags exactly as
/// the original does (Data/native_check.swift compares both).  The object is
/// CUR_OBJECT ($9C2F), the move (MOVE_DX, MOVE_DY) at $9C22/$9C23.
///
/// Positions: x 0-$85 in a room (two pixels each, 7 per wall tile), y 0-$B0
/// from the bottom (16 per tile); 20 × 12 tiles.  An object is a 7 × 16 box.
enum ObjectMotion {
    /// The code the ports replace (engine main, $9500-$B7FF; the same in v1.0
    /// and v1.1), without the variables kept in between.
    static let code = [0x9D56 ..< 0x9D8F, 0x9DB3 ..< 0x9E7A, 0xA934 ..< 0xA979, 0xAB91 ..< 0xABA1,
                       0xACF8 ..< 0xAD3D, 0xAD40 ..< 0xADD3, 0xADD5 ..< 0xAE28, 0xAE2A ..< 0xAE65,
                       0xAE67 ..< 0xAEDF, 0xB40B ..< 0xB44F]
    static let fingerprint = "df9e60a1ba04c4ab7f63eb92a65a1931"

    static func matches(_ mem: [UInt8]) -> Bool {
        DiskImage.md5(code.flatMap { mem[$0] }) == fingerprint
    }

    /// Entry points and routines, for `Machine.installNatives`.
    static var entries: [(UInt16, String, (inout RAM, inout Registers) -> Void)] { [
        (0x9D56, "ROOM_WALLS_PTR", { wallsPointer(&$0, &$1) }), (0x9DB3, "MOVE_OBJECT", { moveObject(&$0, &$1) }),
        (0x9DB9, "MOVE_OBJECT_XY", { moveObjectXY(&$0, &$1) }), (0x9E07, "SET_OBJECT_ROOM", { setObjectRoom(&$0, &$1) }),
        (0xA934, "KEEP_ON_SCREEN", { keepOnScreen(&$0, &$1) }), (0xACF8, "LIMIT_MOVE", { limitMove(&$0, &$1) }),
        (0xAD40, "STOP_AT_WALLS", { stopAtWalls(&$0, &$1) }), (0xB40B, "WALL_AT", { wallAt(&$0, &$1) }),
    ] }

    // Objects and rooms (WorldFormat.md).
    static let objNext = 0x6000, objRoom = 0x6300, objX = 0x6400, objY = 0x6500
    static let roomFirst = 0x6E00, roomUp = 0x6EC0, roomDown = 0x6F00, roomRight = 0x6F40, roomLeft = 0x6F80
    static let roomWalls = 0x7000
    /// X_BYTE_TABLE: the hi-res byte of each x.
    static let xByte = 0x9B05

    // Variables and tables of the code.
    static let wallsRoom = 0x9D55
    static let wallGroup = 0xB3A8, wallGroupOffsets = 0xB3F8, wallBits = 0xB3FB
    static let screenEdgeX = 0xA979, screenEdgeY = 0xA97B
    static let limitX = 0xACF6, limitY = 0xACF7
    static let tryDX = 0xAD3D, tryDY = 0xAD3E, tileColumn = 0xAD3F
    static let sizeDX = 0xADD3, sizeTryDX = 0xADD4, sizeDY = 0xAE28, sizeTryDY = 0xAE29
    static let testResult = 0xAE65, corner = 0xAE66, offRightBit = 0xAE67, offTopBit = 0xAE68
    static let cornerDX = 0xAEDF, cornerDY = 0xAEE3

    // MARK: walls ($9D56, $B40B)

    /// ROOM_WALLS_PTR ($9D56): ($00) = the wall bitmap of room A, ROOM_WALLS + 30 × A.
    static func wallsPointer(_ m: inout RAM, _ r: inout Registers) {
        let room = r.a
        m[wallsRoom] = room
        let offset = 30 * Int(room)
        m[0x00] = UInt8(offset & 0xFF)
        r.carry = false
        r.a = r.adc(UInt8(offset >> 8), UInt8(roomWalls >> 8))
        m[0x01] = r.a
    }

    /// WALL_AT ($B40B): whether the wall bitmap at ($00) has a wall at tile
    /// column $02 (0-19), row $03 (0-11, counted from the bottom); A = 1 or 0
    /// (Z set when free), 0 outside the room.  The bitmap holds 3 bands of 4
    /// rows from the top, 10 bytes each: a byte is two columns, 4 bits each.
    static func wallAt(_ m: inout RAM, _ r: inout Registers) {
        let column = m[0x02], row = m[0x03]
        r.compare(row, 0x0C)
        if !r.carry { r.compare(column, 0x14) }
        guard !r.carry else {
            r.a = r.nz(0)
            return
        }
        let fromTop = 11 - row
        r.x = column << 2 & 4 | fromTop & 3
        let group = m[wallGroupOffsets + Int(fromTop >> 2)]
        m[wallGroup] = group
        r.carry = false
        r.y = r.adc(column >> 1, group)
        let wall = m[(m.word(0x00) + Int(r.y)) & 0xFFFF] & m[wallBits + Int(r.x)]
        r.a = wall == 0 ? 0 : 1
        r.carry = false
        r.nz(r.a)
    }

    // MARK: moving ($9DB3, $9DB9, $9E07)

    /// MOVE_OBJECT ($9DB3): moves CUR_OBJECT by (MOVE_DX, MOVE_DY) from its room.
    static func moveObject(_ m: inout RAM, _ r: inout Registers) {
        r.y = m[RAM.currentObject]
        r.x = r.nz(m[objRoom + Int(r.y)])
        moveObjectXY(&m, &r)
    }

    /// MOVE_OBJECT_XY ($9DB9): moves object Y of room X by (MOVE_DX, MOVE_DY).
    /// Across an edge it goes on in the linked room: x wraps by $86, y by $B1
    /// (a coordinate of $D8 or more has left by the left or bottom edge).  The
    /// room it ends in becomes DEST_ROOM and the object moves there
    /// (SET_OBJECT_ROOM).
    static func moveObjectXY(_ m: inout RAM, _ r: inout Registers) {
        let object = Int(r.y)
        var room = Int(r.x)
        r.carry = false
        let x = wrap(r.adc(m[objX + object], m[RAM.moveDX]), size: 0x86, &room,
                     before: roomLeft, after: roomRight, &m, &r)
        m[objX + object] = x
        r.carry = false
        let y = wrap(r.adc(m[objY + object], m[RAM.moveDY]), size: 0xB1, &room,
                     before: roomDown, after: roomUp, &m, &r)
        m[objY + object] = y
        r.a = y
        r.x = UInt8(room)
        m[RAM.destinationRoom] = UInt8(room)
        setObjectRoom(&m, &r)
    }

    /// One coordinate of `moveObjectXY`: below 0 ($D8 and more) it
    /// goes on in the room `before`, at `size` and more in the room `after`.
    private static func wrap(_ v: UInt8, size: UInt8, _ room: inout Int, before: Int, after: Int,
                             _ m: inout RAM, _ r: inout Registers) -> UInt8 {
        var v = v
        r.compare(v, 0xD8)
        if r.carry {
            r.carry = false
            v = r.adc(v, size)
            room = Int(m[before + room])
        }
        r.compare(v, size)
        if r.carry {
            r.carry = true
            v = r.sbc(v, size)
            room = Int(m[after + room])
            r.nz(v)
        }
        return v
    }

    /// SET_OBJECT_ROOM ($9E07): moves CUR_OBJECT to DEST_ROOM: out of its
    /// room's object list (OBJ_NEXT chains from ROOM_FIRST, $FF ends) and into
    /// the new room's, which is kept in object order.
    static func setObjectRoom(_ m: inout RAM, _ r: inout Registers) {
        let object = m[RAM.currentObject]
        let to = m[RAM.destinationRoom]
        r.x = object
        r.y = m[objRoom + Int(object)]
        r.compare(r.y, to)
        if r.zero { return }
        let from = Int(r.y)
        var next = m[roomFirst + from]
        if next == object {
            m[roomFirst + from] = m[objNext + Int(object)]
        } else if next != 0xFF {
            while true {
                let previous = Int(next)
                next = m[objNext + previous]
                if next == 0xFF { break }
                if next == object {
                    m[objNext + previous] = m[objNext + Int(object)]
                    break
                }
            }
        }
        r.y = to
        next = m[roomFirst + Int(to)]
        if next == 0xFF || next >= object {
            m[objNext + Int(object)] = next
            m[roomFirst + Int(to)] = object
        } else {
            var previous: UInt8
            repeat {
                previous = next
                next = m[objNext + Int(previous)]
            } while next != 0xFF && next < object
            m[objNext + Int(object)] = next
            m[objNext + Int(previous)] = object
            r.y = previous
        }
        m[objRoom + Int(object)] = to
        r.a = r.nz(to)
        r.carry = true
    }

    // MARK: limiting the move ($A934, $ACF8)

    /// $A934: keeps CUR_OBJECT's move inside the screen: a move past the right
    /// or left edge goes exactly to it ($86 or $FF, which MOVE_OBJECT carries
    /// into the next room) and loses its vertical part; past the top or bottom
    /// ($B1 or $FF) it loses the horizontal part.
    static func keepOnScreen(_ m: inout RAM, _ r: inout Registers) {
        r.y = m[RAM.currentObject]
        let object = Int(r.y)
        r.carry = false
        let x = r.adc(m[objX + object], m[RAM.moveDX])
        r.compare(x, 0x86)
        if r.carry {
            toEdge(of: objX, at: screenEdgeX, x, object, &m, &r)
            m[RAM.moveDX] = r.a
            m[RAM.moveDY] = 0
            r.a = r.nz(0)
            return
        }
        r.carry = false
        let y = r.adc(m[objY + object], m[RAM.moveDY])
        r.compare(y, 0xB1)
        guard r.carry else {
            r.a = y
            return
        }
        toEdge(of: objY, at: screenEdgeY, y, object, &m, &r)
        m[RAM.moveDY] = r.a
        m[RAM.moveDX] = 0
        r.a = r.nz(0)
    }

    /// The move to the far edge (`edges`[0]) or, if the coordinate went below 0
    /// ($D8 and more), to the near one (`edges`[1]); in A.
    private static func toEdge(of coordinate: Int, at edges: Int, _ v: UInt8, _ object: Int,
                               _ m: inout RAM, _ r: inout Registers) {
        r.compare(v, 0xD8)
        r.x = r.carry ? 1 : 0
        r.carry = true
        r.a = r.sbc(m[edges + Int(r.x)], m[coordinate + object])
    }

    /// $ACF8: limits the move to X steps horizontally and Y vertically.
    static func limitMove(_ m: inout RAM, _ r: inout Registers) {
        m[limitX] = r.x
        m[limitY] = r.y
        limit(RAM.moveDX, to: limitX, &m, &r)
        limit(RAM.moveDY, to: limitY, &m, &r)
    }

    private static func limit(_ move: Int, to limit: Int, _ m: inout RAM, _ r: inout Registers) {
        r.a = r.magnitude(m[move])
        r.compare(r.a, m[limit])
        guard r.carry && !r.zero else { return }
        r.y = m[move] & 0x80 == 0 ? 0xFF : 0
        r.a = m[limit]
        withSign(&r)
        m[move] = r.a
    }

    /// $AB91: A with the sign Y asks for: as it is for Y above $80, negated
    /// below, 0 for $80.
    private static func withSign(_ r: inout Registers) {
        r.compare(r.y, 0x80)
        if r.zero {
            r.a = r.nz(0)
        } else if !r.carry {
            r.carry = false
            r.a = r.adc(r.a ^ 0xFF, 1)
        }
    }

    // MARK: walls in the way ($AD40)

    /// $AD40: stops CUR_OBJECT's move at walls.  If one of the object's
    /// corners (a 7 × 16 box) would end on a wall, it first keeps the longer
    /// part of the move and stops the other at the edge of the tile the object
    /// is in, then the other way round, else stops both.  A move off the
    /// screen's side loses its vertical part, one off the top its horizontal
    /// part.  A = what the last test found (`testMove`), 0 when stopped.
    static func stopAtWalls(_ m: inout RAM, _ r: inout Registers) {
        m[tryDX] = m[RAM.moveDX]
        m[tryDY] = m[RAM.moveDY]
        r.a = findWay(&m, &r)
        r.x = r.nz(m[tryDX])
        r.y = r.nz(m[tryDY])
        r.bit(r.a, m[offRightBit])
        if !r.zero { r.y = r.nz(0) }
        r.bit(r.a, m[offTopBit])
        if !r.zero { r.x = r.nz(0) }
        m[RAM.moveDX] = r.x
        m[RAM.moveDY] = r.y
    }

    private static func findWay(_ m: inout RAM, _ r: inout Registers) -> UInt8 {
        var found = testMove(&m, &r)
        r.compare(found, 1)
        guard r.zero else { return found }
        m[sizeDX] = r.magnitude(m[RAM.moveDX])
        m[sizeDY] = r.magnitude(m[RAM.moveDY])
        r.compare(r.nz(m[sizeDX]), m[sizeDY])
        for keepHorizontal in r.carry ? [true, false] : [false, true] {
            if keepHorizontal {
                m[tryDX] = r.nz(m[RAM.moveDX])
                stopAtTileRow(&m, &r)
            } else {
                stopAtTileColumn(&m, &r)
                m[tryDY] = r.nz(m[RAM.moveDY])
            }
            found = testMove(&m, &r)
            r.compare(found, 1)
            guard r.zero else { return found }
        }
        stopAtTileColumn(&m, &r)
        stopAtTileRow(&m, &r)
        return r.nz(0)
    }

    /// $AE69: what CUR_OBJECT's four corners would meet after moving by
    /// ($AD3D, $AD3E): bit 0 a wall, bit 1 the right edge (x $8C and more),
    /// bit 2 the top (y $C0 and more).  In A and $AE65.
    private static func testMove(_ m: inout RAM, _ r: inout Registers) -> UInt8 {
        r.a = m[objRoom + Int(m[RAM.currentObject])]
        wallsPointer(&m, &r)
        m[corner] = 3
        m[testResult] = 0
        repeat {
            r.x = m[corner]
            r.y = m[RAM.currentObject]
            let object = Int(r.y), c = Int(r.x)
            r.carry = false
            var x = r.adc(m[objX + object], m[cornerDX + c])
            r.carry = false
            x = r.adc(x, m[tryDX])
            r.compare(x, 0x8C)
            if r.carry {
                m[testResult] |= 2
            } else {
                m[0x02] = m[xByte + Int(x)] >> 1
                r.carry = false
                var y = r.adc(m[objY + object], m[cornerDY + c])
                r.carry = false
                y = r.adc(y, m[tryDY])
                r.compare(y, 0xC0)
                if r.carry {
                    m[testResult] |= 4
                } else {
                    m[0x03] = y >> 4
                    wallAt(&m, &r)
                    if !r.zero { m[testResult] |= 1 }
                }
            }
            m[corner] &-= 1
        } while m[corner] & 0x80 == 0
        r.a = r.nz(m[testResult])
        return r.a
    }

    /// $ADD5: $AD3D = the move to the edge of CUR_OBJECT's tile column in
    /// MOVE_DX's direction, or MOVE_DX if that is shorter.
    private static func stopAtTileColumn(_ m: inout RAM, _ r: inout Registers) {
        r.y = m[RAM.currentObject]
        let x = m[objX + Int(r.y)]
        r.x = x
        let column = m[xByte + Int(x)] >> 1
        m[tileColumn] = column
        r.carry = false
        var a = r.adc(column << 1, column)
        r.carry = false
        a = r.adc(a << 1, column)
        r.carry = true
        a = r.sbc(a, x)
        if !r.zero {
            r.x = r.nz(m[RAM.moveDX])
            if r.x & 0x80 == 0 {
                r.carry = false
                a = r.adc(a, 7)
            }
        }
        m[tryDX] = a
        shorter(RAM.moveDX, tryDX, sizes: sizeDX, sizeTryDX, &m, &r)
    }

    /// $AE2A: $AD3E = the move to the edge of CUR_OBJECT's tile row in
    /// MOVE_DY's direction, or MOVE_DY if that is shorter.
    private static func stopAtTileRow(_ m: inout RAM, _ r: inout Registers) {
        r.y = m[RAM.currentObject]
        let y = m[objY + Int(r.y)]
        r.carry = true
        var a = r.sbc(y & 0xF0, y)
        if !r.zero {
            r.x = r.nz(m[RAM.moveDY])
            if r.x & 0x80 == 0 {
                r.carry = false
                a = r.adc(a, 0x10)
            }
        }
        m[tryDY] = a
        shorter(RAM.moveDY, tryDY, sizes: sizeDY, sizeTryDY, &m, &r)
    }

    /// The move at `wanted` replaces the one at `aligned` if it is shorter.
    private static func shorter(_ wanted: Int, _ aligned: Int, sizes: Int, _ alignedSize: Int,
                                _ m: inout RAM, _ r: inout Registers) {
        m[sizes] = r.magnitude(m[wanted])
        m[alignedSize] = r.magnitude(m[aligned])
        r.a = r.nz(m[sizes])
        r.compare(r.a, m[alignedSize])
        if !r.carry {
            r.a = r.nz(m[wanted])
            m[aligned] = r.a
        }
    }
}
