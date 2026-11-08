// Checks the loader as the app runs it (Loader, DiskDrive, GameLoop): the
// original boot stage 2, loader and menu on the 6502 emulator, with the
// native boot, RWTS and copy checks.
//
// Build and run with loader_check.sh (compiles this file together with the
// app's sources).  On the given program disks (one version, both sides):
//
//   next:    levels 1-4 run their exit code (the way out found), the loader
//            loads the next level, which must arrive at its main loop and
//            run; its rooms, texts and code must be the disk's, and where its
//            memory differs from WorldBuilder's (the level entered from an
//            untouched previous one) is listed;
//   menu:    Level 1, Esc Esc: back to the menu, then each of its worlds
//            chosen must start;
//   escape:  Esc in the menu: its tune must come as one sound, then the
//            title and the menu again; Robotropolis starts without its
//            intro (the app steps over it);
//   intro:   Robotropolis with PLAY_INTRO switched off: the intro plays,
//            its tunes streamed 1/60 s at a time as the viewer does must
//            equal each stretch rendered at once;
//   sounds:  Level 1 with sounds queued, run and played as the viewer does
//            (ticks finished at once, the clicks streamed): PLAY_SOUNDS
//            native and switched off must click alike, no sound pausing
//            where the original doesn't, the player never running dry while
//            the cone moves (a click);
//   menu natives: the menu, the title (Esc in the menu) and the intro, each
//            call of DRAW_PICTURE and XOR_BLOCK against the original run to
//            its return on a copy: memory, banks, PC and SP the same;
//   walls:  the easter egg: Ctrl-A Ctrl-L T in the menu, Robotropolis,
//            then Ctrl-E must turn WALLS_ON off and on;
//   save:    Level 1, Esc S: the game saved on a new storage disk (letter A,
//            a name), back in Level 1; the slot read back (savedGames) must
//            hold the world as it was;
//   restore: the menu, Robotropolis, O: the saved game restored by the
//            loader, after its first tick, must be WorldBuilder's saved game
//            after its first (the random generator started alike) but for
//            the loader's own bytes;
//   new:     Level 1, Esc S, C: a new storage disk made on the one with the
//            saved game (the loader warns that it erases it), the game saved
//            there: the disk holds just that one.
//
// With --png DIR the screens along the way are written there.
import Apple2Kit
import CoreGraphics
import Foundation
import ImageIO
import MOS6502

func hex(_ v: Int) -> String { String(format: "$%04X", v) }

/// Address ranges where `a` and `b` differ, within `range`.
func differences(_ a: [UInt8], _ b: [UInt8], in range: Range<Int>) -> [ClosedRange<Int>] {
    var out: [ClosedRange<Int>] = []
    for i in range where a[i] != b[i] {
        if let last = out.last, i - last.upperBound <= 16 {
            out[out.count - 1] = last.lowerBound ... i
        } else {
            out.append(i ... i)
        }
    }
    return out
}

func describe(_ ranges: [ClosedRange<Int>]) -> String {
    ranges.isEmpty ? "none" : ranges.prefix(12).map { "\(hex($0.lowerBound))-\(hex($0.upperBound))" }.joined(separator: " ")
        + (ranges.count > 12 ? " … (\(ranges.count))" : "")
}

/// A session as the viewer runs one: the world after its start-up, the loader
/// with a drive; the machine at hand to start the world's exit code.
final class Session {
    let machine: Machine
    let loop: GameLoop
    let drive: DiskDrive
    let phase: DrawPhase

    init(_ world: World, disks: DiskSet, storage: DiskImage?) throws {
        guard let phase = DrawPhase(in: world.mem) else { throw GameScreen.Failure.noMainLoop }
        self.phase = phase
        machine = Machine(memory: world.mem, bank1: world.bank1, variant: world.codeCheck?.variant)
        machine.stirRandom()
        machine.cpu.sp = 0xFF
        try machine.cpu.call(UInt16(GameSymbols.address(\.worldStart)), stopAt: [UInt16(phase.loopStart)], maxSteps: 2_000_000)
        machine.install(world.codeCheck?.natives ?? [])
        drive = DiskDrive(program: disks, storage: storage, inserted: world.engine == .levels ? .sideA : .sideB)
        Loader.install(on: machine, drive: drive)
        loop = GameLoop(machine: machine, phase: phase, room: nil)
    }

