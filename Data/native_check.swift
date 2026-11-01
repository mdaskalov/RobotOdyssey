// Checks the native engine routines against the original 6502 code.
//
// Build and run with native_check.sh (compiles this file together with the
// app's sources).  For every world on the given disks (and saved games on
// storage disks):
//
//   frames: each room drawn by the world's draw phase with the native routines
//           and with all 6502 code -- memory, bank 1 and screen must match;
//   ticks:  the world's main loop run as in the game (GameLoop, no input) with
//           the native routines and with all 6502 code -- memory, bank 1 and
//           the page on screen must match after every tick;
//   input:  the same with input before every tick: keys held for a while
//           (movement keys, lower case, Ctrl, space, others), then a joystick
//           moved around with its buttons, now and then a key or unplugged --
//           also the keyboard latch must match, and the natives must still
//           find their code afterwards;
//   calls:  the robot routines called directly on randomised states (robots in
//           the room, thrusters, bumpers, grabbers, battery, switch, antenna,
//           animation counters, random generator, interior rooms), several ticks
//           in a row -- all memory must match except the stack below the caller;
//           the object motion, input and player routines likewise on random
//           objects, moves, walls, keys and joystick positions -- memory, A, X,
//           Y and the flags must match; the sound player on random queues --
//           memory, registers, flags, the cycles it takes and every click
//           (the speaker's sound), to the cycle.
//
// Every sound the ticks play must be in the sound map (GameSounds).
//
// Every world's engine code must match the symbols' fingerprints (the
// loader's CodeCheck), and still match after the ticks.
import Foundation

struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476C_E5E9_CE1B
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func byte(_ upTo: Int = 256) -> UInt8 { UInt8(next() % UInt64(upTo)) }
    mutating func chance(_ n: Int) -> Bool { next() % UInt64(n) == 0 }
}

func firstDifference(_ a: [UInt8], _ b: [UInt8], ignoring skip: ClosedRange<Int>? = nil) -> Int? {
    for i in 0 ..< a.count where a[i] != b[i] && !(skip?.contains(i) ?? false) { return i }
    return nil
}

func hex(_ v: Int) -> String { String(format: "$%04X", v) }

@main
struct NativeCheck {
    static var failures = 0

    static func fail(_ s: String) {
        failures += 1
        if failures <= 20 { print("  FAIL " + s) }
    }

    static func main() throws {
        let paths = CommandLine.arguments.dropFirst()
        guard !paths.isEmpty else {
            print("usage: native_check DISK.dsk... (program sides of one version, storage disks)")
            exit(2)
        }
        var program: [DiskImage] = []
        var storage: [DiskImage] = []
        for p in paths {
            let d = try DiskImage(name: (p as NSString).lastPathComponent, data: Data(contentsOf: URL(fileURLWithPath: p)))
            if case .storage = d.role { storage.append(d) } else { program.append(d) }
        }
        var set = DiskSet(version: nil)
        for d in program {
            if case .programSide(let side, let version) = d.role {
                set.version = version
                if side == .a { set.sideA = d } else { set.sideB = d }
            }
        }
        let builder = WorldBuilder(disks: set)
        let (worlds, errors) = builder.buildAll()
        errors.forEach { print("build error: \($0)") }
        var all = worlds
        for disk in storage {
            all += builder.savedGames(on: disk, reference: worlds.filter { $0.kind == .level || $0.kind == .lab })
        }
        var rng = SplitMix(state: 1984)
        var frames = 0, ticks = 0, inputTicks = 0, calls = 0
        for world in all {
            let screen: GameScreen
            do {
                screen = try GameScreen(world: world)
            } catch {
                print("\(world.name): start-up failed: \(error)")
                failures += 1
                continue
            }
            let natives = screen.natives.map { String(format: "%@ $%04X", $0.name, $0.entry) }
            print("\(world.name) (v\(set.versionName)): natives \(natives.joined(separator: ", "))")
            if let differing = world.codeCheck?.differing, !differing.isEmpty {
                fail("\(world.name): code differs from the symbols' fingerprints: \(differing.joined(separator: ", "))")
            }
            frames += checkFrames(world, screen)
            ticks += checkTicks(world, screen)
            inputTicks += checkInputTicks(world, screen, &rng)
            guard let check = world.codeCheck else { continue }
            calls += checkRegisterCalls(world, screen, check, &rng)
            calls += checkRobotCalls(world, screen, check, &rng)
            calls += checkSoundCalls(world, screen, check, &rng)
        }
        print("\(frames) frames, \(ticks) ticks, \(inputTicks) ticks with input, \(calls) calls compared; \(failures) differences")
        exit(failures == 0 ? 0 : 1)
    }

