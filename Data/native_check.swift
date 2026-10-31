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
//           the object motion and input routines likewise on random objects,
//           moves, walls, keys and joystick positions -- memory, A, X, Y and
//           the flags must match.
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
        var set = DiskSet(version: "?")
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
            print("\(world.name) (v\(set.version)): natives \(screen.natives.joined(separator: ", "))")
            frames += checkFrames(world, screen)
            ticks += checkTicks(world, screen)
            inputTicks += checkInputTicks(world, screen, &rng)
            calls += checkMotionCalls(world, screen, &rng)
            guard let layout = RobotDrawing.layout(in: world.mem) else { continue }
            calls += checkCalls(world, screen, layout, &rng)
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
        for tick in 0 ..< count {
            do {
                try native.runTick()
                try original.runTick()
            } catch {
                fail("\(world.name) tick \(tick): \(error)")
                return tick
            }
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
        var rooms = Set<UInt8>(), keyTicks = 0, stickTicks = 0
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
            let at = [0x6300, 0x6400, 0x6500].map { native.memory[$0] }
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
                print("  \(tick + 1) ticks with input, then the world exits \(exit)")
                return tick + 1
            }
        }
        let still = Machine(memory: native.memory, bank1: native.bank1).installNatives()
        if still != screen.natives { fail("\(world.name): natives after the ticks: \(still)") }
        print("  \(count) ticks with input (\(keyTicks) keys, \(stickTicks) with a joystick), player in \(rooms.count) rooms")
        return count
    }

    /// Movement keys (capitals, lower case, Ctrl), space, and two others: T
    /// (the levels' toolkit key) and Z.  Not the keys that open a message
    /// waiting for a key (?, /, Esc...).
    static let testKeys: [UInt8] = [0xC9, 0xCD, 0xCA, 0xCB, 0xE9, 0xED, 0xEA, 0xEB, 0x89, 0x8D, 0x8A, 0x8B,
                                    0xA0, 0xD4, 0xDA]

    /// The object motion and input routines called directly on randomised
    /// states: memory, registers and the keyboard latch must match.
    static func checkMotionCalls(_ world: World, _ screen: GameScreen, _ rng: inout SplitMix, trials: Int = 200) -> Int {
        guard let start = try? screen.render(room: 0).machine else { return 0 }
        var routines: [(UInt16, String, Native)] = ObjectMotion.entries.map { entry, name, routine in
            (entry, name, { (s: inout NativeState) in routine(&s.ram, &s.registers); return true })
        }
        if PlayerInput.matches(start.cpu.mem) {
            routines.append((PlayerInput.entry, "READ_INPUT", PlayerInput.readInput))
        }
        if let l = PlayerInput.LevelRoutines.find(in: start.cpu.mem) {
            for (entry, name, routine) in [(l.walk, "walk", PlayerInput.walk), (l.grab, "grab", PlayerInput.grabButton),
                                           (l.keepMove, "keep move", PlayerInput.keepMove)] {
                routines.append((entry, name, { (s: inout NativeState) in routine(&s.ram, &s.registers); return true }))
            }
        }
        // Objects in the room lists (so moving them keeps the lists intact).
        let mem0 = start.cpu.mem
        var listed: [UInt8] = []
        for room in 0 ..< 0x40 {
            var o = mem0[0x6E00 + room], steps = 0
            while o != 0xFF && steps < 256 {
                if mem0[0x6300 + Int(o)] == room { listed.append(o) }
                o = mem0[0x6000 + Int(o)]
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
            for o in [0, Int(object)] {
                mem[0x6400 + o] = rng.chance(4) ? rng.byte() : rng.byte(0x86)
                mem[0x6500 + o] = rng.chance(4) ? rng.byte() : rng.byte(0xB1)
            }
            mem[RAM.currentObject] = object
            mem[RAM.moveDX] = signedStep(&rng)
            mem[RAM.moveDY] = signedStep(&rng)
            mem[RAM.destinationRoom] = rng.byte(0x40)
            mem[PlayerInput.wallsOn] = rng.byte(2)
            mem[PlayerInput.device] = rng.byte(2)
            for a in [PlayerInput.lastPaddleX, PlayerInput.lastPaddleY] { mem[a] = rng.chance(2) ? 0xFE : rng.byte() }
            let walls = ObjectMotion.roomWalls + 30 * Int(rng.byte(0x40))
            mem[0x00] = UInt8(walls & 0xFF)
            mem[0x01] = UInt8(walls >> 8)
            mem[0x02] = rng.chance(5) ? rng.byte() : rng.byte(22)
            mem[0x03] = rng.chance(5) ? rng.byte() : rng.byte(14)
            // Frames stay 0-7 in the game; from 8 on the sprite may be read from the I/O page.
            mem[PlayerInput.walkFrame] = rng.byte(8)
            mem[PlayerInput.grabState] = rng.byte(3)
            mem[RAM.buttonA] = rng.byte(2)
            mem[RAM.buttonB] = rng.byte(2)
            var devices = InputDevices()
            if !rng.chance(3) { devices.type(rng.chance(2) ? testKeys[Int(rng.byte(testKeys.count))] : rng.byte()) }
            if rng.chance(2) { devices.joystick = (rng.byte(), rng.byte()) }
            devices.buttons = [rng.chance(3), rng.chance(3)]
            let regs = Registers(a: rng.byte(), x: rng.byte(0x40), y: object, p: rng.byte() & ~0x18 | 0x20)
            for (entry, name, routine) in routines {
                let original = Machine(memory: mem, bank1: start.bank1)
                let native = Machine(memory: mem, bank1: start.bank1)
                for m in [original, native] {
                    m.devices = devices
                    (m.cpu.a, m.cpu.x, m.cpu.y, m.cpu.p, m.cpu.sp) = (regs.a, regs.x, regs.y, regs.p, 0xF0)
                }
                do {
                    try original.cpu.call(entry)
                } catch {
                    fail("\(world.name) trial \(trial) \(name): \(error)")
                    return n
                }
                guard native.call(routine) else {
                    fail("\(world.name) trial \(trial) \(name): declined")
                    return n
                }
                n += 1
                let o = original.cpu, c = native.cpu
                let what = "\(world.name) trial \(trial) \(name) object \(hex(Int(object)))"
                if let d = firstDifference(c.mem, o.mem, ignoring: 0x0100 ... 0x01F0) {
                    fail("\(what): \(hex(d)) native \(c.mem[d]) original \(o.mem[d])")
                    return n
                } else if (c.a, c.x, c.y, c.p & 0xCF) != (o.a, o.x, o.y, o.p & 0xCF) {
                    fail(String(format: "%@: registers native A=%02X X=%02X Y=%02X P=%02X original A=%02X X=%02X Y=%02X P=%02X",
                                what, c.a, c.x, c.y, c.p & 0xCF, o.a, o.x, o.y, o.p & 0xCF))
                    return n
                } else if native.devices.key != original.devices.key {
                    fail("\(what): keyboard latch differs")
                    return n
                }
            }
        }
        print("  \(n) calls of \(routines.count) object motion and input routines")
        return n
    }

    /// The robot routines called directly, on randomised states, 4 ticks each.
    static func checkCalls(_ world: World, _ screen: GameScreen, _ l: RobotDrawing.Layout, _ rng: inout SplitMix) -> Int {
        guard let start = try? screen.render(room: 0).machine else { return 0 }
        let robots = RobotDrawing(layout: l)
        var n = 0
        for trial in 0 ..< 300 {
            var mem = start.cpu.mem
            let interior = rng.chance(3)
            let room = interior ? RobotDrawing.interiorRooms[Int(rng.byte(l.robots))] : rng.byte(0x40)
            mem[RAM.currentRoom] = room
            for (i, body) in RobotDrawing.bodies.prefix(l.robots).enumerated() {
                if !interior || rng.chance(2) { mem[0x6300 + body] = room }
                mem[0x6400 + body] = rng.chance(8) ? rng.byte() : rng.byte(0x8C)
                mem[0x6500 + body] = rng.chance(8) ? rng.byte() : rng.byte(0xB8)
                let state = l.robotState + 0x1A * i
                for k in 0 ..< 4 {
                    mem[state + 0x0C + k] = rng.chance(10) ? rng.byte() : rng.byte(4)
                    mem[state + 0x10 + k] = rng.byte(8)
                    mem[l.grabbers + 4 * i + k] = rng.chance(10) ? rng.byte() : rng.byte(5)
                }
                mem[state + 0x18] = rng.chance(10) ? rng.byte(0x20) : rng.byte(0x10)
                mem[state + 0x19] = rng.byte(2)
                mem[0x6200 + RobotDrawing.antennaObjects[i]] = rng.byte(8)
                mem[0x6200 + RobotDrawing.signalObjects[i]] = rng.chance(2) ? 5 : rng.byte(8)
            }
            for v in [l.scanPosition, l.sparkToggle, l.rainbowColour, l.rainbowStep, l.rainbowBit] {
                mem[v] = rng.chance(4) ? rng.byte() : rng.byte(14)
            }
            if l.robots == 4 { mem[l.pulsePhase] = rng.byte(4) }
            mem[0x4E] = rng.byte()
            mem[0x4F] = rng.byte()
            let original = Machine(memory: mem, bank1: start.bank1)
            original.nativesEnabled = false
            let native = Machine(memory: mem, bank1: start.bank1)
            for tick in 0 ..< 4 {
                for (entry, routine) in [(l.exterior, robots.drawExteriors), (l.interior, robots.drawInterior)] {
                    original.cpu.sp = 0xF0
                    do {
                        try original.cpu.call(entry)
                    } catch {
                        fail("\(world.name) trial \(trial): \(error)")
                        return n
                    }
                    native.run(routine)
                    n += 1
                    // The stack below the caller ($01F0 down) only holds dead return addresses.
                    if let d = firstDifference(native.cpu.mem, original.cpu.mem, ignoring: 0x0100 ... 0x01F0) {
                        fail("\(world.name) trial \(trial) tick \(tick) room \(room) \(hex(Int(entry))): \(hex(d)) native \(native.cpu.mem[d]) original \(original.cpu.mem[d])")
                        return n
                    }
                }
            }
        }
        return n
    }
}
