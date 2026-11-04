import Foundation

/// What the canvas and the current room show of the selected room: the world as
/// the running loop's draw phase finds it (`GameLoop.memory`), with the
/// room's objects, and if recorded the sprites it drew (`GameLoop.sprites`):
/// the objects as drawn and the others (robots, the world's own code).
/// Without a draw (a code room, no main loop) the world as it starts.
struct RoomContents {
    let world: World
    let room: Int
    /// The world as the loop draws the room; false: as the world starts.
    let live: Bool
    /// The sprites drawn were recorded (`others`, the objects' `drawn`).
    let recorded: Bool
    /// The objects drawn, in drawing order, then the room's objects it didn't draw.
    let objects: [RoomSprite]
    /// The sprites drawn that are no object, in drawing order; the texts' letters left out.
    let others: [RoomSprite]
    /// What is on the page, in drawing order (topmost last).
    private let visible: [RoomSprite]

    init(world: World, room: Int, live: Bool = false, sprites: [DrawnSprite]? = nil) {
        self.world = world
        self.room = room
        self.live = live
        recorded = sprites != nil
        let texts = GameSymbols.address(\.drawRoomTexts)
        var objects: [RoomSprite] = [], others: [RoomSprite] = [], visible: [RoomSprite] = []
        for d in sprites ?? [] where d.routine != texts {
            let sprite: RoomSprite
            if let o = d.object {
                sprite = RoomSprite(id: .object(o), object: world.object(o), drawn: d)
                objects.removeAll { $0.id == sprite.id }
                objects.append(sprite)
            } else {
                sprite = RoomSprite(id: .other(others.count), object: nil, drawn: d)
                others.append(sprite)
            }
            visible.append(sprite)
        }
        let rest = world.objectsInRoom(room).filter { o in !objects.contains { $0.id == .object(o) } }
        objects += rest.map { RoomSprite(id: .object($0), object: world.object($0), drawn: nil) }
        self.objects = objects
        self.others = others
        self.visible = sprites == nil ? objects : visible
        wires = objects.compactMap { s in
            s.object.flatMap { o in world.wire(o.id).map { RoomWire(id: .wire(o.id), object: o.id, wire: $0) } }
        }
    }

    /// The wires of the room's objects (DRAW_WIRES draws them after the robots).
    let wires: [RoomWire]

    /// What the player carries (`World.carried`, the player left out), those
    /// in the room as drawn.
    var carried: [RoomSprite] {
        world.carried.filter { $0 != 0 }.map { o in
            sprite(.object(o)) ?? RoomSprite(id: .object(o), object: world.object(o), drawn: nil)
        }
    }

    func sprite(_ item: RoomItem) -> RoomSprite? {
        switch item {
        case .object: objects.first { $0.id == item }
        case .other(let n): others.indices.contains(n) ? others[n] : nil
        case .wire: nil
        }
    }

    func wire(_ item: RoomItem) -> RoomWire? {
        wires.first { $0.id == item }
    }

    /// The topmost sprite whose 7x16 box contains (x, y).
    func sprite(atX x: Int, y: Int) -> RoomSprite? {
        visible.last { ($0.x ..< $0.x + 7).contains(x) && ($0.y ..< $0.y + 16).contains(y) }
    }

    /// The last wire drawn that passes (x, y) within a unit.
    func wire(atX x: Int, y: Int) -> RoomWire? {
        wires.last { $0.passes(x: x, y: y) }
    }

    /// What a click at (x, y) selects: a sprite, else a wire.
    func item(atX x: Int, y: Int) -> RoomItem? {
        sprite(atX: x, y: y)?.id ?? wire(atX: x, y: y)?.id
    }
}

/// A point of the room in object coordinates: x 0-139, y 0-191 counted from the bottom.
struct RoomPoint: Equatable {
    let x: Int
    let y: Int
}

/// What the current room and the canvas select in the room.
enum RoomItem: Hashable {
    case object(Int)
    /// The nth of the other sprites drawn (`RoomContents.others`).
    case other(Int)
    /// The wire of an object (where it starts).
    case wire(Int)
}

/// A wire of the room, by the object it starts at.  Drawn L-shaped
/// (DRAW_WIRES, WorldFormat.md): horizontal at A's y from ax to bx, then
/// vertical at B's x from ay to by, x and y clamped as the line routines do.
struct RoomWire: Identifiable {
    let id: RoomItem
    let object: Int
    let wire: Wire

    /// A, the corner and B, in object coordinates (y from the bottom).
    var points: [(x: Int, y: Int)] {
        let ax = Engine.clampX(UInt8(wire.ax)), bx = Engine.clampX(UInt8(wire.bx))
        let ay = Engine.clampY(UInt8(wire.ay)), by = Engine.clampY(UInt8(wire.by))
        return [(ax, ay), (bx, ay), (bx, by)]
    }

    /// (x, y) is on the wire, within a unit.
    func passes(x: Int, y: Int) -> Bool {
        let p = points
        func near(_ v: Int, _ a: Int, _ b: Int) -> Bool { (min(a, b) - 1 ... max(a, b) + 1).contains(v) }
        return (abs(y - p[0].y) <= 1 && near(x, p[0].x, p[1].x)) || (abs(x - p[1].x) <= 1 && near(y, p[1].y, p[2].y))
    }
}

/// An object of the room or another sprite drawn there: a row of the
/// current room, and what a click on the canvas selects.
struct RoomSprite: Identifiable {
    let id: RoomItem
    let object: GameObject?
    /// How the draw phase drew it; nil for an object it didn't draw.
    let drawn: DrawnSprite?

    /// Where it was drawn, in object coordinates (y from the bottom).
    var x: Int { drawn?.x ?? object?.x ?? 0 }
    var y: Int { drawn?.y ?? object?.y ?? 0 }

    /// The engine's colour it was drawn in (an object's own when not drawn).
    var colour: Int? {
        if let drawn { return drawn.colour }
        return object?.color
    }

    /// Its 16 rows as drawn (row 0 at the bottom); an object not drawn has its sprite's.
    func rows(in world: World) -> [UInt8] {
        drawn?.rows ?? object.map { Array(world.sprite($0.sprite)) } ?? []
    }

    /// An object's sprite number; for the others the world's sprite number,
    /// an engine sprite by name, or the address.
    func spriteName(in world: World) -> String {
        if let object { return String(format: "sprite $%02X", object.sprite) }
        guard let address = drawn?.address else { return "" }
        let sprites = GameSymbols.address(\.sprites)
        if (sprites ..< sprites + 64 * 16).contains(address), (address - sprites) % 16 == 0 {
            return String(format: "sprite $%02X", (address - sprites) / 16)
        }
        return GameSymbols.name(Sprite.self, at: address, in: world.codeCheck?.variant) ?? String(format: "sprite at $%04X", address)
    }

    /// The draw phase's routine that drew it, by name if it has one.
    func drawnBy(in world: World) -> String? {
        guard let routine = drawn?.routine else { return drawn == nil ? nil : "?" }
        return GameSymbols.name(Routine.self, at: routine, in: world.codeCheck?.variant) ?? String(format: "$%04X", routine)
    }
}