    /// Every room drawn with and without the native routines.
    static func checkFrames(_ world: World, _ screen: GameScreen) -> Int {
        var n = 0, nativeCalls = 0
        defer {
            print("  \(n) frames, \(nativeCalls) native calls")
            if nativeCalls == 0 { fail("\(world.name): the native routines never ran") }
        }
        for room in 0 ..< World.roomCount where world.codeRooms[room] == nil {
            do {
                let native = try screen.render(room: room)
                let original = try screen.render(room: room, nativesEnabled: false)
                n += 1
                nativeCalls += native.machine.nativeCalls
                let deadStack = 0x0100 ... 0x0100 + Int(original.machine.cpu.sp)
                if native.machine.cpu.sp != original.machine.cpu.sp {
                    fail("\(world.name) room \(room): stack pointer differs")
                } else if let d = firstDifference(native.machine.cpu.mem, original.machine.cpu.mem, ignoring: deadStack) {
                    fail("\(world.name) room \(room): memory \(hex(d)) native \(native.machine.cpu.mem[d]) original \(original.machine.cpu.mem[d])")
                } else if native.machine.bank1 != original.machine.bank1 {
                    fail("\(world.name) room \(room): bank 1 differs")
                } else if native.screen.bytes != original.screen.bytes {
                    fail("\(world.name) room \(room): screen differs")
                }
            } catch {
                fail("\(world.name) room \(room): \(error)")
            }
        }
        return n
    }

    /// The main loop with and without the native routines, tick by tick.
    static func checkTicks(_ world: World, _ screen: GameScreen, count: Int = 40) -> Int {
        let native = screen.loop(room: nil)
        let original = screen.loop(room: nil, nativesEnabled: false)
        var sounds = 0
        defer { if sounds > 0 { print("  \(sounds) sounds in the ticks") } }
        for tick in 0 ..< count {
            do {
                try native.runTick()
                try original.runTick()
            } catch {
                fail("\(world.name) tick \(tick): \(error)")
                return tick
            }
            sounds += checkMapped(native.takeSounds(), "\(world.name) tick \(tick)")
            // Native routines leave no return addresses on the stack page.
            let deadStack = 0x0100 ... 0x01FF
            if let d = firstDifference(native.memory, original.memory, ignoring: deadStack) {
                fail("\(world.name) tick \(tick): memory \(hex(d)) native \(native.memory[d]) original \(original.memory[d])")
                return tick
            } else if native.bank1 != original.bank1 {
                fail("\(world.name) tick \(tick): bank 1 differs")
                return tick
            } else if native.screen().bytes != original.screen().bytes {
                fail("\(world.name) tick \(tick): screen differs")
                return tick
            }
        }
        print("  \(count) ticks")
        return count
    }

