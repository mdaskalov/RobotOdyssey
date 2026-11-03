import Foundation
import MOS6502

/// The canvas's mouse in the running game: press on something and drag it.
/// No Apple did that (the game's own mouse mode, INPUT_DEVICE 2, moves the
/// player by the mouse's motion, Docs/Engine.md "Input"), so it changes the
/// game (Docs/Frontends.md "Input"), as far as it goes with the game's own
/// means, where each tick starts (`GameLoop`):
///
/// * **The player** (with what it carries) walks after the pointer on the
///   joystick the game reads: each tick the paddles go to the position whose
///   move in the game's joystick table (STICK_MOVE_X/Y) comes nearest the
///   target without passing it, and READ_INPUT moves the player as ever, 7
///   across and 15 up or down at most, stopped by walls, through exits, with
///   its walking sprite and what it holds.  Through an exit the target goes
///   along into the next room; let go, the player walks on to it.
/// * **An object** (the root of its OBJ_LINK chain: a robot's body, a gate's
///   base; the rest follows in MOVE_LINKED_OBJECTS) goes to the target at
///   once, in the steps the game's mouse mode moves the player by
///   (`Engine.moveByHand`), so it stays an object of its room like any other.
///   A wall in the way drops it there, so does an exit (it lies on the other
///   side), and the player taking it.
///
/// The target is where the object was as the drag started moved by the
/// pointer's motion since, in object coordinates of `room`.
nonisolated struct MouseHand {
    enum Holding: Equatable {
        case player
        /// An object, the root of its OBJ_LINK chain.
        case object(Int)
    }

    /// How far `Engine.moveByHand` got.
    enum Move { case there, underway, stopped, crossed }

    let holding: Holding
    /// The room the target counts in.
    private(set) var room: Int
    /// Where the object was as the drag started, in `room`'s coordinates.
    private var origin: (x: Double, y: Double)
    /// The pointer's motion since, in object units (y up).
    var moved: (x: Double, y: Double) = (0, 0)
    /// The mouse button is up: the player walks on to the target, an object is put there.
    var released = false
    /// Press the game's button once the player is there (a click on it while it walks).
    var press = false
    /// Where the player was as the last tick started, and whether the stick was off the centre since.
    private var last: (room: Int, x: Int, y: Int)
    fileprivate var steered = false

    /// The most steps an object takes in a tick: across the room and more.
    static let maxSteps = 40

    init(holding: Holding, room: Int, x: Int, y: Int) {
        self.holding = holding
        self.room = room
        origin = (Double(x), Double(y))
        last = (room, x, y)
    }

    var target: (x: Int, y: Int) {
        (Int((origin.x + moved.x).rounded()), Int((origin.y + moved.y).rounded()))
    }

    /// The player is at `at` as a tick starts: across an edge from the room
    /// it was in, the target goes along into the room it is in now, as
    /// MOVE_OBJECT_XY carries coordinates.  Returns its move since the last
    /// tick; nil if it got there otherwise (a robot's inside, the world's
    /// code) or moved more than a step.
    mutating func follow(_ at: (room: Int, x: Int, y: Int), in mem: [UInt8]) -> (dx: Int, dy: Int)? {
        var dx = at.x - last.x, dy = at.y - last.y
        if at.room != last.room {
            let from = last.room
            if dx < -0x43, Int(mem[\.roomRight, from]) == at.room {
                origin.x -= 0x86
                dx += 0x86
            } else if dx > 0x43, Int(mem[\.roomLeft, from]) == at.room {
                origin.x += 0x86
                dx -= 0x86
            } else if dy < -0x58, Int(mem[\.roomUp, from]) == at.room {
                origin.y -= 0xB1
                dy += 0xB1
            } else if dy > 0x58, Int(mem[\.roomDown, from]) == at.room {
                origin.y += 0xB1
                dy -= 0xB1
            } else {
                return nil
            }
            room = at.room
        }
        last = at
        return abs(dx) <= 7 && abs(dy) <= 16 ? (dx, dy) : nil
    }

    /// For each of the 16 joystick positions READ_JOYSTICK tells apart
    /// (STICK_X >> 4 and STICK_Y >> 4, the index into the move tables), a
    /// paddle position that reads as it: the middle of those that do, the
    /// other paddle centred.
    static let paddles: (x: [UInt8], y: [UInt8]) = {
        var x = [[UInt8]](repeating: [], count: 16), y = x
        var devices = InputDevices()
        for p in 0 ... 255 {
            devices.joystick = (UInt8(p), InputDevices.centre.y)
            x[Int((Engine.paddleCounts(devices).x << 1) >> 4)].append(UInt8(p))
            devices.joystick = (InputDevices.centre.x, UInt8(p))
            y[Int((Engine.paddleCounts(devices).y << 1 ^ 0xFF) >> 4)].append(UInt8(p))
        }
        func middle(_ ps: [UInt8]) -> UInt8 { ps.isEmpty ? 128 : ps[ps.count / 2] }
        return (x.map(middle), y.map(middle))
    }()

    /// The joystick position whose move in `table` (16 signed bytes) is the
    /// largest toward `d` that doesn't pass it; the centre for 0.
    static func stick(toward d: Int, in table: ArraySlice<UInt8>) -> Int {
        var best = 8, size = 0
        for (i, byte) in table.enumerated() {
            let v = Int(Int8(bitPattern: byte))
            if v.signum() == d.signum(), abs(v) <= abs(d), abs(v) > size {
                best = i
                size = abs(v)
            }
        }
        return best
    }
}

