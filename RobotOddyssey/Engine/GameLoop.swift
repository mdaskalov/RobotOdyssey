import Foundation

/// A world's main loop running as in the game: tick after tick, the original
/// 6502 code with the native routines, from the state after the world's
/// start-up code (`GameScreen.loop`).  No keys are pressed, so the player
/// stays where the world puts it, but everything else runs: robots, circuits
/// and the world's own code.  Run it by CPU cycles (`run(until:)`) and show
/// the page on screen, like the Apple II: a tick takes as long as its work.
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
    /// The loop's own `CUR_ROOM` while the draw phase draws `room`.
    private var loopRoom: UInt8?

    init(machine: Machine, phase: DrawPhase, room: Int?) {
        self.machine = machine
        self.phase = phase
        self.room = room
        machine.cpu.pc = UInt16(phase.loopStart)
        tickStart = machine.copy()
    }

    var cycles: UInt64 { machine.cpu.cycles }

    /// Main RAM as the CPU sees it, and language card bank 1.
    var memory: [UInt8] { machine.cpu.mem }
    var bank1: [UInt8] { machine.bank1 }

    /// Cycles run in the current tick so far.
    var cyclesIntoTick: UInt64 { machine.cpu.cycles - tickStart.cpu.cycles }

    /// The hi-res page on screen.
    func screen() -> HiresScreen { machine.shownScreen() }

    /// Runs until the cycle counter reaches `cycles`.
    func run(until cycles: UInt64) throws {
        while machine.cpu.cycles < cycles { try step() }
    }

    /// Runs to the start of the next tick.
    func runTick() throws {
        let t = ticks
        for _ in 0 ..< 20_000_000 {
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
        switch Int(machine.cpu.pc) {
        case phase.loopStart:
            restoreRoom()                           // in case the draw phase was left early
            ticks += 1
            tickCycles = machine.cpu.cycles - tickStart.cpu.cycles
            tickStart = machine.copy()
        case phase.start:
            if let room {
                loopRoom = machine.cpu.mem[RAM.currentRoom]
                machine.cpu.mem[RAM.currentRoom] = UInt8(room)
            }
            drawing = Int(machine.cpu.mem[RAM.currentRoom])
        case phase.end:
            restoreRoom()
        default:
            break
        }
    }

    private func restoreRoom() {
        guard let r = loopRoom else { return }
        machine.cpu.mem[RAM.currentRoom] = r
        loopRoom = nil
    }
}