    /// The main loop with and without the native routines, with the same input
    /// before every tick.
    static func checkInputTicks(_ world: World, _ screen: GameScreen, _ rng: inout SplitMix, count: Int = 300) -> Int {
        let native = screen.loop(room: nil)
        let original = screen.loop(room: nil, nativesEnabled: false)
        func apply(_ change: (inout InputDevices) -> Void) {
            change(&native.devices)
            change(&original.devices)
        }
        var key: UInt8 = 0, hold = 0
        var rooms = Set<UInt8>(), keyTicks = 0, stickTicks = 0, sounds = 0
        var player: [UInt8] = []
        for tick in 0 ..< count {
            let joystickPhase = tick >= count / 2
            if hold == 0 {
                // Long walks in one direction, to get around.
                hold = rng.chance(3) ? Int(rng.byte(4)) + 1 : Int(rng.byte(30)) + 8
                if !joystickPhase {
                    key = rng.chance(5) ? 0 : testKeys[Int(rng.byte(testKeys.count))]
                } else {
                    key = rng.chance(6) ? testKeys[Int(rng.byte(testKeys.count))] : 0
                    let unplug = rng.chance(10)
                    let position = { (r: inout SplitMix) -> UInt8 in r.chance(3) ? [0, 128, 255][Int(r.byte(3))] : r.byte() }
                    let stick = (position(&rng), position(&rng))
                    let buttons = [rng.chance(4), rng.chance(4)]
                    apply { d in
                        d.joystick = unplug ? nil : stick
                        d.buttons = buttons
                    }
                }
            }
            hold -= 1
            if key != 0 {
                apply { $0.type(key) }
                keyTicks += 1
            }
            if joystickPhase && native.devices.joystick != nil { stickTicks += 1 }
            do {
                try native.runTick()
                try original.runTick()
            } catch {
                fail("\(world.name) input tick \(tick): \(error)")
                return tick
            }
            sounds += checkMapped(native.takeSounds(), "\(world.name) input tick \(tick)")
            let position: [KeyPath<GameSymbols, Table>] = [\.objRoom, \.objX, \.objY]
            let at = position.map { native.memory[$0, 0] }
            if at == player { hold = 0 }            // stuck at a wall: another direction
            player = at
            rooms.insert(at[0])
            let deadStack = 0x0100 ... 0x01FF
            if let d = firstDifference(native.memory, original.memory, ignoring: deadStack) {
                fail("\(world.name) input tick \(tick): memory \(hex(d)) native \(native.memory[d]) original \(original.memory[d])")
                return tick
            } else if native.bank1 != original.bank1 {
                fail("\(world.name) input tick \(tick): bank 1 differs")
                return tick
            } else if native.screen().bytes != original.screen().bytes {
                fail("\(world.name) input tick \(tick): screen differs")
                return tick
            } else if native.devices.key != original.devices.key {
                fail("\(world.name) input tick \(tick): keyboard latch differs")
                return tick
            } else if native.exit?.description != original.exit?.description {
                fail("\(world.name) input tick \(tick): exit differs")
                return tick
            }
            if let exit = native.exit {
                print("  \(tick + 1) ticks with input (\(sounds) sounds), then the world exits \(exit)")
                return tick + 1
            }
        }
        if let v = world.codeCheck?.variant {
            let still = CodeCheck(native.memory, v)
            if still.natives.map(\.name) != world.codeCheck?.natives.map(\.name) {
                fail("\(world.name): natives after the ticks: \(still.natives.map(\.name)), differing: \(still.differing)")
            }
        }
        print("  \(count) ticks with input (\(keyTicks) keys, \(stickTicks) with a joystick, \(sounds) sounds), player in \(rooms.count) rooms")
        return count
    }

    /// Fails for each sound played that is not in the sound map; returns how many were played.
    static func checkMapped(_ sounds: [Sound.Played], _ what: String) -> Int {
        for s in sounds where s.name == nil {
            fail("\(what): a sound not in GameSounds: \(s.parameters)")
        }
        return sounds.count
    }

    /// Movement keys (capitals, lower case, Ctrl), space, and two others: T
    /// (the levels' toolkit key) and Z.  Not the keys that open a message
    /// waiting for a key (?, /, Esc...).
    static let testKeys: [UInt8] = [0xC9, 0xCD, 0xCA, 0xCB, 0xE9, 0xED, 0xEA, 0xEB, 0x89, 0x8D, 0x8A, 0x8B,
                                    0xA0, 0xD4, 0xDA]

