import Foundation
import MOS6502

/// An Apple mouse card in slot 4, as Robot Odyssey uses one: plugged in
/// while the viewer's canvas has the Mac's mouse (`Machine.plugMouse`,
/// Docs/Frontends.md "Input").  The game has a mouse mode of its own
/// (INPUT_DEVICE 2, Docs/Engine.md "Input"): every tick READ_DEVICE reads
/// the card (READMOUSE), takes its position, the motion since the last tick,
/// halved as the move (READ_MOUSE $ABDE: X across, Y down), limits it to 7
/// across and 15 up or down (LIMIT_MOVE), stops it at walls and moves the
/// player as the keys do, then puts the mouse back at (0, 0) (POSMOUSE):
/// motion past the limit is lost, so the player walks no faster than by the
/// keys.  The button is BUTTON_A.  The keyboard still moves the player too
/// (a key typed comes first).
///
/// The firmware is the AppleMouse II's calls as the game makes them
/// (CALL_MOUSE: the routine at $Cn00 + the offset in the ROM's table at
/// $Cn12 + Y), answering through the screen holes of slot 4 (text page 1,
/// empty in every world): X $047C/$057C, Y $04FC/$05FC (low, high), the
/// status $077C (bit 5 moved since the last read, bit 7 the button), the
/// mode $07FC; CLAMPMOUSE takes its bounds from slot 0's ($0478/$0578 low,
/// $04F8/$05F8 high).  A call takes no time.
///
/// The button is one tick's press, as the space key's: bit 7 at the first
/// read after it went down only, held or not, and never bit 6 (down at the
/// last read), which READ_MOUSE takes as down too.  The game reads a button
/// down over two ticks as one press held, and a press held on a pin with a
/// wire cuts the wire and then starts a new one on the pin, free now:
/// SOLDER_TOUCH's UNSOLDER leaves GRAB_STATE at 1, and SOLDER_WIRE takes
/// that as a new press in the next tick (the card's real status would
/// hold every click over two reads).
nonisolated struct AppleMouse {
    static let slot = 4
    /// The card's ROM page, $C400.
    static let rom = 0xC000 | slot << 8

    /// The firmware's routines, by where their offset is in the ROM ($Cn12...).
    enum Call: Int, CaseIterable {
        case setMouse = 0x12, serveMouse, readMouse, clearMouse, posMouse, clampMouse, homeMouse, initMouse

        /// Where the routine is: $Cn80 on, an RTS each.
        var entry: Int { AppleMouse.rom + 0x80 + rawValue - Call.setMouse.rawValue }
    }

    /// The ROM page as DETECT_JOYSTICK and CALL_MOUSE read it: the Pascal
    /// firmware's bytes ($Cn05 $38, $Cn07 $18, $Cn0B $01), the mouse's ID
    /// ($Cn0C $20, $CnFB $D6), the routines' offsets, and an RTS at each.
    static let romPage: [UInt8] = {
        var page = [UInt8](repeating: 0, count: 256)
        for (i, v) in [(0x05, 0x38), (0x07, 0x18), (0x0B, 0x01), (0x0C, 0x20), (0xFB, 0xD6)] as [(Int, UInt8)] {
            page[i] = v
        }
        for call in Call.allCases {
            page[call.rawValue] = UInt8(call.entry - rom)
            page[call.entry - rom] = 0x60
        }
        return page
    }()

    /// Counts the card moves by for a unit of the player's move: READ_MOUSE
    /// halves them (but on a IIc, where $FBC0 is 0; in every world that byte
    /// of the language card's RAM isn't).
    static let countsPerUnit = 2

    /// The screen holes of the card's slot, and of slot 0 (CLAMPMOUSE's bounds).
    private static let xLow = 0x0478 + slot, yLow = 0x04F8 + slot, xHigh = 0x0578 + slot, yHigh = 0x05F8 + slot
    private static let status = 0x0778 + slot, modeHole = 0x07F8 + slot
    private static let bounds = (lowLow: 0x0478, highLow: 0x04F8, lowHigh: 0x0578, highHigh: 0x05F8)

    /// The position, in counts (y down), kept within `clamp`.
    private(set) var x = 0, y = 0
    /// The bounds CLAMPMOUSE set: 0-1023 each way as the card starts.
    private(set) var clamp = (x: 0 ... 1023, y: 0 ... 1023)
    private(set) var mode: UInt8 = 0
    /// The button is down.
    private(set) var button = false
    /// It went down since the last read: the next read finds it down, once.
    private var pressed = false
    /// The mouse moved since the last read.
    private var moved = false

    /// The mouse moved by (dx, dy) counts, y down.
    mutating func move(dx: Int, dy: Int) {
        guard dx != 0 || dy != 0 else { return }
        x = min(max(x + dx, clamp.x.lowerBound), clamp.x.upperBound)
        y = min(max(y + dy, clamp.y.lowerBound), clamp.y.upperBound)
        moved = true
    }

    /// The button pressed or let go.
    mutating func set(button down: Bool) {
        if down && !button { pressed = true }
        button = down
    }

    /// A firmware call with A and the memory as the CPU has them; returns
    /// the carry: set where a call fails, else clear.
    mutating func run(_ call: Call, a: UInt8, mem: inout [UInt8]) -> Bool {
        switch call {
        case .setMouse:
            guard a <= 0x0F else { return true }
            mode = a
            mem[AppleMouse.modeHole] = a
        case .serveMouse:
            return true                             // no interrupts: the game sets mode 1
        case .readMouse:
            let status = (pressed ? 0x80 : 0) | (moved ? 0x20 : 0) as UInt8
            (pressed, moved) = (false, false)
            mem[AppleMouse.status] = status
            putPosition(&mem)
        case .clearMouse:
            (x, y) = (0, 0)
            putPosition(&mem)
        case .posMouse:
            x = position(mem, AppleMouse.xLow, AppleMouse.xHigh)
            y = position(mem, AppleMouse.yLow, AppleMouse.yHigh)
        case .clampMouse:
            let b = AppleMouse.bounds
            var low = position(mem, b.lowLow, b.lowHigh), high = position(mem, b.highLow, b.highHigh)
            if low > high {
                // The game's: the low bytes meant signed, the high bytes left 0.
                low = Int(Int8(bitPattern: mem[b.lowLow]))
                high = Int(Int8(bitPattern: mem[b.highLow]))
            }
            guard low <= high else { break }
            if a & 1 == 0 { clamp.x = low ... high } else { clamp.y = low ... high }
        case .homeMouse:
            (x, y) = (clamp.x.lowerBound, clamp.y.lowerBound)
            putPosition(&mem)
        case .initMouse:
            self = AppleMouse()
            putPosition(&mem)
        }
        return false
    }

    private func position(_ mem: [UInt8], _ low: Int, _ high: Int) -> Int {
        Int(Int16(bitPattern: UInt16(mem[low]) | UInt16(mem[high]) << 8))
    }

    private func putPosition(_ mem: inout [UInt8]) {
        let (px, py) = (UInt16(truncatingIfNeeded: x), UInt16(truncatingIfNeeded: y))
        mem[AppleMouse.xLow] = UInt8(px & 0xFF)
        mem[AppleMouse.xHigh] = UInt8(px >> 8)
        mem[AppleMouse.yLow] = UInt8(py & 0xFF)
        mem[AppleMouse.yHigh] = UInt8(py >> 8)
    }

    /// What the card took over as it went in (`Machine.plugMouse`): put back
    /// as it comes out.
    struct Before {
        var device: UInt8
        let slotPointer: (UInt8, UInt8)
        let rom: [UInt8]
    }
}