    /// Runs `seconds` of the Apple's time.
    func run(_ seconds: Double) throws {
        try loop.run(until: loop.cycles + UInt64(seconds * GameLoop.clock))
    }

    /// Types each key once the game has taken the one before and run `pause`
    /// seconds; then runs until `until` holds (or `limit` seconds pass).
    func type(_ keys: [UInt8], pause: Double = 0.5, limit: Double = 60, until: () -> Bool = { false }) throws -> Bool {
        for key in keys {
            try run(pause)
            loop.devices.type(key)
            var waited = 0.0
            while loop.devices.key & 0x80 != 0 && waited < limit {
                try run(0.05)
                waited += 0.05
            }
        }
        var waited = 0.0
        while !until() && waited < limit {
            try run(0.1)
            waited += 0.1
        }
        return until()
    }

    /// The loader started a world, which is at its main loop.
    func arrived(_ count: Int = 1) -> Bool { loop.worldsLoaded >= count && !loop.inLoader }
}

func keys(_ s: String) -> [UInt8] { s.utf8.map { $0 | 0x80 } }
let esc: UInt8 = 0x9B, ret: UInt8 = 0x8D

@main
struct LoaderCheck {
    static var failures = 0
    static var pngDir: URL?

    static func fail(_ s: String) {
        failures += 1
        print("  FAIL " + s)
    }

