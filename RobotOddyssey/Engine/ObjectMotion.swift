import Foundation

/// Native port of the engine's object movement, shared by every world: the
/// player's input (PlayerInput), the robots and the worlds' own code move
/// objects with it.  Move an object across room edges (MOVE_OBJECT,
/// MOVE_OBJECT_XY), put it into another room's object list (SET_OBJECT_ROOM),
/// the rooms' wall bitmaps (ROOM_WALLS_PTR, WALL_AT), stop a move at walls
/// (STOP_AT_WALLS) and at the screen's edges (KEEP_ON_SCREEN), limit its
/// speed (LIMIT_MOVE).
///
/// Other code calls these with parameters in registers and may use what they
/// leave there, so each leaves memory *and* A, X, Y and the flags exactly as
/// the original does (Data/native_check.swift compares both).  The object is
/// CUR_OBJECT, the move (MOVE_DX, MOVE_DY).
///
/// Positions: x 0-$85 in a room (two pixels each, 7 per wall tile), y 0-$B0
/// from the bottom (16 per tile); 20 × 12 tiles.  An object is a 7 × 16 box.
extension Engine {
    // MARK: walls

    /// ROOM_WALLS_PTR ($9D56): POINTER = the wall bitmap of room A,
    /// ROOM_WALLS + 30 × A (ROOM_WALLS's low byte is 0).
    mutating func roomWallsPointer() {
        m.wallsRoom = r.a
        let offset = 30 * Int(r.a)
        r.carry = false
        r.a = r.adc(UInt8(offset >> 8), UInt8(m.roomWalls.address >> 8))
        m.pointer = offset & 0xFF | Int(r.a) << 8
    }

    /// WALL_AT ($B40B): whether the wall bitmap at POINTER has a wall at tile
    /// WALL_COLUMN (0-19), WALL_ROW (0-11, counted from the bottom); A = 1 or
    /// 0 (Z set when free), 0 outside the room.  The bitmap holds 3 bands of
    /// 4 rows from the top, 10 bytes each: a byte is two columns, 4 bits each.
    mutating func wallAt() {
        let column = m.wallColumn, row = m.wallRow
        r.compare(row, 0x0C)
        if !r.carry { r.compare(column, 0x14) }
        guard !r.carry else {
            r.a = r.nz(0)
            return
        }
        let fromTop = 11 - row
        r.x = column << 2 & 4 | fromTop & 3
        let group = m.wallGroupOffsets[fromTop >> 2]
        m.wallGroup = group
        r.carry = false
        r.y = r.adc(column >> 1, group)
        let wall = m[m.pointer + Int(r.y)] & m.wallBits[r.x]
        r.a = wall == 0 ? 0 : 1
        r.carry = false
        r.nz(r.a)
    }

    // MARK: moving

    /// MOVE_OBJECT ($9DB3): moves CUR_OBJECT by (MOVE_DX, MOVE_DY) from its room.
    mutating func moveObject() {
        r.y = m.currentObject
        r.x = r.nz(m.objRoom[r.y])
        moveObjectXY()
    }

    /// MOVE_OBJECT_XY ($9DB9): moves object Y of room X by (MOVE_DX, MOVE_DY).
    /// Across an edge it goes on in the linked room: x wraps by $86, y by $B1
    /// (a coordinate of $D8 or more has left by the left or bottom edge).  The
    /// room it ends in becomes DEST_ROOM and the object moves there
    /// (SET_OBJECT_ROOM).
    mutating func moveObjectXY() {
        let object = Int(r.y)
        var room = Int(r.x)
        r.carry = false
        let movedX = r.adc(m.objX[object], m.moveDX)
        let x = wrap(movedX, size: 0x86, &room, before: m.roomLeft, after: m.roomRight)
        m.objX[object] = x
        r.carry = false
        let movedY = r.adc(m.objY[object], m.moveDY)
        let y = wrap(movedY, size: 0xB1, &room, before: m.roomDown, after: m.roomUp)
        m.objY[object] = y
        r.a = y
        r.x = UInt8(room)
        m.destinationRoom = UInt8(room)
        setObjectRoom()
    }

    /// One coordinate of `moveObjectXY`: below 0 ($D8 and more) it goes on in
    /// the room `before`, at `size` and more in the room `after`.
    private mutating func wrap(_ v: UInt8, size: UInt8, _ room: inout Int, before: Bytes, after: Bytes) -> UInt8 {
        var v = v
        r.compare(v, 0xD8)
        if r.carry {
            r.carry = false
            v = r.adc(v, size)
            room = Int(before[room])
        }
        r.compare(v, size)
        if r.carry {
            r.carry = true
            v = r.sbc(v, size)
            room = Int(after[room])
            r.nz(v)
        }
        return v
    }