nonisolated extension Machine {
    /// The firmware's routines, where CALL_MOUSE jumps to them: they run
    /// while the card is in (`devices.mouse`) and return like RTS; with the
    /// card out they only return, the carry set.
    func installMouseFirmware() {
        for call in AppleMouse.Call.allCases {
            hook(call.entry) { m in
                var carry = true
                if var mouse = m.devices.mouse {
                    carry = mouse.run(call, a: m.cpu.a, mem: &m.cpu.mem)
                    m.devices.mouse = mouse
                }
                m.cpu.p = carry ? m.cpu.p | CPU6502.Flag.carry : m.cpu.p & ~CPU6502.Flag.carry
                m.cpu.returnFromSubroutine()
                return true
            }
        }
    }

    /// The card is in.
    var mousePlugged: Bool { beforeMouse != nil }

    /// Plugs the card in (if it isn't) and tells the game, as DETECT_JOYSTICK
    /// does at start-up when it finds one (the joystick comes first there):
    /// INPUT_DEVICE 2, SLOT_POINTER at the card's ROM, and the game's own
    /// set-up of it (SET_UP_MOUSE), its registers and cycles put back (none
    /// of the tick's time).  Again where each tick starts (`GameLoop`): once
    /// INPUT_DEVICE isn't 2 (a world started), it is again.  What the game
    /// had there is put back as the card comes out (`unplugMouse`).
    func plugMouse() {
        let rom = AppleMouse.rom ..< AppleMouse.rom + 0x100
        let slotPointer = GameSymbols.address(\.slotPointer)
        if beforeMouse == nil {
            beforeMouse = AppleMouse.Before(device: cpu.mem[\.inputDevice],
                                            slotPointer: (cpu.mem[slotPointer], cpu.mem[slotPointer + 1]),
                                            rom: Array(cpu.mem[rom]))
            cpu.mem.replaceSubrange(rom, with: AppleMouse.romPage)
            devices.mouse = AppleMouse()
        }
        guard cpu.mem[\.inputDevice] != 2 else { return }
        beforeMouse?.device = cpu.mem[\.inputDevice]
        cpu.mem[\.inputDevice] = 2
        cpu.mem[slotPointer] = UInt8(AppleMouse.rom & 0xFF)
        cpu.mem[slotPointer + 1] = UInt8(AppleMouse.rom >> 8)
        let registers = (cpu.pc, cpu.sp, cpu.a, cpu.x, cpu.y, cpu.p, cpu.cycles)
        _ = try? cpu.call(UInt16(GameSymbols.address(\.setUpMouse)), maxSteps: 10_000)
        (cpu.pc, cpu.sp, cpu.a, cpu.x, cpu.y, cpu.p, cpu.cycles) = registers
    }

    /// Takes the card out: INPUT_DEVICE (if still 2), SLOT_POINTER and the
    /// ROM page as they were before it went in.  The rest of its set-up
    /// (MOUSE_SLOT, the screen holes) only the mouse mode reads.
    func unplugMouse() {
        guard let before = beforeMouse else { return }
        let slotPointer = GameSymbols.address(\.slotPointer)
        if cpu.mem[\.inputDevice] == 2 { cpu.mem[\.inputDevice] = before.device }
        (cpu.mem[slotPointer], cpu.mem[slotPointer + 1]) = before.slotPointer
        cpu.mem.replaceSubrange(AppleMouse.rom ..< AppleMouse.rom + 0x100, with: before.rom)
        devices.mouse = nil
        beforeMouse = nil
    }

    /// The mouse's button pressed or let go: a press is the game's button,
    /// BUTTON_A (READ_MOUSE), for one tick (`AppleMouse`).
    func mouseButton(down: Bool) {
        devices.mouse?.set(button: down)
    }
}
