import Foundation

/// The Apple IIe's input devices as the game reads them: the keyboard ($C000,
/// its strobe cleared by $C010), the joystick's buttons ($C061/$C062) and its
/// two paddle timers ($C064/$C065, started by $C070).  A timer runs for a time
/// proportional to the paddle's position and the engine measures it by
/// counting loop rounds (`PlayerInput`).  Without a joystick the timers never
/// run out, so the engine finds none at start-up ($AC24) and plays by keyboard;
/// it switches to the joystick as soon as the paddles read differently.
struct InputDevices {
    /// $C000: the last key typed, bit 7 set until $C010 clears it.
    var key: UInt8 = 0
    /// Button 0 (Open Apple) and button 1 (Solid Apple).
    var buttons = [false, false]
    /// Paddle 0 (x) and paddle 1 (y), 0-255; nil: no joystick plugged in.
    var joystick: (x: UInt8, y: UInt8)?
    /// CPU cycle of the last $C070 strobe.
    var strobe: UInt64 = 0

    /// Types a key: an Apple key code, with or without bit 7.
    mutating func type(_ code: UInt8) {
        key = code | 0x80
    }

    /// Whether paddle `n`'s timer still runs `elapsed` cycles after the
    /// strobe: 2816 cycles at position 255, about 11 per step (as in AppleWin).
    func paddleRunning(_ n: Int, after elapsed: UInt64) -> Bool {
        guard let joystick, n < 2 else { return true }
        let position = UInt64(n == 0 ? joystick.x : joystick.y)
        return elapsed * 255 < position * 2816
    }
}
