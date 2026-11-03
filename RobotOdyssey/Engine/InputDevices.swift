import Foundation

/// The Apple IIe's input devices as the game reads them: the keyboard ($C000,
/// its strobe cleared by $C010), the joystick's buttons ($C061/$C062) and its
/// two paddle timers ($C064/$C065, started by $C070).  A timer runs for a time
/// proportional to the paddle's position and the engine measures it by
/// counting loop rounds (`PlayerInput`).  Without a joystick the timers never
/// run out, so the engine finds none at start-up ($AC24) and plays by keyboard;
/// it switches to the joystick as soon as the paddles read differently.  The
/// viewer plugs a game controller in as the joystick (`GameControllers`).
nonisolated struct InputDevices {
    /// $C000: the last key typed, bit 7 set until $C010 clears it.
    var key: UInt8 = 0
    /// Button 0 (Open Apple) and button 1 (Solid Apple).
    var buttons = [false, false]
    /// Paddle 0 (x) and paddle 1 (y), 0-255; nil: no joystick plugged in.
    var joystick: (x: UInt8, y: UInt8)?
    /// CPU cycle of the last $C070 strobe.
    var strobe: UInt64 = 0
    /// A movement key held down: typed again where a tick starts (`GameLoop`)
    /// once the game has read the last key, so the player walks on tick
    /// after tick from the first, without the Mac's key repeat delay.
    var held: UInt8?
    /// The buttons pressed since the last tick started (`set(button:down:)`).
    private var unread = [false, false]
    /// Tick starts until a click lets button 1 go (`click`).
    private var clickTicks = 0

    /// The paddles of a joystick let go: READ_JOYSTICK's centre, $80.
    static let centre: (x: UInt8, y: UInt8) = (128, 128)

    /// Types a key: an Apple key code, with or without bit 7.
    mutating func type(_ code: UInt8) {
        key = code | 0x80
    }

    /// A button pressed or let go (a controller's, every display frame): a
    /// press reads as down until a tick has started with it, so one shorter
    /// than a tick still reaches READ_INPUT, once.
    mutating func set(button i: Int, down: Bool) {
        if down && !buttons[i] { unread[i] = true }
        if down || !unread[i] { buttons[i] = down }
    }

    /// A click of the canvas's mouse (`MouseHand`): button 1 down for the
    /// next tick, as the game's mouse mode takes the Apple mouse's button for
    /// BUTTON_A (READ_MOUSE $ABDE).
    mutating func click() {
        set(button: 1, down: true)
        clickTicks = 2
    }

    /// Where a tick starts (`GameLoop`), before READ_INPUT reads the devices:
    /// the key held is typed again, the buttons pressed have been read, and
    /// a click's button, read in the last tick, goes up.
    mutating func startTick() {
        typeHeld()
        unread = [false, false]
        if clickTicks > 0 {
            clickTicks -= 1
            if clickTicks == 0 { buttons[1] = false }
        }
    }

    /// Types the key held, if any, once the last key typed has been read.
    private mutating func typeHeld() {
        guard let held, key & 0x80 == 0 else { return }
        type(held)
    }

    /// Whether paddle `n`'s timer still runs `elapsed` cycles after the
    /// strobe: 3072 cycles at position 255, 12 per step, the range
    /// READ_JOYSTICK measures (128 rounds of 24 cycles): 128 is its centre
    /// ($80), 0 and 255 its full moves.  (A PREAD counts about 11 cycles a
    /// step, AppleWin's 2816 at 255; with that, right and down reach only
    /// table entry 14, 4 across and 8 down instead of 7 and 15.)
    func paddleRunning(_ n: Int, after elapsed: UInt64) -> Bool {
        guard let joystick, n < 2 else { return true }
        let position = UInt64(n == 0 ? joystick.x : joystick.y)
        return elapsed * 255 < position * 3072
    }
}