    /// The natives that leave registers (object motion, input, the levels'
    /// player routines) called directly on randomised states: memory,
    /// registers and the keyboard latch must match.
    static func checkRegisterCalls(_ world: World, _ screen: GameScreen, _ check: CodeCheck,
                                   _ rng: inout SplitMix, trials: Int = 200) -> Int {
        guard let start = try? screen.render(room: 0).machine else { return 0 }
        let v = check.variant
        let natives = check.natives.filter(\.leavesRegisters)
        // Objects in the room lists (so moving them keeps the lists intact).
        let mem0 = start.cpu.mem
        var listed: [UInt8] = []
        for room in 0 ..< World.roomCount {
            var o = mem0[\.roomFirstObject, room], steps = 0
            while o != 0xFF && steps < 256 {
                if mem0[\.objRoom, Int(o)] == room { listed.append(o) }
                o = mem0[\.objNext, Int(o)]
                steps += 1
            }
        }
        guard !listed.isEmpty else { return 0 }
        var n = 0
        func signedStep(_ r: inout SplitMix) -> UInt8 {
            r.chance(5) ? r.byte() : UInt8(bitPattern: Int8(Int(r.byte(33)) - 16))
        }
        for trial in 0 ..< trials {
            var mem = mem0
            let object = listed[Int(rng.byte(listed.count))]
            mem.withRAM(v) { m in
                for o in [0, Int(object)] {
                    m.objX[o] = rng.chance(4) ? rng.byte() : rng.byte(0x86)
                    m.objY[o] = rng.chance(4) ? rng.byte() : rng.byte(0xB1)
                }
                m.currentObject = object
                m.moveDX = signedStep(&rng)
                m.moveDY = signedStep(&rng)
                m.destinationRoom = rng.byte(0x40)
                m.wallsOn = rng.byte(2)
                m.inputDevice = rng.byte(2)
                m.lastPaddleX = rng.chance(2) ? 0xFE : rng.byte()
                m.lastPaddleY = rng.chance(2) ? 0xFE : rng.byte()
                m.pointer = m.roomWalls.address + 30 * Int(rng.byte(0x40))
                m.wallColumn = rng.chance(5) ? rng.byte() : rng.byte(22)
                m.wallRow = rng.chance(5) ? rng.byte() : rng.byte(14)
                m.buttonA = rng.byte(2)
                m.buttonB = rng.byte(2)
                if v.engine == .levels {
                    // Frames stay 0-7 in the game; from 8 on the sprite may be read from the I/O page.
                    m.walkFrame = rng.byte(8)
                    m.grabState = rng.byte(3)
                }
            }
            var devices = InputDevices()
            if !rng.chance(3) { devices.type(rng.chance(2) ? testKeys[Int(rng.byte(testKeys.count))] : rng.byte()) }
            if rng.chance(2) { devices.joystick = (rng.byte(), rng.byte()) }
            devices.buttons = [rng.chance(3), rng.chance(3)]
            let regs = Registers(a: rng.byte(), x: rng.byte(0x40), y: object, p: rng.byte() & ~0x18 | 0x20)
            for native in natives {
                let entry = GameSymbols.map[keyPath: native.routine].entry(v)!
                let original = Machine(memory: mem, bank1: start.bank1, variant: v)
                let ported = Machine(memory: mem, bank1: start.bank1, variant: v)
                for m in [original, ported] {
                    m.devices = devices
                    (m.cpu.a, m.cpu.x, m.cpu.y, m.cpu.p, m.cpu.sp) = (regs.a, regs.x, regs.y, regs.p, 0xF0)
                }
                do {
                    try original.cpu.call(entry)
                } catch {
                    fail("\(world.name) trial \(trial) \(native.name): \(error)")
                    return n
                }
                guard ported.call(native.run) else {
                    fail("\(world.name) trial \(trial) \(native.name): declined")
                    return n
                }
                n += 1
                let o = original.cpu, c = ported.cpu
                let what = "\(world.name) trial \(trial) \(native.name) object \(hex(Int(object)))"
                if let d = firstDifference(c.mem, o.mem, ignoring: 0x0100 ... 0x01F0) {
                    fail("\(what): \(hex(d)) native \(c.mem[d]) original \(o.mem[d])")
                    return n
                } else if (c.a, c.x, c.y, c.p & 0xCF) != (o.a, o.x, o.y, o.p & 0xCF) {
                    fail(String(format: "%@: registers native A=%02X X=%02X Y=%02X P=%02X original A=%02X X=%02X Y=%02X P=%02X",
                                what, c.a, c.x, c.y, c.p & 0xCF, o.a, o.x, o.y, o.p & 0xCF))
                    return n
                } else if ported.devices.key != original.devices.key {
                    fail("\(what): keyboard latch differs")
                    return n
                }
            }
        }
        print("  \(n) calls of \(natives.count) routines that leave registers")
        return n
    }

