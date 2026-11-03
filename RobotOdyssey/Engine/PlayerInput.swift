import Foundation

/// Native port of the engine's input: READ_INPUT ($A90C), the first call of
/// every world's main loop, and in the Robotropolis levels the three routines
/// right after it that use its result.
///
/// READ_INPUT reads the keyboard (one key per tick) and the joystick, turns
/// them into a joystick position (STICK_X, STICK_Y, $80 = centre), the move
/// (MOVE_DX, MOVE_DY) and the buttons (BUTTON_A, BUTTON_B), and moves the
/// player, object 0: stopped at walls (unless WALLS_ON is 0), kept on the
/// screen, into the next room across an edge (ObjectMotion).  A key that is
/// not a movement key stays in LAST_KEY for the world's own code (`?`, Esc,
/// the tools...).  INPUT_DEVICE: 0 keyboard, 1 joystick, 2 mouse (not ported:
/// the routine declines and the original code reads the mouse card).
///
/// Keyboard: each world sets ten keys in MOVE_KEYS (all worlds: I M J K up,
/// down, left, right; Ctrl-I M J K slowly; space button B), each a joystick
/// position or a button, so a key press is one step: 7 across, 16 up or down,
/// 1 slowly.  Joystick: the paddle timers are measured by counting rounds of
/// a 24-cycle loop, at most 127; with the keyboard the paddles are still read
/// every tick and the first change switches to the joystick, a key back to
/// the keyboard.
nonisolated extension Engine {
    /// READ_INPUT ($A90C); declines for the mouse.
    mutating func readInput() -> Bool {
        guard m.inputDevice != 2 else { return false }
        m.mouseMoved = 0
        readDevice()
        r.x = 0xFF
        r.y = 0xFF
        limitMove()
        m.currentObject = 0
        if r.nz(m.wallsOn) != 0 { stopAtWalls() }
        keepOnScreen()
        moveObject()
        return true
    }

    /// READ_DEVICE ($A97D): the move and the buttons from the keyboard or the joystick.
    private mutating func readDevice() {
        m.moveDX = 0
        m.moveDY = 0
        clearButtons()
        let key = readKey()
        if m.inputDevice == 0 {
            readJoystick()
            if m.paddleY == m.lastPaddleY && m.paddleX == m.lastPaddleX {
                keyAsStick()
                moveByKey()
            } else {
                m.inputDevice = 1
                moveByStick()
            }
        } else if key == 0 {
            readJoystick()
            moveByStick()
        } else {
            m.inputDevice = 0
            readJoystick()
            m.lastPaddleX = m.paddleX
            m.lastPaddleY = m.paddleY
            keyAsStick()
            moveByKey()
        }
    }

    /// READ_KEY ($AA25): LAST_KEY = the key typed, or 0; lower-case letters as capitals.
    private mutating func readKey() -> UInt8 {
        var key = devices.key
        if key & 0x80 == 0 {
            key = 0
        } else {
            devices.key &= 0x7F
            if (0xE1 ..< 0xFB).contains(key) { key &= m.caseMask }
        }
        m.lastKey = key
        return key
    }

    /// What each of the ten keys in MOVE_KEYS does.
    private static let keyActions: [(ByteSymbol, UInt8)] = [
        (\.stickY, 0xFF), (\.stickY, 0x00), (\.stickX, 0x00), (\.stickX, 0xFF), (\.buttonA, 1),
        (\.buttonB, 1), (\.stickY, 0xC0), (\.stickY, 0x3F), (\.stickX, 0x3F), (\.stickX, 0xC0)]

    /// KEY_AS_STICK ($AA40): the key as a joystick position (or a button); a
    /// movement key is used up.  MOVE_KEYS: up, down, left, right, button A,
    /// button B, slowly up, down, left, right.
    private func keyAsStick() {
        m.stickX = 0x80
        m.stickY = 0x80
        let key = m.lastKey
        guard let i = Engine.keyActions.indices.first(where: { m.moveKeys[$0] == key }) else { return }
        let (variable, value) = Engine.keyActions[i]
        m[variable] = value
        m.lastKey = 0
    }

    /// MOVE_BY_KEY ($AB54) and MOVE_BY_STICK ($ABA1): the move for the
    /// joystick position, by the keyboard's or the joystick's table (16 steps
    /// of 16 positions each way).
    private func moveByKey() { move(by: m.keyMoveX, m.keyMoveY) }
    private func moveByStick() { move(by: m.stickMoveX, m.stickMoveY) }

    private func move(by x: Bytes, _ y: Bytes) {
        m.moveDX = x[m.stickX >> 4]
        m.moveDY = y[m.stickY >> 4]
    }

    /// CLEAR_BUTTONS ($AC09).
    private func clearButtons() {
        m.buttonA = 0
        m.buttonB = 0
    }

    /// READ_JOYSTICK ($AACB): the paddle counts, doubled, in PADDLE_X/Y and as
    /// the joystick position (STICK_Y upside down), and the buttons: button 1
    /// alone is BUTTON_A, button 0 alone BUTTON_B.
    private mutating func readJoystick() {
        devices.strobe = cycles
        let counts = Engine.paddleCounts(devices)
        m.paddleX = counts.x << 1
        m.paddleY = counts.y << 1
        m.stickX = counts.x << 1
        m.stickY = counts.y << 1 ^ 0xFF
        clearButtons()
        let b0 = devices.buttons[0], b1 = devices.buttons[1]
        let button: ByteSymbol = b1 ? \.buttonA : \.buttonB
        if b0 != b1 { m[button] &+= 1 }
    }

    /// The paddle counts READ_JOYSTICK's loop reaches: it reads paddle 0 at 14
    /// and paddle 1 at 23 cycles after the strobe, every 24 cycles, up to 127
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

    /// DETECT_JOYSTICK ($AC24), in every world's start-up code: after a
    /// strobe it reads paddle 0 up to 1280 times, every 11 cycles (15 after
    /// each 256th), and INPUT_DEVICE is 1 if the timer runs out by then (X
    /// and Y the reads left and made); else it looks for a mouse card from
    /// slot 7 down (its ROM's $Cn0C = $20 and $CnFB = $D6), finds none and
    /// INPUT_DEVICE is 0.  Declines for a mouse card: the original sets it up.
    mutating func detectJoystick() -> Bool {
        let found = (0 ..< 1280).first { n in
            !devices.paddleRunning(0, after: UInt64(10 + 11 * n + 4 * (n >> 8)))
        }
        var x: UInt8 = 0xFF, y: UInt8 = 0
        if let n = found {
            x = UInt8(5 - n >> 8)
            y = UInt8(n & 0xFF)
        } else {
            for slot in (1 ... 7).reversed() {
                let rom = 0xC000 | slot << 8
                y = 0x0C
                guard m[rom + 0x0C] == 0x20 else { continue }
                y = 0xFB
                guard m[rom + 0xFB] != 0xD6 else { return false }
            }
            m.slotPointer = 0xC000
        }
        devices.strobe = cycles
        r.bit(r.a, m[0xCFFF])
        r.a = found == nil ? 0 : 1
        r.x = x
        r.y = y
        m.inputDevice = r.a
        r.compare(r.a, 2)
        return true
    }

    // MARK: the levels' player routines

    /// PLAYER_WALK_SPRITE ($DFA3, v1.0 $DFA4): the player's sprite (sprite 0)
    /// for the move: two steps for each of up, down, right, left (frames 0-7
    /// of PLAYER_SPRITES), the larger part of the move choosing, a new step
    /// each tick.
    mutating func playerWalkSprite() {
        let dx = m.moveDX, dy = m.moveDY
        r.x = dx
        r.a = r.nz(dx | dy)
        guard r.a != 0 else { return }
        m.walkTemp = r.magnitude(dx)
        r.x = dy
        r.compare(r.magnitude(dy), m.walkTemp)
        let frame = m.walkFrame
        var step: UInt8
        if r.carry {
            r.x = dy
            step = dy & 0x80 == 0 ? frame & 1 : frame & 3 | 2
        } else {
            r.x = dx
            step = dx & 0x80 == 0 ? frame & 5 | 4 : frame | 6
        }
        step ^= 1
        m.walkFrame = step
        let first = Int(step << 4)
        for row in 0 ..< 16 { m.sprites[row] = m.playerSprites[first + row] }
        r.carry = false
        _ = r.adc(step << 4, 0x0F)
        r.x = UInt8((first - 1) & 0xFF)
        r.a = m.playerSprites[first]
        r.y = r.nz(0xFF)
    }

    /// GRAB_BUTTON ($BEBC): GRAB_STATE from the buttons: 0 with none (or
    /// both), 1 on a new press; otherwise as it is (the grab code sets it to 2
    /// once done).
    mutating func grabButton() {
        guard m.buttonA != m.buttonB else {
            r.a = r.nz(0)
            m.grabState = 0
            return
        }
        r.a = r.nz(m.grabState)
        guard r.a == 0 else { return }
        r.a = r.nz(1)
        m.grabState = 1
    }

    /// KEEP_MOVE ($FE18): keeps this tick's move in KEPT_DX/DY.
    mutating func keepMove() {
        m.keptDX = m.moveDX
        r.a = r.nz(m.moveDY)
        m.keptDY = r.a
    }
}
