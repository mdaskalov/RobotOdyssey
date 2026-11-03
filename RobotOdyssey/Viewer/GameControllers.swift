import GameController

/// A game controller as the Apple's joystick (`InputDevices`): the left stick,
/// or the d-pad, as the two paddles, A or X as button 0 and B or Y as button
/// 1.  The controller used last plays.  The game moves by how far the stick
/// is pushed (MOVE_BY_STICK, Docs/Engine.md "Input"): a little 1 step (as
/// Ctrl-I J K M), further 2 and 4 across, all the way 7 across and 15 up or
/// down; the d-pad all the way.
enum GameControllers {
    /// A controller's name and the joystick the game reads from it.
    struct Joystick {
        var name: String
        var paddles: (x: UInt8, y: UInt8)
        var buttons: [Bool]
    }

    /// The paddles of a stick let go.
    static let centre = InputDevices.centre

    /// The controller in use, if one is connected.
    static func read() -> Joystick? {
        guard let controller = GCController.current ?? GCController.controllers().first,
              let pad = controller.extendedGamepad
        else { return nil }
        let dpad = pad.dpad
        let stick = dpad.xAxis.value != 0 || dpad.yAxis.value != 0 ? dpad : pad.leftThumbstick
        return Joystick(name: controller.vendorName ?? "Game controller",
                        paddles: paddles(x: stick.xAxis.value, y: stick.yAxis.value),
                        buttons: [pad.buttonA.isPressed || pad.buttonX.isPressed,
                                  pad.buttonB.isPressed || pad.buttonY.isPressed])
    }

    /// The paddle positions (0-255, `centre` in the middle, y growing
    /// downwards) for a stick at (x, y), -1...1 each, y up: its round gate
    /// stretched to the Apple joystick's square one, so a corner is all the
    /// way both ways.  Within `deadZone` it is the centre: the noise of a
    /// stick let go would change the paddles, and in keyboard mode a change
    /// switches to the joystick, dropping that tick's key (READ_DEVICE).
    static func paddles(x: Float, y: Float) -> (x: UInt8, y: UInt8) {
        let r = min((x * x + y * y).squareRoot(), 1)
        guard r >= deadZone else { return centre }
        let stretch = r / max(abs(x), abs(y))
        func paddle(_ v: Float) -> UInt8 { UInt8(((min(max(v * stretch, -1), 1) + 1) * 127.5).rounded()) }
        return (paddle(x), paddle(-y))
    }

    /// Inside the game's own: MOVE_BY_STICK doesn't move within a quarter of the way out.
    private static let deadZone: Float = 0.2
}