    /// The robot drawing called directly, on randomised states, 4 ticks each.
    static func checkRobotCalls(_ world: World, _ screen: GameScreen, _ check: CodeCheck, _ rng: inout SplitMix) -> Int {
        let robots = check.natives.filter { !$0.leavesRegisters }
        guard !robots.isEmpty, let start = try? screen.render(room: 0).machine else { return 0 }
        let v = check.variant
        let count = Robot.count(v.engine)
        var n = 0
        for trial in 0 ..< 300 {
            var mem = start.cpu.mem
            let interior = rng.chance(3)
            let room = interior ? Robot.interiorRooms[Int(rng.byte(count))] : rng.byte(0x40)
            mem.withRAM(v) { m in
                m.currentRoom = room
                for (i, body) in Robot.bodies.prefix(count).enumerated() {
                    if !interior || rng.chance(2) { m.objRoom[body] = room }
                    m.objX[body] = rng.chance(8) ? rng.byte() : rng.byte(0x8C)
                    m.objY[body] = rng.chance(8) ? rng.byte() : rng.byte(0xB8)
                    let state = Robot.stateSize * i
                    for k in 0 ..< 4 {
                        m.robotThrusters[state + k] = rng.chance(10) ? rng.byte() : rng.byte(4)
                        m.robotBumpers[state + k] = rng.byte(8)
                        m.robotGrabbers[4 * i + k] = rng.chance(10) ? rng.byte() : rng.byte(5)
                    }
                    m.robotBattery[state] = rng.chance(10) ? rng.byte(0x20) : rng.byte(0x10)
                    m.robotSwitch[state] = rng.byte(2)
                    m.objColour[Robot.antennaObjects[i]] = rng.byte(8)
                    m.objColour[Robot.signalObjects[i]] = rng.chance(2) ? 5 : rng.byte(8)
                }
                let counters: [ByteSymbol] = [\.scanPosition, \.sparkToggle, \.rainbowColour, \.rainbowStep, \.rainbowBit]
                for counter in counters {
                    m[counter] = rng.chance(4) ? rng.byte() : rng.byte(14)
                }
                if v.engine == .levels { m.pulsePhase = rng.byte(4) }
                m.randomLow = rng.byte()
                m.randomHigh = rng.byte()
            }
            let original = Machine(memory: mem, bank1: start.bank1, variant: v)
            original.nativesEnabled = false
            let ported = Machine(memory: mem, bank1: start.bank1, variant: v)
            for tick in 0 ..< 4 {
                for native in robots {
                    let entry = GameSymbols.map[keyPath: native.routine].entry(v)!
                    original.cpu.sp = 0xF0
                    do {
                        try original.cpu.call(entry)
                    } catch {
                        fail("\(world.name) trial \(trial): \(error)")
                        return n
                    }
                    ported.call(native.run)
                    n += 1
                    // The stack below the caller ($01F0 down) only holds dead return addresses.
                    if let d = firstDifference(ported.cpu.mem, original.cpu.mem, ignoring: 0x0100 ... 0x01F0) {
                        fail("\(world.name) trial \(trial) tick \(tick) room \(room) \(native.name): \(hex(d)) native \(ported.cpu.mem[d]) original \(original.cpu.mem[d])")
                        return n
                    }
                }
            }
        }
        print("  \(n) calls of the robot drawing")
        return n
    }

