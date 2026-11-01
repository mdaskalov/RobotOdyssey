import Foundation

/// A world's main loop running as in the game: tick after tick, the original
/// 6502 code with the native routines, from the state after the world's
/// start-up code (`GameScreen.loop`).  Everything runs: the player by the
/// keys typed (`devices`), robots, circuits and the world's own code.  Run it
/// by CPU cycles (`run(until:)`) and show the page on screen, like the
/// Apple II: a tick takes as long as its work.  It stops where the world
/// hands back to the loader (`exit`): the menu, the next level, saving.
///
/// The viewer may look at any room: on arriving at the draw phase, `room`
/// replaces the room the loop chose (the player's), and the loop's room goes
/// back before the page flip, so the rest of the tick sees what the game
/// would.  Looking at the player's room changes nothing; elsewhere, only what
/// the draw phase itself writes differs (the world's own drawing code
/// animates the room it draws).
final class GameLoop {
    /// Apple IIe CPU clock in Hz (Data/ro_timing.py).
    static let clock = 1_020_484.0

    let phase: DrawPhase
    private let machine: Machine
    /// The room to draw; nil draws the loop's own room, the player's view.
    var room: Int?
    /// Ticks completed.
    private(set) var ticks = 0
    /// CPU cycles of the last completed tick.
    private(set) var tickCycles: UInt64 = 0
    /// The room on the page on screen (nil until the first flip).
    private(set) var shownRoom: Int?
    /// The machine at the start of the current tick.
    private var tickStart: Machine
    /// The room the draw phase is drawing.
    private var drawing: Int?
    /// The loop's own CURRENT_ROOM while the draw phase draws `room`.
    private var loopRoom: UInt8?
    /// The world's `JMP (RESET_VECTOR)`, back to the loader.
    private let exitJump: Int?
    /// Where the loop stopped, handing back to the loader.
    private(set) var exit: Exit?

    /// The world's request to the loader.
    struct Exit: CustomStringConvertible {
        /// MENU_MODE: 1 the menu, 2 the next level, 4 save the game, ...
        let request: UInt8
        /// NEXT_LEVEL: the level (or slot) it asks for.
        let level: UInt8

        var description: String {
            switch request {
            case 1: "back to the menu"
            case 2: "on to the next level (NEXT_LEVEL = \(level))"
            case 4: "to save the game"
            default: "to the loader (MENU_MODE = \(request), NEXT_LEVEL = \(level))"
            }
        }
    }

    init(machine: Machine, phase: DrawPhase, room: Int?) {
        self.machine = machine
        self.phase = phase
        self.room = room
        machine.cpu.pc = UInt16(phase.loopStart)
        tickStart = machine.copy()
        exitJump = WorldBuilder.find(WorldBuilder.instruction(0x6C, \.resetVector), in: machine.cpu.mem, from: 0x0803, to: 0x2000)
    }

    var cycles: UInt64 { machine.cpu.cycles }

    /// The keyboard, joystick and buttons the game reads.
    var devices: InputDevices {
        get { machine.devices }
        set { machine.devices = newValue }
    }

    /// Main RAM as the CPU sees it, and language card bank 1.
    var memory: [UInt8] { machine.cpu.mem }
    var bank1: [UInt8] { machine.bank1 }

    /// Cycles run in the current tick so far.
    var cyclesIntoTick: UInt64 { machine.cpu.cycles - tickStart.cpu.cycles }

    /// The hi-res page on screen.
    func screen() -> HiresScreen { machine.shownScreen() }

    /// Runs until the cycle counter reaches `cycles` (or the world exits).
    func run(until cycles: UInt64) throws {
        while exit == nil && machine.cpu.cycles < cycles { try step() }
    }

    /// Runs to the start of the next tick (or the world's exit).  A tick
    /// waiting for a key (a world's message) fails after `maxSteps`
    /// instructions (`CPUError.tooManySteps`) and can go on later.
    func runTick(maxSteps: Int = 20_000_000) throws {
        let t = ticks
        for _ in 0 ..< maxSteps {
            guard exit == nil else { return }
            try step()
            if ticks != t { return }
        }
        throw CPU6502.CPUError.tooManySteps(pc: machine.cpu.pc)
    }

    /// `room` drawn by the draw phase from the state at the start of the
    /// current tick, on a copy: what the loop shows once it gets there.
    func preview(room: Int) throws -> HiresScreen {
        try phase.draw(room: room, on: tickStart.copy())
    }

    private func step() throws {
        let page = machine.shownPage
        try machine.cpu.step()
        if machine.shownPage != page { shownRoom = drawing }
        if Int(machine.cpu.pc) == exitJump {
            exit = Exit(request: machine.cpu.mem[\.menuMode], level: machine.cpu.mem[\.nextLevel])
            return
        }
        switch Int(machine.cpu.pc) {
        case phase.loopStart:
            restoreRoom()                           // in case the draw phase was left early
            ticks += 1
            tickCycles = machine.cpu.cycles - tickStart.cpu.cycles
            tickStart = machine.copy()
        case phase.start:
            if let room {
                loopRoom = machine.cpu.mem[\.currentRoom]
                machine.cpu.mem[\.currentRoom] = UInt8(room)
            }
            drawing = Int(machine.cpu.mem[\.currentRoom])
        case phase.end:
            restoreRoom()
        default:
            break
        }
    }

    private func restoreRoom() {
        guard let r = loopRoom else { return }
        machine.cpu.mem[\.currentRoom] = r
        loopRoom = nil
    }
}