    /// SET_OBJECT_ROOM ($9E07): moves CUR_OBJECT to DEST_ROOM: out of its
    /// room's object list (OBJ_NEXT chains from ROOM_FIRST_OBJECT, $FF ends)
    /// and into the new room's, which is kept in object order.
    mutating func setObjectRoom() {
        let object = m.currentObject
        let to = m.destinationRoom
        r.x = object
        r.y = m.objRoom[object]
        r.compare(r.y, to)
        if r.zero { return }
        let from = r.y
        var next = m.roomFirstObject[from]
        if next == object {
            m.roomFirstObject[from] = m.objNext[object]
        } else if next != 0xFF {
            while true {
                let previous = next
                next = m.objNext[previous]
                if next == 0xFF { break }
                if next == object {
                    m.objNext[previous] = m.objNext[object]
                    break
                }
            }
        }
        r.y = to
        next = m.roomFirstObject[to]
        if next == 0xFF || next >= object {
            m.objNext[object] = next
            m.roomFirstObject[to] = object
        } else {
            var previous: UInt8
            repeat {
                previous = next
                next = m.objNext[previous]
            } while next != 0xFF && next < object
            m.objNext[object] = next
            m.objNext[previous] = object
            r.y = previous
        }
        m.objRoom[object] = to
        r.a = r.nz(to)
        r.carry = true
    }

    // MARK: limiting the move

    /// KEEP_ON_SCREEN ($A934): keeps CUR_OBJECT's move inside the screen: a
    /// move past the right or left edge goes exactly to it ($86 or $FF, which
    /// MOVE_OBJECT carries into the next room) and loses its vertical part;
    /// past the top or bottom ($B1 or $FF) it loses the horizontal part.
    mutating func keepOnScreen() {
        r.y = m.currentObject
        let object = Int(r.y)
        r.carry = false
        let x = r.adc(m.objX[object], m.moveDX)
        r.compare(x, 0x86)
        if r.carry {
            toEdge(m.screenEdgesX, from: m.objX[object], x)
            m.moveDX = r.a
            m.moveDY = 0
            r.a = r.nz(0)
            return
        }
        r.carry = false
        let y = r.adc(m.objY[object], m.moveDY)
        r.compare(y, 0xB1)
        guard r.carry else {
            r.a = y
            return
        }
        toEdge(m.screenEdgesY, from: m.objY[object], y)
        m.moveDY = r.a
        m.moveDX = 0
        r.a = r.nz(0)
    }

    /// A = the move from `position` to the far edge (`edges`[0]) or, if the
    /// coordinate `v` went below 0 ($D8 and more), to the near one (`edges`[1]).
    private mutating func toEdge(_ edges: Bytes, from position: UInt8, _ v: UInt8) {
        r.compare(v, 0xD8)
        r.x = r.carry ? 1 : 0
        r.carry = true
        r.a = r.sbc(edges[r.x], position)
    }

    /// LIMIT_MOVE ($ACF8): limits the move to X steps horizontally and Y vertically.
    mutating func limitMove() {
        m.limitX = r.x
        m.limitY = r.y
        limit(\.moveDX, to: \.limitX)
        limit(\.moveDY, to: \.limitY)
    }

    private mutating func limit(_ move: ByteSymbol, to limit: ByteSymbol) {
        r.a = r.magnitude(m[move])
        r.compare(r.a, m[limit])
        guard r.carry && !r.zero else { return }
        r.y = m[move] & 0x80 == 0 ? 0xFF : 0
        r.a = m[limit]
        withSign()
        m[move] = r.a
    }

    /// WITH_SIGN ($AB91): A with the sign Y asks for: as it is for Y above
    /// $80, negated below, 0 for $80.
    private mutating func withSign() {
        r.compare(r.y, 0x80)
        if r.zero {
            r.a = r.nz(0)
        } else if !r.carry {
            r.carry = false
            r.a = r.adc(r.a ^ 0xFF, 1)
        }
    }

    // MARK: walls in the way

    /// What TEST_MOVE finds at the object's corners.
    private static let wallHit: UInt8 = 1, offRight: UInt8 = 2, offTop: UInt8 = 4

    /// STOP_AT_WALLS ($AD40): stops CUR_OBJECT's move at walls.  If one of
    /// the object's corners (a 7 × 16 box) would end on a wall, it first keeps
    /// the longer part of the move and stops the other at the edge of the tile
    /// the object is in, then the other way round, else stops both.  A move
    /// off the screen's side loses its vertical part, one off the top its
    /// horizontal part.  A = what the last test found (`testMove`), 0 when stopped.
    mutating func stopAtWalls() {
        m.tryDX = m.moveDX
        m.tryDY = m.moveDY
        r.a = findWay()
        r.x = r.nz(m.tryDX)
        r.y = r.nz(m.tryDY)
        r.bit(r.a, m.offRightBit)
        if !r.zero { r.y = r.nz(0) }
        r.bit(r.a, m.offTopBit)
        if !r.zero { r.x = r.nz(0) }
        m.moveDX = r.x
        m.moveDY = r.y
    }

