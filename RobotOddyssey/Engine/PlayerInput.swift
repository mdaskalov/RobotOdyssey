import Foundation

/// Native port of the engine's input: READ_INPUT ($A90C), the first call of
/// every world's main loop, and in the Robotropolis levels the three routines
/// right after it that use its result.
///
/// READ_INPUT reads the keyboard (one key per tick) and the joystick, turns
/// them into a joystick position ($9C39 x, $9C3A y, $80 = centre), the move
/// (MOVE_DX, MOVE_DY) and the buttons (BUTTON_A, BUTTON_B), and moves the
/// player, object 0: stopped at walls (unless $9C30 is 0), kept on the screen,
/// into the next room across an edge (ObjectMotion).  A key that is not a
/// movement key stays in LAST_KEY for the world's own code (`?`, Esc, the
/// tools...).  Device $9C3E: 0 keyboard, 1 joystick, 2 mouse (not ported: the
/// routine declines and the original code reads the mouse card).
///
/// Keyboard: each world sets ten keys at $9C13 (all worlds: I M J K up, down,
/// left, right; Ctrl-I M J K slowly; space button B), each a joystick
/// position or a button, so a key press is one step: 7 across, 16 up or down,
/// 1 slowly.  Joystick: the paddle timers are measured by counting rounds of a
/// 24-cycle loop, at most 127; with the keyboard the paddles are still read
/// every tick and the first change switches to the joystick, a key back to
/// the keyboard.
enum PlayerInput {
    /// The code `readInput` replaces (engine main, the same in all worlds and
    /// versions), without its variables; it calls ObjectMotion's.
    static let code = [0xA90C ..< 0xA934, 0xA97D ..< 0xA9D2, 0xA9D4 ..< 0xAAC9, 0xAACB ..< 0xAB71,
                       0xABA1 ..< 0xABBE, 0xAC09 ..< 0xAC12]
    static let fingerprint = "b72211c0bd7317802aac99def68c6837"
    static let entry: UInt16 = 0xA90C

    static func matches(_ mem: [UInt8]) -> Bool {
        ObjectMotion.matches(mem) && DiskImage.md5(code.flatMap { mem[$0] }) == fingerprint
    }

    // Variables and tables of the code.
    static let mouseMoved = 0xA909
    static let lastPaddleY = 0xA90A, lastPaddleX = 0xA90B
    static let paddleX = 0xAAC9, paddleY = 0xAACA
    static let stickX = 0x9C39, stickY = 0x9C3A
    static let device = 0x9C3E
    static let wallsOn = 0x9C30
    static let caseMask = 0x9C21
    static let movementKeys = 0x9C13
    static let keyMoveX = 0xAB71, keyMoveY = 0xAB81
    static let stickMoveX = 0xABBE, stickMoveY = 0xABCE

    /// READ_INPUT ($A90C).
    static func readInput(_ s: inout NativeState) -> Bool {
        guard s.ram[device] != 2 else { return false }
        s.ram[mouseMoved] = 0
        readDevice(&s)
        s.registers.x = 0xFF
        s.registers.y = 0xFF
        ObjectMotion.limitMove(&s.ram, &s.registers)
        s.ram[RAM.currentObject] = 0
        if s.registers.nz(s.ram[wallsOn]) != 0 {
            ObjectMotion.stopAtWalls(&s.ram, &s.registers)
        }
        ObjectMotion.keepOnScreen(&s.ram, &s.registers)
        ObjectMotion.moveObject(&s.ram, &s.registers)
        return true
    }

    /// $A97D: the move and the buttons from the keyboard or the joystick.
    private static func readDevice(_ s: inout NativeState) {
        s.ram[RAM.moveDX] = 0
        s.ram[RAM.moveDY] = 0
        clearButtons(&s.ram)
        let key = readKey(&s)
        if s.ram[device] == 0 {
            readJoystick(&s)
            if s.ram[paddleY] == s.ram[lastPaddleY] && s.ram[paddleX] == s.ram[lastPaddleX] {
                keyAsStick(&s.ram)
                move(byKey: &s.ram)
            } else {
                s.ram[device] = 1
                move(byStick: &s.ram)
            }
        } else if key == 0 {
            readJoystick(&s)
            move(byStick: &s.ram)
        } else {
            s.ram[device] = 0
            readJoystick(&s)
            s.ram[lastPaddleX] = s.ram[paddleX]
            s.ram[lastPaddleY] = s.ram[paddleY]
            keyAsStick(&s.ram)
            move(byKey: &s.ram)
        }
    }

