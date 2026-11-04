// Checks the Mac's mouse as the game's (AppleMouse: a mouse card in slot 4,
// the game's own mouse mode), headless, in Level 1 and every world of the
// kit's and the lab's engines (Robot Anatomy, whose main loop never takes a
// tool, has no soldering):
//
//   plug:   the card in where a tick starts: INPUT_DEVICE 2, SLOT_POINTER
//           $C400, the card's ROM page (ID bytes), the game's set-up run
//           (CLAMPMOUSE: -28..28 across, -60..60 up and down);
//   walk:   the mouse moved 3 units right -- the player 3 right in the tick;
//   pace:   moved 30 right -- the player 7 (LIMIT_MOVE), the rest lost (no
//           move in the next tick); 30 up -- 15 up;
//   keys:   K typed with the card in -- 7 right, as without it;
//   unplug: the card out -- INPUT_DEVICE, SLOT_POINTER and the ROM page as
//           they were;
//   solder: the player put on a free pin of a room with free pins (no chip),
//           the soldering pen taken with S; a click (the button down and up
//           between two ticks) -- a wire started (SOLDER_PIN); the mouse
//           walks the pen to a pin of the other type, a click -- the wire
//           made; then pressed on a free pin and held there for some
//           ticks, the mouse wobbling a unit -- one press: the wire started
//           and still being made after the button is up (no second press);
//           walked to a pin of the other type, a click -- made; a click on
//           a pin with a wire, and one held for 4 ticks -- the wire cut, no
//           new one started (a press held would cut, then start one).
//
// In Level 1 also
//
//   carry:  the player on gate $25 (room $0A) takes it with a click, the
//           mouse moves it 7 right -- the gate with it, its wires too (the
//           game's own CARRY_WIRES, by KEEP_MOVE).
//
// Build and run with mouse_check.sh (compiles this file with the app's sources).
import Foundation
import MOS6502

@main
struct MouseCheck {
    static var failures = 0

    static func fail(_ s: String) {
        failures += 1
        print("  FAIL " + s)
    }

    static func check(_ ok: Bool, _ s: String) {
        if ok { print("  ok   " + s) } else { fail(s) }
    }