    static func png(_ session: Session, _ name: String) {
        guard let pngDir, let image = Screen.image(session.loop.screen()),
              let dest = CGImageDestinationCreateWithURL(pngDir.appending(path: name + ".png") as CFURL, "public.png" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    static func main() throws {
        setvbuf(stdout, nil, _IONBF, 0)
        var args = Array(CommandLine.arguments.dropFirst()).filter { $0 != "--trace" }
        if let i = args.firstIndex(of: "--png"), i + 1 < args.count {
            pngDir = URL(fileURLWithPath: args[i + 1])
            try FileManager.default.createDirectory(at: pngDir!, withIntermediateDirectories: true)
            args.removeSubrange(i ... i + 1)
        }
        guard !args.isEmpty else {
            print("usage: loader_check [--png DIR] SIDE_A.dsk SIDE_B.dsk")
            exit(2)
        }
        var set = DiskSet(version: nil)
        for p in args {
            let d = try DiskImage(name: (p as NSString).lastPathComponent, data: Data(contentsOf: URL(fileURLWithPath: p)))
            if case .programSide(let side, let version) = d.role {
                set.version = version
                if side == .a { set.sideA = d } else { set.sideB = d }
            }
        }
        let builder = WorldBuilder(disks: set)
        let (worlds, errors) = builder.buildAll()
        errors.forEach { print("build error: \($0)") }
        let world = { (id: String) in worlds.first { $0.id == id }! }

        func scenario<T>(_ run: () throws -> T?) -> T? {
            do { return try run() } catch {
                fail("\(error)")
                return nil
            }
        }
        if !CommandLine.arguments.contains("--trace") { _ = scenario { try checkNextLevels(worlds, set) } }
        let storage = CommandLine.arguments.contains("--trace") ? nil : scenario { try checkSave(world("level1"), set) }
        _ = scenario { try checkMenu(world("level1"), set, worlds) }
        _ = scenario { try checkMenuEscape(world("level1"), set) }
        _ = scenario { try checkIntro(world("level1"), set) }
        _ = scenario { try checkGameSounds(world("level1"), set) }
        _ = scenario { try checkMenuNatives(world("level1"), set) }
        _ = scenario { try checkWallsKey(world("level1"), set) }
        if let storage {
            _ = scenario { try checkRestore(world("level1"), set, storage) }
            _ = scenario { try checkNewStorage(world("level1"), set, storage) }
        }
        print("\(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    /// Each level's exit code, then the next level as the loader loads it.
    static func checkNextLevels(_ worlds: [World], _ set: DiskSet) throws {
        for n in 1 ... 4 {
            let from = worlds.first { $0.id == "level\(n)" }!, to = worlds.first { $0.id == "level\(n + 1)" }!
            print("next: \(from.name) → \(to.name)")
            let session = try Session(from, disks: set, storage: nil)
            guard let entry = WorldBuilder.exitEntry(in: from.mem) else {
                fail("\(from.name): no exit code")
                continue
            }
            session.machine.cpu.pc = UInt16(entry)
            let ok = try session.type([esc], limit: 30) { session.arrived() }
            png(session, "next\(n + 1)")
            guard ok else {
                fail("\(to.name) didn't start (exit \(session.loop.exit?.description ?? "none"), PC \(hex(Int(session.machine.cpu.pc))))")
                continue
            }
            if session.loop.loadedWorld?.id != "level\(n + 1)" {
                fail("the loader started \(session.loop.loadedWorld?.name ?? "an unknown world")")
            }
            // WorldBuilder's level after its start-up, as the viewer starts it.
            let mem = session.loop.memory, built = try Session(to, disks: set, storage: nil).loop.memory
            print("  arrived; differs from WorldBuilder's after start-up (zero page, stack, screens, loader left out):",
                  describe(differences(mem, built, in: 0x0300 ..< 0x2000) + differences(mem, built, in: 0x6000 ..< 0x10000)))
            let ticks = session.loop.ticks
            try session.run(10)
            print("  \(session.loop.ticks - ticks) ticks in 10 s")
            if session.loop.ticks - ticks < 20 { fail("\(to.name): its main loop doesn't run") }
        }
    }

    /// Level 1 saved on a new storage disk, slot A.
    static func checkSave(_ level1: World, _ set: DiskSet) throws -> DiskImage? {
        print("save: \(level1.name), Esc S")
        let session = try Session(level1, disks: set, storage: nil)
        try session.run(2)
        var atExit: [UInt8]?
        _ = try session.type([esc, keys("S")[0]], limit: 10) { session.loop.exit != nil }
        atExit = session.loop.memory
        png(session, "save1")
        _ = try session.type([ret], limit: 5) { false }
        png(session, "save2")
        _ = try session.type([keys("A")[0]], limit: 3) { false }
        png(session, "save3")
        _ = try session.type(keys("LOADER CHECK") + [ret], limit: 5) { false }
        png(session, "save4")
        let ok = try session.type([ret], limit: 30) { session.arrived() }
        png(session, "save5")
        guard ok else {
            fail("not back in Level 1 (PC \(hex(Int(session.machine.cpu.pc))))")
            return nil
        }
        guard let disk = session.drive.takeWritten() else {
            fail("nothing written")
            return nil
        }
        let games = WorldBuilder(disks: set).savedGames(on: disk)
        print("  saved:", games.map(\.name))
        guard let game = games.first, games.count == 1 else {
            fail("expected one saved game")
            return disk
        }
        if game.name != "LOADER CHECK (Level 1)" { fail("name \(game.name)") }
        if let atExit {
            print("  saved world differs from the world at the exit: \(describe(differences(game.mem, atExit, in: 0x6000 ..< 0x9500)))")
            if !differences(game.mem, atExit, in: 0x6000 ..< 0x9500).isEmpty { fail("the saved world differs") }
        }
        return disk
    }

    /// Back to the menu, then each of the menu's worlds: ↓ (the Apple's, $8A) to choose,
    /// RETURN to load (Robotropolis and the lab: RETURN once more to go, O restores).
    static func checkMenu(_ level1: World, _ set: DiskSet, _ worlds: [World]) throws {
        let choices = ["level1", "lab", "anatomy", "toolkit", "labtutorial"]
        for (n, id) in choices.enumerated() {
            print("menu: \(level1.name), Esc Esc, choice \(n + 1)")
            let session = try Session(level1, disks: set, storage: nil)
            try session.run(2)
            _ = try session.type([esc, esc], limit: 10) { session.loop.exit != nil }
            try session.run(8)
            if n == 0 { png(session, "menu") }
            let ok = try session.type(Array(repeating: 0x8A, count: n) + [ret] + (n <= 1 ? [ret] : []), limit: 60) { session.arrived() }
            png(session, "menu-\(id)")
            guard ok else {
                fail("\(id) didn't start (PC \(hex(Int(session.machine.cpu.pc))), drive \(String(describing: session.drive.inserted)))")
                continue
            }
            if session.loop.loadedWorld?.id != id { fail("the loader started \(session.loop.loadedWorld?.name ?? "an unknown world")") }
            let built = try Session(worlds.first { $0.id == id }!, disks: set, storage: nil).loop.memory
            print("  \(session.loop.loadedWorld?.name ?? "?") arrived; differs from WorldBuilder's after start-up:",
                  describe(differences(session.loop.memory, built, in: 0x0300 ..< 0x2000) + differences(session.loop.memory, built, in: 0x6000 ..< 0x10000)))
            let ticks = session.loop.ticks
            try session.run(5)
            if session.loop.ticks - ticks < 10 { fail("\(id): its main loop doesn't run") }
        }
    }

    /// The saved game restored from the menu: Robotropolis, O, the storage
    /// disk (RETURN), letter A, the program disk (RETURN); compared after its
    /// first tick with WorldBuilder's saved game after its first, started with
    /// the random generator where the restore found it.
    static func checkRestore(_ level1: World, _ set: DiskSet, _ storage: DiskImage) throws {
        print("restore: the menu, Robotropolis, O, A")
        let session = try Session(level1, disks: set, storage: storage)
        var random: (UInt8, UInt8) = (0, 0)
        session.machine.hook(GameSymbols.address(\.worldStart)) { m in
            random = (m.cpu.mem[\.randomLow], m.cpu.mem[\.randomHigh])
            return false
        }
        _ = try session.type([esc, esc], limit: 10) { session.loop.exit != nil }
        try session.run(8)
        _ = try session.type([ret], limit: 3) { false }
        png(session, "restore1")
        _ = try session.type(keys("O"), limit: 3) { false }
        png(session, "restore2")
        _ = try session.type([ret], limit: 3) { false }
        png(session, "restore3")
        _ = try session.type(keys("A"), limit: 5) { false }
        png(session, "restore4")
        try session.run(0.5)
        session.loop.devices.type(ret)
        var steps = 0
        while session.loop.worldsLoaded == 0 || session.loop.inLoader || session.loop.ticks == 0 {
            do { try session.loop.runTick(maxSteps: 100_000) } catch CPU6502.CPUError.tooManySteps {}
            steps += 1
            if steps > 1000 { break }
        }
        png(session, "restore5")
        guard session.arrived() else {
            fail("the game wasn't restored (PC \(hex(Int(session.machine.cpu.pc))))")
            return
        }
        guard let game = WorldBuilder(disks: set).savedGames(on: storage).first else { return }
        var mem = game.mem
        mem[\.randomLow] = random.0
        mem[\.randomHigh] = random.1
        let built = try Session(game.with(mem: mem, bank1: game.bank1), disks: set, storage: nil)
        try built.loop.runTick()
        let restored = session.loop.memory
        let ranges = differences(restored, built.loop.memory, in: 0x0300 ..< 0x2000) + differences(restored, built.loop.memory, in: 0x6000 ..< 0x10000)
        print("  \(session.loop.loadedWorld?.name ?? "?") restored, tick \(session.loop.ticks); differs from WorldBuilder's saved game:")
        for r in ranges {
            print("   ", hex(r.lowerBound), Array(restored[r]).map { String(format: "%02X", $0) }.joined(separator: " "), "vs",
                  Array(built.loop.memory[r]).map { String(format: "%02X", $0) }.joined(separator: " "))
        }
        if session.loop.bank1 != built.loop.bank1 { fail("bank 1 differs") }
        // The loader's own: SLOTS_USED, BOOT_CHECK_RESULT and boot sector bytes, COPY_PROTECTION_OK's low bits.
        let loaders = [0x03E0, 0x03FE, 0x0800, 0x9C4E]
        if ranges.contains(where: { r in !loaders.contains { r.contains($0) } }) { fail("the restored game differs") }
    }

    static func checkNewStorage(_ level1: World, _ set: DiskSet, _ storage: DiskImage) throws {
        print("new: \(level1.name), Esc S, C")
        let session = try Session(level1, disks: set, storage: storage)
        try session.run(2)
        _ = try session.type([esc, keys("S")[0]], limit: 10) { session.loop.exit != nil }
        _ = try session.type(keys("C"), limit: 3) { false }
        png(session, "new1")
        _ = try session.type([ret], limit: 5) { false }
        png(session, "new2")
        let ok = try session.type(keys("A") + keys("NEW DISK") + [ret, ret], limit: 30) { session.arrived() }
        guard ok else {
            fail("not back in Level 1 (PC \(hex(Int(session.machine.cpu.pc))))")
            return
        }
        guard let disk = session.drive.takeWritten() else {
            fail("nothing written")
            return
        }
        let games = WorldBuilder(disks: set).savedGames(on: disk)
        print("  saved:", games.map(\.name), "on", disk.name)
        if games.map(\.name) != ["NEW DISK (Level 1)"] { fail("expected just the new game") }
        // The disk outside the slot is a blank storage disk's.
        var blank = DiskDrive.blankStorage(from: set.sideA!)
        let directory = DiskImage.offset(page: 32)
        blank.replaceSubrange(directory ..< directory + 256, with: disk.data[directory ..< directory + 256])
        let pages = (0 ..< 560).filter { p in
            let o = DiskImage.offset(page: p)
            return !(118 ..< 118 + 107).contains(p) && blank[o ..< o + 256] != disk.data[o ..< o + 256]
        }
        if !pages.isEmpty { fail("pages \(pages) differ from a blank storage disk's") }
    }

    static func checkMenuEscape(_ level1: World, _ set: DiskSet) throws {
        print("escape: the menu, Esc")
        let session = try Session(level1, disks: set, storage: nil)
        try session.run(1)
        _ = try session.type([esc, esc], limit: 10) { session.loop.exit != nil }
        try session.run(8)
        _ = session.loop.takeSpeaker()
        session.loop.devices.type(esc)
        var clicks: [UInt64] = []
        for _ in 0 ..< 20 {
            try session.run(0.1)
            clicks += session.loop.takeSpeaker().clicks
        }
        print(String(format: "  the tune: %d clicks in %.2f s", clicks.count,
                     Double((clicks.last ?? 0) - (clicks.first ?? 0)) / GameLoop.clock))
        if clicks.isEmpty { fail("no tune") }
        try session.run(25)
        png(session, "escape")
        let start = session.loop.cycles
        let ok = try session.type([ret, ret], limit: 20) { session.arrived() }
        let seconds = Double(session.loop.cycles - start) / GameLoop.clock
        print(String(format: "  Robotropolis started in %.1f s", seconds))
        if !ok || session.loop.loadedWorld?.id != "level1" { fail("Robotropolis didn't start") }
        if seconds > 5 { fail("the intro played") }
    }

    /// Robotropolis with PLAY_INTRO switched off: the intro plays, then the
    /// world starts.  Its tunes taken as the viewer takes them, 1/60 s at a
    /// time, and streamed (`SpeakerStream`, without its lead) must give each
    /// stretch's samples as rendered at once.
    static func checkIntro(_ level1: World, _ set: DiskSet) throws {
        print("intro: the menu, PLAY_INTRO switched off, Robotropolis")
        let session = try Session(level1, disks: set, storage: nil)
        session.loop.switchedOff = [Loader.skipIntro]
        try session.run(1)
        _ = try session.type([esc, esc], limit: 10) { session.loop.exit != nil }
        try session.run(8)
        _ = try session.type([ret], limit: 1) { false }
        _ = session.loop.takeSpeaker()
        session.loop.devices.type(ret)
        let start = session.loop.cycles
        var stream = SpeakerStream()
        var stretches: [(clicks: [UInt64], samples: [Float])] = []
        var resting = true
        var frames = 0
        while !session.arrived() && frames < 60 * 60 {
            try session.loop.run(until: start + UInt64(Double(frames + 1) / 60 * GameLoop.clock))
            frames += 1
            let clicks = session.loop.takeSpeaker().clicks
            let samples = stream.samples(clicks, upTo: session.loop.cycles, lead: 0)
            if samples.isEmpty {
                resting = true
                continue
            }
            if resting { stretches.append(([], [])) }
            resting = false
            stretches[stretches.count - 1].clicks += clicks
            stretches[stretches.count - 1].samples += samples
        }
        let clicks = stretches.reduce(0) { $0 + $1.clicks.count }
        print(String(format: "  Robotropolis started after %.1f s; the intro's tunes: %d clicks in %d stretches",
                     Double(frames) / 60, clicks, stretches.count))
        if !session.arrived() || session.loop.loadedWorld?.id != "level1" { fail("Robotropolis didn't start") }
        if frames < 60 * 10 { fail("the intro didn't play") }
        if clicks == 0 { fail("the intro played no tune") }
        for (n, s) in stretches.enumerated() {
            guard let first = s.clicks.first else {
                fail("stretch \(n) has no clicks")
                continue
            }
            var speaker = SpeakerRenderer()
            let once = speaker.samples(s.samples.count, clicks: s.clicks.map { Double($0 - first) })
            // The cone may start on its other side.
            let sign: Float = zip(s.samples, once).first { abs($0.0) > 1e-3 }.map { ($0.0 > 0) == ($0.1 > 0) ? 1 : -1 } ?? 1
            if let i = zip(s.samples, once).enumerated().first(where: { abs($1.0 - sign * $1.1) > 1e-6 })?.offset {
                fail(String(format: "stretch %d (at %.2f s): sample %d differs from the stretch rendered at once", n,
                            Double(first - start) / GameLoop.clock, i))
            }
        }
    }

    /// The game's sounds as the viewer plays them: Level 1 with sounds
    /// queued, run in 1/60 s frames, each tick finished at once
    /// (`GameLoop.run`'s `finishingTick`), the clicks streamed
    /// (`SpeakerStream`) into a player that plays each batch once the one
    /// before has played, or at once.  With PLAY_SOUNDS native and switched
    /// off: both must click alike, no sound may pause where the original
    /// doesn't – its clicks as far apart when played as their cycles – and
    /// the player may run dry (waiting for the clock) only once the cone has
    /// settled: cut off, it clicks.
    static func checkGameSounds(_ level1: World, _ set: DiskSet) throws {
        print("sounds: Level 1, PLAY_SOUNDS native and switched off, sounds played as the viewer plays them")
        let names = ["grab", "bumper", "crystalDischarge", "robotRelease"]
        var heard: [[UInt64]] = []
        for off in [false, true] {
            let session = try Session(level1, disks: set, storage: nil)
            if off { session.loop.switchedOff = [GameSymbols.name(of: \.playSounds)] }
            let loop = session.loop, mem = session.machine
            var stream = SpeakerStream()
            var clock = loop.cycles
            var queued = 0
            var playEnd = 0.0
            var lastSample: Float = 0, cut: Float = 0
            var played: [(cycle: UInt64, time: Double)] = []
            for frame in 0 ..< 120 * names.count {
                // Into the queue's last slot as QUEUE_SOUND puts it, at a tick's start: the tick plays it.
                if queued < names.count, frame >= 120 * queued, Int(mem.cpu.pc) == session.phase.loopStart,
                   let sound = GameSounds.pitches.first(where: { $0.name == names[queued] })?.parameters {
                    mem.cpu.mem[\.soundQueue] = 7
                    mem.cpu.mem[GameSymbols.address(\.soundFlags) + 7] = sound.kind.rawValue
                    mem.cpu.mem[GameSymbols.address(\.soundLengths) + 7] = sound.length
                    mem.cpu.mem[GameSymbols.address(\.soundSweeps) + 7] = sound.sweep
                    mem.cpu.mem[GameSymbols.address(\.soundPitches) + 7] = sound.pitch
                    mem.cpu.mem[GameSymbols.address(\.soundRooms) + 7] = 0xFF
                    queued += 1
                }
                clock += UInt64(GameLoop.clock / 60)
                try loop.run(until: clock, finishingTick: true)
                let clicks = loop.takeSpeaker().clicks
                let quiet = loop.speakerQuiet
                let samples = stream.samples(clicks, upTo: loop.cycles, quiet: quiet)
                guard !samples.isEmpty else { continue }
                // Ran dry: the player jumped from its last sample to 0 (a new sound's first click is its own).
                if Double(frame) / 60 > playEnd { cut = max(cut, abs(lastSample)) }
                lastSample = samples[samples.count - 1]
                playEnd = max(Double(frame) / 60, playEnd) + Double(samples.count) / Double(SpeakerRenderer.sampleRate)
                // While it sounds, the stream renders up to the machine's cycle; quiet, until the cone has settled.
                let end = quiet ? Double(clicks.last ?? 0) + Double(SpeakerRenderer.settle) * SpeakerRenderer.perSample : Double(loop.cycles)
                played += clicks.map { ($0, playEnd - (end - Double($0)) / GameLoop.clock) }
            }
            heard.append(played.map(\.cycle))
            // The sounds: clicks less than 20,000 cycles apart.
            var sounds: [ArraySlice<(cycle: UInt64, time: Double)>] = []
            var first = 0
            for i in played.indices.dropFirst() where played[i].cycle - played[i - 1].cycle >= 20_000 {
                sounds.append(played[first ..< i])
                first = i
            }
            if !played.isEmpty { sounds.append(played[first...]) }
            if sounds.count != names.count { fail("\(sounds.count) sounds played, not \(names.count)") }
            for (name, s) in zip(names, sounds) {
                let pause = zip(s, s.dropFirst()).map { ($1.time - $0.time) - Double($1.cycle - $0.cycle) / GameLoop.clock }.max() ?? 0
                print(String(format: "  %@ %@: %d clicks, %.0f ms, the longest pause added %.1f ms", off ? "6502  " : "native", name,
                             s.count, Double(s.last!.cycle - s.first!.cycle) / GameLoop.clock * 1000, max(pause, 0) * 1000))
                if pause > 0.001 { fail("\(name) (\(off ? "6502" : "native")) pauses where the original doesn't") }
            }
            print(String(format: "  %@ the player ran dry with the cone at %.3f at most", off ? "6502  " : "native", cut))
            if cut > 0.001 { fail("the player ran dry while the cone moved: a click") }
        }
        if heard[0] != heard[1] { fail("the 6502 PLAY_SOUNDS clicks other than the native") }
    }

    /// The menu's natives (`Loader.menuNatives`: DRAW_PICTURE, XOR_BLOCK)
    /// call by call against the original: Level 1, Esc Esc (the menu), Esc
    /// in the menu (the title), Robotropolis with PLAY_INTRO switched off
    /// (the intro).  At each call the original runs to its return on a copy,
    /// the native on the machine: memory but the dead stack, both banks, PC
    /// and SP must be the same.
    static func checkMenuNatives(_ level1: World, _ set: DiskSet) throws {
        print("menu natives: the menu, the title and the intro, each call against the original")
        let session = try Session(level1, disks: set, storage: nil)
        session.loop.switchedOff = [Loader.skipIntro]
        var calls: [String: Int] = [:]
        for native in Loader.menuNatives {
            let code = LoaderSymbols.map[keyPath: native.routine].code[0]
            session.machine.hook(native.entry, name: native.name) { m in
                guard code.matches(m.cpu.mem) else { return false }
                let original = m.copy()
                original.switchedOff.insert(native.name)
                let cpu = original.cpu
                let back = (UInt16(cpu.mem[0x100 + Int(cpu.sp &+ 1)]) | UInt16(cpu.mem[0x100 + Int(cpu.sp &+ 2)]) << 8) &+ 1
                let sp = cpu.sp &+ 2
                var steps = 0
                while !(cpu.pc == back && cpu.sp == sp), steps < 5_000_000, (try? cpu.step()) != nil { steps += 1 }
                native.run(LoaderRAM(cpu: m.cpu))
                m.cpu.returnFromSubroutine()
                let n = calls[native.name, default: 0]
                calls[native.name] = n + 1
                let dead = 0x0100 ... 0x0100 + Int(sp)
                if cpu.pc != back || m.cpu.pc != back || m.cpu.sp != sp {
                    fail("\(native.name) call \(n): returns to $\(String(cpu.pc, radix: 16)), not as the native")
                } else if let a = (0 ..< 0x10000).first(where: { !dead.contains($0) && m.cpu.mem[$0] != cpu.mem[$0] }) {
                    fail(String(format: "%@ call %d: $%04X is $%02X, the original's $%02X", native.name, n, a, m.cpu.mem[a], cpu.mem[a]))
                } else if m.bank1 != original.bank1 {
                    fail("\(native.name) call \(n): bank 1 differs")
                }
                return true
            }
        }
        try session.run(1)
        _ = try session.type([esc, esc], limit: 10) { session.loop.exit != nil }
        try session.run(8)
        let menu = calls
        session.loop.devices.type(esc)
        try session.run(25)
        let title = calls
        let start = session.loop.cycles
        let ok = try session.type([ret, ret], limit: 40) { session.arrived() }
        if !ok || session.loop.loadedWorld?.id != "level1" { fail("Robotropolis didn't start") }
        func counts(_ c: [String: Int], _ before: [String: Int] = [:]) -> String {
            Loader.menuNatives.map { "\($0.name) \(c[$0.name, default: 0] - before[$0.name, default: 0])" }.joined(separator: ", ")
        }
        print("  the menu: \(counts(menu)); the title: \(counts(title, menu)); the intro: \(counts(calls, title))")
        print(String(format: "  Robotropolis started after %.1f s with the natives", Double(session.loop.cycles - start) / GameLoop.clock))
        for native in Loader.menuNatives where calls[native.name, default: 0] == 0 { fail("\(native.name) never ran") }
    }

    /// Engine.md, *Easter egg: walking through walls*.
    static func checkWallsKey(_ level1: World, _ set: DiskSet) throws {
        print("walls: Ctrl-A Ctrl-L T in the menu, Robotropolis, Ctrl-E")
        let session = try Session(level1, disks: set, storage: nil)
        try session.run(1)
        _ = try session.type([esc, esc], limit: 10) { session.loop.exit != nil }
        try session.run(8)
        _ = try session.type([0x81, 0x8C, 0xD4], limit: 1) { false }
        let key = session.loop.memory[\.wallsKey]
        print(String(format: "  WALLS_KEY $%02X", key))
        if key != 0x85 { fail("WALLS_KEY isn't Ctrl-E") }
        guard try session.type([ret, ret], limit: 20, until: { session.arrived() }) else {
            fail("Robotropolis didn't start")
            return
        }
        try session.run(2)
        var walls = [session.loop.memory[\.wallsOn]]
        for _ in 0 ..< 2 {
            _ = try session.type([0x85], limit: 1) { false }
            walls.append(session.loop.memory[\.wallsOn])
        }
        print("  WALLS_ON", walls.map { String(format: "%d", $0) }.joined(separator: " → "))
        if walls != [1, 0, 1] { fail("Ctrl-E doesn't turn the walls off and on") }
    }
}