    /// $AA25: LAST_KEY = the key typed, or 0; lower-case letters as capitals.
    private static func readKey(_ s: inout NativeState) -> UInt8 {
        var key = s.devices.key
        if key & 0x80 == 0 {
            key = 0
        } else {
            s.devices.key &= 0x7F
            if (0xE1 ..< 0xFB).contains(key) { key &= s.ram[caseMask] }
        }
        s.ram[RAM.lastKey] = key
        return key
    }

    /// $AA40: the key as a joystick position (or a button); a movement key is
    /// used up.  The ten keys at $9C13: up, down, left, right, button A,
    /// button B, slowly up, down, left, right.
    private static func keyAsStick(_ m: inout RAM) {
        m[stickX] = 0x80
        m[stickY] = 0x80
        let actions = [(stickY, 0xFF), (stickY, 0x00), (stickX, 0x00), (stickX, 0xFF), (RAM.buttonA, 1),
                       (RAM.buttonB, 1), (stickY, 0xC0), (stickY, 0x3F), (stickX, 0x3F), (stickX, 0xC0)]
        let key = m[RAM.lastKey]
        guard let i = actions.indices.first(where: { m[movementKeys + $0] == key }) else { return }
        m[actions[i].0] = UInt8(actions[i].1)
        m[RAM.lastKey] = 0
    }

    /// $AB54 and $ABA1: the move for the joystick position, by the keyboard's
    /// or the joystick's table (16 steps of 16 positions each way).
    private static func move(byKey m: inout RAM) { move(&m, tables: keyMoveX, keyMoveY) }
    private static func move(byStick m: inout RAM) { move(&m, tables: stickMoveX, stickMoveY) }

    private static func move(_ m: inout RAM, tables x: Int, _ y: Int) {
        m[RAM.moveDX] = m[x + Int(m[stickX] >> 4)]
        m[RAM.moveDY] = m[y + Int(m[stickY] >> 4)]
    }

    /// $AC09.
    private static func clearButtons(_ m: inout RAM) {
        m[RAM.buttonA] = 0
        m[RAM.buttonB] = 0
    }

    /// $AACB: the paddle counts, doubled, in $AAC9/$AACA and as the joystick
    /// position ($9C3A upside down), and the buttons: button 1 alone is
    /// BUTTON_A, button 0 alone BUTTON_B.
    private static func readJoystick(_ s: inout NativeState) {
        s.devices.strobe = s.cycles
        let counts = paddleCounts(s.devices)
        s.ram[paddleX] = counts.x << 1
        s.ram[paddleY] = counts.y << 1
        s.ram[stickX] = counts.x << 1
        s.ram[stickY] = counts.y << 1 ^ 0xFF
        clearButtons(&s.ram)
        let b0 = s.devices.buttons[0], b1 = s.devices.buttons[1]
        if b0 != b1 { s.ram[b1 ? RAM.buttonA : RAM.buttonB] &+= 1 }
    }

    /// The paddle counts $AACB's loop reaches: it reads paddle 0 at 14 and
    /// paddle 1 at 23 cycles after the strobe, every 24 cycles, up to 127
    /// rounds.  Once paddle 0 has run out at round k, it reads paddle 1 at
    /// 25 + 24j (j from k); once paddle 1 has, paddle 0 at 17 + 24j (j from k + 1).
    static func paddleCounts(_ d: InputDevices) -> (x: UInt8, y: UInt8) {
        func running(_ paddle: Int, _ cycles: Int) -> Bool { d.paddleRunning(paddle, after: UInt64(cycles)) }
        for k in 0 ..< 128 {
            if !running(0, 14 + 24 * k) {
                let y = (k ..< 128).first { !running(1, 25 + 24 * $0) } ?? 127
                return (UInt8(k), UInt8(y))
            }
            if !running(1, 23 + 24 * k) {
                let x = (k + 1 ..< 128).first { !running(0, 17 + 24 * $0) } ?? 127
                return (UInt8(x), UInt8(k))
            }
        }
        return (127, 127)
    }