    static func main() throws {
        let paths = CommandLine.arguments.dropFirst()
        guard !paths.isEmpty else {
            print("usage: mouse_check SIDE_A.dsk SIDE_B.dsk")
            exit(2)
        }
        var set = DiskSet(version: nil)
        for p in paths {
            let d = try DiskImage(name: (p as NSString).lastPathComponent, data: Data(contentsOf: URL(fileURLWithPath: p)))
            if case .programSide(let side, let version) = d.role {
                set.version = version
                if side == .a { set.sideA = d } else { set.sideB = d }
            }
        }
        let (worlds, errors) = WorldBuilder(disks: set).buildAll()
        errors.forEach { print("build error: \($0)") }
        for world in worlds where world.id == "level1" || world.engine != .levels {
            guard let variant = world.codeCheck?.variant else {
                print("\(world.name): no variant, skipped")
                continue
            }
            print("\(world.name) (\(variant)):")
            try plugAndWalk(world)
            try solder(world, variant)
            if world.id == "level1" { try carry(world, variant) }
        }
        print(failures == 0 ? "all ok" : "\(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: the world

    /// `world` with the player (object 0) in `room` at (x, y), in its object
    /// list (what follows it goes along in the first tick).
    static func playerIn(_ room: Int, at p: (x: Int, y: Int), _ world: World) -> World {
        var mem = world.mem
        let from = Int(mem[\.objRoom, 0])
        let first = GameSymbols.address(\.roomFirstObject), next = GameSymbols.address(\.objNext)
        precondition(mem[first + from] == 0, "the player isn't first in its room")
        if from != room {
            mem[first + from] = mem[next]
            mem[next] = mem[first + room]           // 0 goes first: the lists keep object order
            mem[first + room] = 0
            mem[\.objRoom, 0] = UInt8(room)
        }
        mem[\.objX, 0] = UInt8(p.x)
        mem[\.objY, 0] = UInt8(p.y)
        return world.with(mem: mem, bank1: world.bank1)
    }

    static func address<S: Symbol>(_ s: KeyPath<GameSymbols, S>, _ v: Variant) -> Int {
        GameSymbols.map[keyPath: s].address(v)!
    }

    static func player(_ loop: GameLoop) -> (x: Int, y: Int) {
        (Int(loop.memory[\.objX, 0]), Int(loop.memory[\.objY, 0]))
    }

    /// The mouse moved by (dx, dy) units of the player's move (y up), then a tick.
    static func move(_ loop: GameLoop, _ dx: Int, _ dy: Int) throws {
        loop.moveMouse(dx: dx * AppleMouse.countsPerUnit, dy: -dy * AppleMouse.countsPerUnit)
        try loop.runTick()
    }

    /// A click: the button down and up before the next tick (a press for one tick), and the ticks for it.
    static func click(_ loop: GameLoop) throws {
        loop.mouseButton(down: true)
        loop.mouseButton(down: false)
        for _ in 0 ..< 3 { try loop.runTick() }
    }

    /// The mouse walks the player to `p`, the rest of the way each tick; false if it doesn't get there.
    @discardableResult
    static func walk(_ loop: GameLoop, to p: (x: Int, y: Int), ticks: Int = 40) throws -> Bool {
        for _ in 0 ..< ticks {
            let at = player(loop)
            if at == p { return true }
            try move(loop, p.x - at.x, p.y - at.y)
        }
        return player(loop) == p
    }

    static func pinType(_ o: Int, _ mem: [UInt8], _ v: Variant) -> UInt8 {
        mem[address(\.pinTypes, v) + Int(mem[\.objSprite, o]) & 0x3F]
    }

    struct Wire: Equatable {
        let to: Int, a: [Int], b: [Int]
    }

    /// Every wire: from, to, and the ends.
    static func wires(_ mem: [UInt8], _ v: Variant) -> [Int: Wire] {
        let to = address(\.wireTo, v), ax = address(\.wireAX, v), ay = address(\.wireAY, v)
        let bx = address(\.wireBX, v), by = address(\.wireBY, v)
        var w: [Int: Wire] = [:]
        for o in 0 ..< 256 where mem[to + o] != 0 {
            w[o] = Wire(to: Int(mem[to + o]), a: [Int(mem[ax + o]), Int(mem[ay + o])], b: [Int(mem[bx + o]), Int(mem[by + o])])
        }
        return w
    }

    static func connects(_ mem: [UInt8], _ v: Variant, _ p: Int, _ q: Int) -> Bool {
        let w = wires(mem, v)
        return w[p]?.to == q || w[q]?.to == p
    }

    /// Where the player stands with the pen so that the tip's middle (the
    /// tip linked to the player at (0, 0), its middle + (2, 4)) is on pin
    /// `o`: on its sprite's pixel nearest its pin (PIN_DX/DY).
    static func spot(on o: Int, _ mem: [UInt8], _ v: Variant) -> (x: Int, y: Int) {
        let sprite = Int(mem[\.objSprite, o]) & 0x3F
        let px = Int(mem[address(\.pinDX, v) + sprite]), py = Int(mem[address(\.pinDY, v) + sprite])
        let rows = (0 ..< 16).map { mem[GameSymbols.address(\.sprites) + sprite * 16 + $0] }
        var best = (x: px, y: py), distance = Int.max
        for row in 0 ..< 16 {
            for column in 0 ..< 7 where rows[row] >> (6 - column) & 1 != 0 {
                let d = (column - px) * (column - px) + (row - py) * (row - py)
                if d < distance { (best, distance) = ((column, row), d) }
            }
        }
        return (Int(mem[\.objX, o]) + best.x - 2, Int(mem[\.objY, o]) + best.y - 4)
    }

    /// A pin of type 1 and one of type 2 in `room` with no wire from or to
    /// them (SOLDER_WIRE joins only pins of different types).
    static func freePins(in room: Int, _ mem: [UInt8], _ v: Variant) -> (Int, Int)? {
        let w = wires(mem, v)
        let wired = Set(w.keys).union(w.values.map(\.to))
        func free(_ type: UInt8) -> Int? {
            (1 ..< 0xFC).first { o in Int(mem[\.objRoom, o]) == room && !wired.contains(o) && pinType(o, mem, v) == type }
        }
        guard let p = free(1), let q = free(2) else { return nil }
        return (p, q)
    }

    /// The objects that follow `root` through OBJ_LINK, and itself.
    static func chain(_ root: Int, _ mem: [UInt8]) -> [Int] {
        (0 ..< 255).filter { o in
            var o = o
            for _ in 0 ..< 255 {
                if o == root { return true }
                let link = Int(mem[\.objLink, o])
                if link == World.noObject || link == o { return false }
                o = link
            }
            return false
        }
    }

    /// The wire ends in the boxes of `objects` (where their pins are).
    static func ends(on objects: [Int], _ mem: [UInt8], _ v: Variant) -> [(wire: Int, b: Bool)] {
        var found: [(Int, Bool)] = []
        for (o, w) in wires(mem, v) {
            for (end, isB) in [(w.a, false), (w.b, true)] {
                if objects.contains(where: { g in
                    Int(mem[\.objRoom, g]) == Int(mem[\.objRoom, o])
                        && (Int(mem[\.objX, g]) ..< Int(mem[\.objX, g]) + 7).contains(end[0])
                        && (Int(mem[\.objY, g]) ..< Int(mem[\.objY, g]) + 16).contains(end[1])
                }) { found.append((o, isB)) }
            }
        }
        return found
    }

    /// The wire ends of `before` on `objects` moved by `d` in `after`, the others where they were.
    static func checkEnds(_ before: [UInt8], _ after: [UInt8], _ v: Variant, on objects: [Int], by d: (Int, Int), _ what: String) {
        let on = ends(on: objects, before, v)
        let w = wires(before, v), moved = wires(after, v)
        var ok = !on.isEmpty
        for e in on {
            let old = e.b ? w[e.wire]!.b : w[e.wire]!.a
            let new = moved[e.wire].map { e.b ? $0.b : $0.a }
            ok = ok && new == [old[0] + d.0, old[1] + d.1]
        }
        let onIDs = Set(on.map(\.wire))
        let others = w.keys.filter { !onIDs.contains($0) }
        let stay = others.allSatisfy { moved[$0] == w[$0] }
        check(ok && stay, "\(what): \(on.count) wire ends moved by \(d), the other \(others.count) wires stay")
    }

    // MARK: the checks

    static func plugAndWalk(_ world: World) throws {
        let loop = try GameScreen(world: world).loop(room: nil)
        try loop.runTick()
        let before = loop.memory
        let slotPointer = GameSymbols.address(\.slotPointer)
        let rom = AppleMouse.rom
        loop.mouse = true
        try loop.runTick()
        var mem = loop.memory
        check(mem[\.inputDevice] == 2 && mem[\.slotPointer] == rom && mem[rom + 0x0C] == 0x20 && mem[rom + 0xFB] == 0xD6
              && mem[\.mouseSlot] == UInt8(rom >> 8) && mem[\.mouseSlot16] == UInt8(AppleMouse.slot << 4),
              "plug: INPUT_DEVICE 2, SLOT_POINTER \(hex(mem[\.slotPointer])), the card's ROM, MOUSE_SLOT \(hex(Int(mem[\.mouseSlot])))")
        let clamp = loop.devices.mouse?.clamp
        check(clamp?.x == -28 ... 28 && clamp?.y == -60 ... 60,
              "plug: the game's CLAMPMOUSE: across \(clamp.map { "\($0.x)" } ?? "-"), up and down \(clamp.map { "\($0.y)" } ?? "-")")

        var at = player(loop)
        try move(loop, 3, 0)
        check(player(loop) == (at.x + 3, at.y), "walk: 3 right from \(at): at \(player(loop))")
        at = player(loop)
        try move(loop, 30, 0)
        let paced = player(loop)
        try loop.runTick()
        check(paced == (at.x + 7, at.y) && player(loop) == paced,
              "pace: 30 right from \(at): at \(paced) (7), then no more: \(player(loop))")
        at = player(loop)
        try move(loop, 0, 30)
        check(player(loop) == (at.x, at.y + 15), "pace: 30 up from \(at): at \(player(loop)) (15)")
        at = player(loop)
        loop.devices.type(0xCB)                     // K: right
        try loop.runTick()
        check(player(loop) == (at.x + 7, at.y), "keys: K with the card in, from \(at): at \(player(loop))")

        loop.mouse = false
        try loop.runTick()
        mem = loop.memory
        check(mem[\.inputDevice] == before[\.inputDevice] && mem[slotPointer] == before[slotPointer]
              && mem[slotPointer + 1] == before[slotPointer + 1] && Array(mem[rom ..< rom + 0x100]) == Array(before[rom ..< rom + 0x100])
              && loop.devices.mouse == nil,
              "unplug: INPUT_DEVICE \(hex(Int(mem[\.inputDevice]))), SLOT_POINTER, the ROM page as before")
    }

    static func solder(_ world: World, _ v: Variant) throws {
        // Not a room with a chip: its pins count as wired (SOLDER_WIRE's $F78C), the check doesn't see that.
        let mem0 = world.mem
        guard let room = (0 ..< World.roomCount).first(where: { r in
            world.codeRooms[r] == nil && freePins(in: r, mem0, v) != nil
                && !(1 ..< 0xFC).contains { Int(mem0[\.objRoom, $0]) == r && pinType($0, mem0, v) == 0xF0 }
        }), let (p, q) = freePins(in: room, mem0, v) else { return fail("solder: no room with free pins of both types") }
        let loop = try GameScreen(world: playerIn(room, at: spot(on: p, mem0, v), world)).loop(room: nil)
        try loop.runTick()
        loop.devices.type(0xD3)                     // S: the soldering pen
        try loop.runTick()
        try loop.runTick()
        guard loop.memory[address(\.toolMode, v)] == 0xFD else {       // TOOL_MODE: the soldering pen
            print("  --   S takes no pen (the main loop has no TAKE_TOOL): no soldering here")
            return
        }
        print("  room \(hex(room)), the pen in hand")
        loop.mouse = true
        try loop.runTick()
        let solderPin = address(\.solderPin, v)
        try click(loop)
        check(Int(loop.memory[solderPin]) == p, "click on pin \(hex(p)): a wire started (SOLDER_PIN \(hex(Int(loop.memory[solderPin]))))")
        guard try walk(loop, to: spot(on: q, loop.memory, v)) else {
            return fail("walk to pin \(hex(q)): the player stopped at \(player(loop))")
        }
        try click(loop)
        check(loop.memory[solderPin] == 0 && connects(loop.memory, v, p, q), "walked to pin \(hex(q)), a click: the wire made")

        if let (p, q) = freePins(in: room, loop.memory, v) {
            if try walk(loop, to: spot(on: p, loop.memory, v)) {
                loop.mouseButton(down: true)
                try move(loop, 0, 1)
                try move(loop, 0, -1)
                try loop.runTick()
                loop.mouseButton(down: false)
                for _ in 0 ..< 3 { try loop.runTick() }
                check(Int(loop.memory[solderPin]) == p,
                      "held: pressed on pin \(hex(p)) for 3 ticks, the mouse wobbling, let go: one press, the wire still being made")
                if try walk(loop, to: spot(on: q, loop.memory, v)) {
                    try click(loop)
                    check(loop.memory[solderPin] == 0 && connects(loop.memory, v, p, q), "held: walked to pin \(hex(q)), a click: the wire made")
                } else {
                    print("  --   held: the player can't get to pin \(hex(q)) (stopped at \(player(loop)))")
                }
            } else {
                print("  --   held: the player can't get to pin \(hex(p)) (stopped at \(player(loop)))")
            }
        } else {
            print("  --   no more free pins for the held press")
        }

        let mem = loop.memory
        guard let (o, wire) = wires(mem, v).first(where: { Int(mem[\.objRoom, $0.key]) == room && (1 ... 2).contains(pinType($0.key, mem, v)) })
        else { return fail("cut: no pin with a wire in the room") }
        guard try walk(loop, to: spot(on: o, mem, v)) else {
            return fail("cut: the player can't get to pin \(hex(o)) (stopped at \(player(loop)))")
        }
        try click(loop)
        check(!connects(loop.memory, v, o, wire.to) && loop.memory[solderPin] == 0,
              "cut: a click on pin \(hex(o)) (wired to \(hex(wire.to))): the wire cut, no new one started (SOLDER_PIN \(hex(Int(loop.memory[solderPin]))))")
        // Held for some ticks: still one press (the game takes a press held
        // on a pin with a wire as a cut, then, the pin free, a new wire).
        let mem2 = loop.memory
        if let (o2, wire2) = wires(mem2, v).first(where: { Int(mem2[\.objRoom, $0.key]) == room && (1 ... 2).contains(pinType($0.key, mem2, v)) }),
           try walk(loop, to: spot(on: o2, mem2, v)) {
            loop.mouseButton(down: true)
            for _ in 0 ..< 4 { try loop.runTick() }
            loop.mouseButton(down: false)
            try loop.runTick()
            check(!connects(loop.memory, v, o2, wire2.to) && loop.memory[solderPin] == 0,
                  "cut: pressed on pin \(hex(o2)) (wired to \(hex(wire2.to))) for 4 ticks: the wire cut, no new one started (SOLDER_PIN \(hex(Int(loop.memory[solderPin]))))")
        }
    }

    /// Level 1's player takes gate $25 in room $0A with a click and the mouse moves it 7 to the right.
    static func carry(_ world: World, _ v: Variant) throws {
        let gate = 0x25, room = 0x0A
        let at = (Int(world.mem[\.objX, gate]), Int(world.mem[\.objY, gate]))
        let loop = try GameScreen(world: playerIn(room, at: at, world)).loop(room: nil)
        loop.mouse = true
        try loop.runTick()
        try click(loop)
        guard Int(loop.memory[\.heldObject]) == gate else {
            return fail("carry: a click didn't take gate \(hex(gate)) (HELD_OBJECT \(hex(Int(loop.memory[\.heldObject]))))")
        }
        let before = loop.memory
        let x = Int(before[\.objX, 0]), gx = Int(before[\.objX, gate])
        try move(loop, 7, 0)
        let after = loop.memory
        check(Int(after[\.objX, 0]) == x + 7 && Int(after[\.objX, gate]) == gx + 7,
              "carry: a click took gate \(hex(gate)), the mouse moved it 7 right (\(gx) → \(after[\.objX, gate]))")
        checkEnds(before, after, v, on: chain(gate, before), by: (7, 0), "carry: the gate's wires")
    }
}

func hex(_ v: Int) -> String { String(format: "$%02X", v) }