nonisolated extension Machine {
    /// Where a tick starts (`GameLoop`): the hand moves what it holds, or
    /// steers the player; returns it as it goes on, nil once it lets go.
    func apply(_ hand: MouseHand) -> MouseHand? {
        guard variant != nil else { return nil }
        switch hand.holding {
        case .player: return steer(hand)
        case .object(let o): return move(o, hand)
        }
    }

    /// The joystick for the player's next step to the target.  Let go, it
    /// is done there, or where the player didn't move with the stick off the
    /// centre (a wall, a sentry holding it, a key typed).
    private func steer(_ hand: MouseHand) -> MouseHand? {
        var hand = hand
        let mem = cpu.mem
        let at = (room: Int(mem[\.objRoom, 0]), x: Int(mem[\.objX, 0]), y: Int(mem[\.objY, 0]))
        guard let step = hand.follow(at, in: mem) else { return letGo(hand) }
        let stuck = hand.steered && step == (0, 0)
        let target = hand.target
        let dx = target.x - at.x, dy = target.y - at.y
        if hand.released && (stuck || dx == 0 && dy == 0) { return letGo(hand) }
        let tableX = mem[GameSymbols.address(\.stickMoveX) ..< GameSymbols.address(\.stickMoveX) + 16]
        let tableY = mem[GameSymbols.address(\.stickMoveY) ..< GameSymbols.address(\.stickMoveY) + 16]
        let x = MouseHand.stick(toward: dx, in: tableX), y = MouseHand.stick(toward: dy, in: tableY)
        devices.joystick = (MouseHand.paddles.x[x], MouseHand.paddles.y[y])
        hand.steered = tableX[tableX.startIndex + x] != 0 || tableY[tableY.startIndex + y] != 0
        return hand
    }

    /// The joystick let go (it stays plugged in), and the button pressed if a click waits for it.
    private func letGo(_ hand: MouseHand) -> MouseHand? {
        devices.joystick = InputDevices.centre
        if hand.press { devices.click() }
        return nil
    }

    /// The object moved to the target (`Engine.moveByHand`); done once it is
    /// let go, dropped, or the player has it (or it isn't where it was).
    private func move(_ object: Int, _ hand: MouseHand) -> MouseHand? {
        let before = cpu.mem
        guard Int(before[\.objRoom, object]) == hand.room, Int(before[\.heldObject]) != object else { return nil }
        let target = hand.target
        let registers = (cpu.a, cpu.x, cpu.y, cpu.p)
        var moved = MouseHand.Move.there
        call { e in
            moved = e.moveByHand(UInt8(object), toX: target.x, y: target.y)
            return true
        }
        (cpu.a, cpu.x, cpu.y, cpu.p) = registers
        restore(from: before)
        return moved == .stopped || moved == .crossed || hand.released ? nil : hand
    }

    /// What the hand may change: where the objects are, and the rooms' object lists.
    private static let objectTables: [Range<Int>] = [
        (\GameSymbols.objNext, 256), (\.objRoom, 256), (\.objX, 256), (\.objY, 256), (\.roomFirstObject, World.roomCount),
    ].map { GameSymbols.address($0.0) ..< GameSymbols.address($0.0) + $0.1 }

    /// Puts back what moving left elsewhere than in the object tables (the
    /// move, CUR_OBJECT, the wall tests' temporaries...): the tick goes on as
    /// it would have, but for where objects are.
    private func restore(from before: [UInt8]) {
        let after = cpu.mem
        for a in after.indices where after[a] != before[a] && !Machine.objectTables.contains(where: { $0.contains(a) }) {
            cpu.mem[a] = before[a]
        }
    }
}

nonisolated extension Engine {
    /// Moves `object` toward (x, y) of its room in the steps the game's
    /// mouse mode moves the player by (READ_DEVICE at $A9FB): LIMIT_MOVE to 7
    /// across and 15 up or down, STOP_AT_WALLS, KEEP_ON_SCREEN, MOVE_OBJECT.
    /// An object lying on a wall moves freely until it is off it
    /// (STOP_AT_WALLS stops every move there).  Stops where a wall stops a
    /// step (`stopped`), or once it is in another room (`crossed`).
    mutating func moveByHand(_ object: UInt8, toX x: Int, y: Int) -> MouseHand.Move {
        let room = m.objRoom[object]
        for _ in 0 ..< MouseHand.maxSteps {
            let dx = x - Int(m.objX[object]), dy = y - Int(m.objY[object])
            guard dx != 0 || dy != 0 else { return .there }
            m.moveDX = UInt8(bitPattern: Int8(clamping: dx))
            m.moveDY = UInt8(bitPattern: Int8(clamping: dy))
            r.x = 7
            r.y = 15
            limitMove()
            let wanted = (m.moveDX, m.moveDY)
            m.currentObject = object
            if !onWall() { stopAtWalls() }
            let stopped = (m.moveDX, m.moveDY) != wanted
            keepOnScreen()
            moveObject()
            if m.objRoom[object] != room { return .crossed }
            if stopped { return .stopped }
        }
        return .underway
    }

    /// CUR_OBJECT lies on a wall: TEST_MOVE finds one where it is.
    private mutating func onWall() -> Bool {
        m.tryDX = 0
        m.tryDY = 0
        return testMove() & Engine.wallHit != 0
    }
}