    // MARK: the levels' engine ($D000-$FFFF)

    /// What the Robotropolis levels do right after READ_INPUT: animate the
    /// player's sprite, turn the buttons into the grab state, keep the move.
    struct LevelRoutines {
        let walk, grab, keepMove: UInt16
        /// MD5 of the three routines' code, per version.
        let fingerprint: String

        var code: [Range<Int>] {
            [Int(walk) ..< Int(walk) + 0x5B, Int(grab) ..< Int(grab) + 0x1A, Int(keepMove) ..< Int(keepMove) + 0x0D]
        }

        static let v11 = LevelRoutines(walk: 0xDFA3, grab: 0xBEBC, keepMove: 0xFE18,
                                       fingerprint: "3489fd2d64735a40dbb68ea6a37ee176")
        static let v10 = LevelRoutines(walk: 0xDFA4, grab: 0xBEBC, keepMove: 0xFE18,
                                       fingerprint: "275c86f67c01690f1d3cb557f71858a2")

        static func find(in mem: [UInt8]) -> LevelRoutines? {
            [v11, v10].first { DiskImage.md5($0.code.flatMap { mem[$0] }) == $0.fingerprint }
        }
    }

    static let walkFrame = 0x8ED7, walkTemp = 0x8ED6, playerSprites = 0xBF30
    static let grabState = 0x8E3E
    static let keptDX = 0x8E88, keptDY = 0x8E89

    /// $DFA3: the player's sprite (sprite 0) for the move: two steps for each
    /// of up, down, right, left (frames 0-7 at $BF30), the larger part of the
    /// move choosing, a new step each tick.
    static func walk(_ m: inout RAM, _ r: inout Registers) {
        let dx = m[RAM.moveDX], dy = m[RAM.moveDY]
        r.x = dx
        r.a = r.nz(dx | dy)
        guard r.a != 0 else { return }
        m[walkTemp] = r.magnitude(dx)
        r.x = dy
        r.compare(r.magnitude(dy), m[walkTemp])
        let frame = m[walkFrame]
        var step: UInt8
        if r.carry {
            r.x = dy
            step = dy & 0x80 == 0 ? frame & 1 : frame & 3 | 2
        } else {
            r.x = dx
            step = dx & 0x80 == 0 ? frame & 5 | 4 : frame | 6
        }
        step ^= 1
        m[walkFrame] = step
        let first = Int(step << 4)
        for i in 0 ..< 16 { m[0x6A00 + i] = m[playerSprites + first + i] }
        r.carry = false
        _ = r.adc(step << 4, 0x0F)
        r.x = UInt8((first - 1) & 0xFF)
        r.a = m[playerSprites + first]
        r.y = r.nz(0xFF)
    }

    /// $BEBC: the grab state from the buttons: 0 with none (or both), 1 on a
    /// new press; otherwise as it is (the grab code sets it to 2 once done).
    static func grabButton(_ m: inout RAM, _ r: inout Registers) {
        guard m[RAM.buttonA] != m[RAM.buttonB] else {
            r.a = r.nz(0)
            m[grabState] = 0
            return
        }
        r.a = r.nz(m[grabState])
        guard r.a == 0 else { return }
        r.a = r.nz(1)
        m[grabState] = 1
    }

    /// $FE18: keeps this tick's move at $8E88/$8E89.
    static func keepMove(_ m: inout RAM, _ r: inout Registers) {
        m[keptDX] = m[RAM.moveDX]
        r.a = r.nz(m[RAM.moveDY])
        m[keptDY] = r.a
    }
}
