import Apple2Kit
import Foundation
import MOS6502

/// The Apple's mouse card (Apple2Kit's `MouseCard`, slot 4) as Robot
/// Odyssey uses it: in while the viewer's canvas has the Mac's mouse
/// (`Machine.plugMouse`, Docs/Frontends.md "Input").  The game has a mouse mode of its own
/// (INPUT_DEVICE 2, Docs/Engine.md "Input"): every tick READ_DEVICE reads
/// the card (READMOUSE), takes its position, the motion since the last tick,
/// halved as the move (READ_MOUSE $ABDE: X across, Y down), limits it to 7
/// across and 15 up or down (LIMIT_MOVE), stops it at walls and moves the
/// player as the keys do, then puts the mouse back at (0, 0) (POSMOUSE):
/// motion past the limit is lost, so the player walks no faster than by the
/// keys.  The button is BUTTON_A.  The keyboard still moves the player too
/// (a key typed comes first).
///
/// The game calls the firmware through CALL_MOUSE (the routine at $Cn00 +
/// the offset in the ROM's table at $Cn12 + Y); it answers through the
/// screen holes of slot 4 (text page 1, empty in every world).
///
/// The button is one tick's press, as the space key's: the card reports
/// it once (`MouseCard.reportsClickOnce`, set by `Machine`): bit 7 at the
/// first read after it went down only, held or not, and never bit 6 (down
/// at the last read), which READ_MOUSE takes as down too.  The game reads
/// a button down over two ticks as one press held, and a press held on a pin with a
/// wire cuts the wire and then starts a new one on the pin, free now:
/// SOLDER_TOUCH's UNSOLDER leaves GRAB_STATE at 1, and SOLDER_WIRE takes
/// that as a new press in the next tick (the card's real status would
/// hold every click over two reads).
enum AppleMouse {
    /// Counts the card moves by for a unit of the player's move: READ_MOUSE
    /// halves them (but on a IIc, where $FBC0 is 0; in every world that byte
    /// of the language card's RAM isn't).
    static let countsPerUnit = 2

    /// What the card took over as it went in (`Machine.plugMouse`): put back
    /// as it comes out.
    struct Before {
        var device: UInt8
        let slotPointer: (UInt8, UInt8)
    }
}

nonisolated extension Machine {
    /// The card is in.
    var mousePlugged: Bool { beforeMouse != nil }

    /// Puts the card in (if it isn't) and tells the game, as DETECT_JOYSTICK
    /// does at start-up when it finds one (the joystick comes first there):
    /// INPUT_DEVICE 2, SLOT_POINTER at the card's ROM, and the game's own
    /// set-up of it (SET_UP_MOUSE), its registers and cycles put back (none
    /// of the tick's time).  Again where each tick starts (`GameLoop`): once
    /// INPUT_DEVICE isn't 2 (a world started), it is again.  What the game
    /// had there is put back as the card comes out (`unplugMouse`).
    func plugMouse() {
        let cpu = apple.cpu
        let slotPointer = GameSymbols.address(\.slotPointer)
        if beforeMouse == nil {
            beforeMouse = AppleMouse.Before(device: cpu.mem[\.inputDevice],
                                            slotPointer: (cpu.mem[slotPointer], cpu.mem[slotPointer + 1]))
            apple.mouseEnabled = true
        }
        guard cpu.mem[\.inputDevice] != 2 else { return }
        beforeMouse?.device = cpu.mem[\.inputDevice]
        cpu.mem[\.inputDevice] = 2
        cpu.mem[slotPointer] = 0x00
        cpu.mem[slotPointer + 1] = UInt8(0xC0 | MouseCard.slot)
        let registers = (cpu.pc, cpu.sp, cpu.a, cpu.x, cpu.y, cpu.p, cpu.cycles)
        _ = try? cpu.call(UInt16(GameSymbols.address(\.setUpMouse)), maxSteps: 10_000)
        (cpu.pc, cpu.sp, cpu.a, cpu.x, cpu.y, cpu.p, cpu.cycles) = registers
    }

    /// Takes the card out: INPUT_DEVICE (if still 2) and SLOT_POINTER as
    /// they were before it went in, the slot empty.  The rest of its set-up
    /// (MOUSE_SLOT, the screen holes) only the mouse mode reads.
    func unplugMouse() {
        guard let before = beforeMouse else { return }
        let cpu = apple.cpu
        let slotPointer = GameSymbols.address(\.slotPointer)
        if cpu.mem[\.inputDevice] == 2 { cpu.mem[\.inputDevice] = before.device }
        (cpu.mem[slotPointer], cpu.mem[slotPointer + 1]) = before.slotPointer
        apple.mouseEnabled = false
        beforeMouse = nil
    }
}