    /// PLAY_SOUNDS called directly on random queues: up to 8 sounds, from
    /// the map or random (wrapping noise too), for the player's room, every
    /// room or another; the sound on or off, Ctrl-S; random counters, sweep
    /// counter (Y) and noise.  Memory, registers, flags, cycles and the
    /// clicks the native reports must be the original's.
    static func checkSoundCalls(_ world: World, _ screen: GameScreen, _ check: CodeCheck,
                                _ rng: inout SplitMix, trials: Int = 120) -> Int {
        guard let native = check.natives.first(where: { $0.routine == \.playSounds }),
              let start = try? screen.render(room: 0).machine else { return 0 }
        let v = check.variant
        let entry = GameSymbols.map.playSounds.entry(v)!
        let known = GameSounds.pitches.map(\.parameters)
        let kinds: [Sound.Kind] = [.tone, .noise, .noiseWrapping]
        let counters: [ByteSymbol] = [\.tonePeriod, \.noiseLow, \.noiseHigh, \.soundCountLow, \.soundCountHigh,
                                      \.noisePeriod, \.soundSweep]
        var n = 0, played = 0, clickCount = 0
        for trial in 0 ..< trials {
            var mem = start.cpu.mem
            mem.withRAM(v) { m in
                let queued = Int(rng.byte(9))
                m.soundQueue = UInt8(8 - queued)
                for slot in 8 - queued ..< 8 {
                    let p = rng.chance(3)
                        ? Sound.Parameters(kind: kinds[Int(rng.byte(3))], length: rng.chance(8) ? rng.byte() : rng.byte(4),
                                           sweep: rng.byte(), pitch: rng.byte())
                        : known[Int(rng.byte(known.count))]
                    m.soundFlags[slot] = p.kind.rawValue | rng.byte(0x40)
                    m.soundLengths[slot] = p.length
                    m.soundSweeps[slot] = p.sweep
                    m.soundPitches[slot] = p.pitch
                    let rooms = [0xFF, m.objRoom[0], rng.byte(0x40)]
                    m.soundRooms[slot] = rooms[Int(rng.byte(3))]
                }
                m.soundOn = rng.chance(4) ? 0 : 1
                m.lastKey = rng.chance(4) ? 0x93 : rng.byte()
                for counter in counters { m[counter] = rng.byte() }
            }
            let original = Machine(memory: mem, bank1: start.bank1, variant: v)
            let ported = Machine(memory: mem, bank1: start.bank1, variant: v)
            let regs = Registers(a: rng.byte(), x: rng.byte(), y: rng.byte(), p: rng.byte() & ~0x18 | 0x20)
            for m in [original, ported] {
                (m.cpu.a, m.cpu.x, m.cpu.y, m.cpu.p, m.cpu.sp) = (regs.a, regs.x, regs.y, regs.p, 0xF0)
            }
            original.clicks = []
            do {
                try original.cpu.call(entry, maxSteps: 50_000_000)
            } catch {
                fail("\(world.name) sound trial \(trial): \(error)")
                return n
            }
            ported.call(native.run)
            let sounds = ported.takeSounds()
            n += 1
            played += sounds.count
            clickCount += original.clicks!.count
            let o = original.cpu, c = ported.cpu
            let what = "\(world.name) sound trial \(trial)"
            if let d = firstDifference(c.mem, o.mem, ignoring: 0x0100 ... 0x01F0) {
                fail("\(what): \(hex(d)) native \(c.mem[d]) original \(o.mem[d])")
                return n
            } else if (c.a, c.x, c.y, c.p & 0xCF) != (o.a, o.x, o.y, o.p & 0xCF) {
                fail(String(format: "%@: registers native A=%02X X=%02X Y=%02X P=%02X original A=%02X X=%02X Y=%02X P=%02X",
                            what, c.a, c.x, c.y, c.p & 0xCF, o.a, o.x, o.y, o.p & 0xCF))
                return n
            } else if c.cycles != o.cycles {
                fail("\(what): native \(c.cycles) cycles, original \(o.cycles)")
                return n
            }
            let clicks = sounds.flatMap { s in s.clicks.map { s.start + UInt64($0) } }
            if clicks != original.clicks! {
                let i = zip(clicks, original.clicks!).enumerated().first { $1.0 != $1.1 }?.offset ?? min(clicks.count, original.clicks!.count)
                fail("\(what): \(clicks.count) clicks, original \(original.clicks!.count), from click \(i) on they differ")
                return n
            }
        }
        print("  \(n) calls of the sound player, \(played) sounds, \(clickCount) clicks")
        return n
    }
}