    private mutating func findWay() -> UInt8 {
        var found = testMove()
        r.compare(found, Engine.wallHit)
        guard r.zero else { return found }
        m.sizeDX = r.magnitude(m.moveDX)
        m.sizeDY = r.magnitude(m.moveDY)
        r.compare(r.nz(m.sizeDX), m.sizeDY)
        for keepHorizontal in r.carry ? [true, false] : [false, true] {
            if keepHorizontal {
                m.tryDX = r.nz(m.moveDX)
                stopAtTileRow()
            } else {
                stopAtTileColumn()
                m.tryDY = r.nz(m.moveDY)
            }
            found = testMove()
            r.compare(found, Engine.wallHit)
            guard r.zero else { return found }
        }
        stopAtTileColumn()
        stopAtTileRow()
        return r.nz(0)
    }

    /// TEST_MOVE ($AE69): what CUR_OBJECT's four corners would meet after
    /// moving by (TRY_DX, TRY_DY): a wall, the right edge (x $8C and more), the
    /// top (y $C0 and more).  In A and TEST_RESULT.
    private mutating func testMove() -> UInt8 {
        r.a = m.objRoom[m.currentObject]
        roomWallsPointer()
        m.testCorner = 3
        m.testResult = 0
        repeat {
            r.x = m.testCorner
            r.y = m.currentObject
            let object = Int(r.y), corner = Int(r.x)
            r.carry = false
            var x = r.adc(m.objX[object], m.cornerDX[corner])
            r.carry = false
            x = r.adc(x, m.tryDX)
            r.compare(x, 0x8C)
            if r.carry {
                m.testResult |= Engine.offRight
            } else {
                m.wallColumn = m.xByteTable[x] >> 1
                r.carry = false
                var y = r.adc(m.objY[object], m.cornerDY[corner])
                r.carry = false
                y = r.adc(y, m.tryDY)
                r.compare(y, 0xC0)
                if r.carry {
                    m.testResult |= Engine.offTop
                } else {
                    m.wallRow = y >> 4
                    wallAt()
                    if !r.zero { m.testResult |= Engine.wallHit }
                }
            }
            m.testCorner &-= 1
        } while m.testCorner & 0x80 == 0
        r.a = r.nz(m.testResult)
        return r.a
    }

    /// STOP_AT_TILE_COLUMN ($ADD5): TRY_DX = the move to the edge of
    /// CUR_OBJECT's tile column in MOVE_DX's direction, or MOVE_DX if that is shorter.
    private mutating func stopAtTileColumn() {
        r.y = m.currentObject
        let x = m.objX[r.y]
        r.x = x
        let column = m.xByteTable[x] >> 1
        m.tileColumn = column
        r.carry = false
        var a = r.adc(column << 1, column)
        r.carry = false
        a = r.adc(a << 1, column)
        r.carry = true
        a = r.sbc(a, x)
        if !r.zero {
            r.x = r.nz(m.moveDX)
            if r.x & 0x80 == 0 {
                r.carry = false
                a = r.adc(a, 7)
            }
        }
        m.tryDX = a
        keepShorter(\.moveDX, or: \.tryDX, sizes: \.sizeDX, \.sizeTryDX)
    }

    /// STOP_AT_TILE_ROW ($AE2A): TRY_DY = the move to the edge of
    /// CUR_OBJECT's tile row in MOVE_DY's direction, or MOVE_DY if that is shorter.
    private mutating func stopAtTileRow() {
        r.y = m.currentObject
        let y = m.objY[r.y]
        r.carry = true
        var a = r.sbc(y & 0xF0, y)
        if !r.zero {
            r.x = r.nz(m.moveDY)
            if r.x & 0x80 == 0 {
                r.carry = false
                a = r.adc(a, 0x10)
            }
        }
        m.tryDY = a
        keepShorter(\.moveDY, or: \.tryDY, sizes: \.sizeDY, \.sizeTryDY)
    }

    /// The move `wanted` replaces the move `aligned` if it is shorter.
    private mutating func keepShorter(_ wanted: ByteSymbol, or aligned: ByteSymbol,
                                      sizes wantedSize: ByteSymbol, _ alignedSize: ByteSymbol) {
        m[wantedSize] = r.magnitude(m[wanted])
        m[alignedSize] = r.magnitude(m[aligned])
        r.a = r.nz(m[wantedSize])
        r.compare(r.a, m[alignedSize])
        if !r.carry {
            r.a = r.nz(m[wanted])
            m[aligned] = r.a
        }
    }
}
