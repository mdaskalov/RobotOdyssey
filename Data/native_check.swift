// Checks the native engine routines against the original 6502 code.
//
// Build and run with native_check.sh (compiles this file together with the
// app's sources).  For every world on the given disks (and saved games on
// storage disks):
//
//   frames: each room drawn by the world's draw phase with the native routines
//           and with all 6502 code -- memory, bank 1 and screen must match;
//   calls:  the robot routines called directly on randomised states (robots in
//           the room, thrusters, bumpers, grabbers, battery, switch, antenna,
//           animation counters, random generator, interior rooms), several ticks
//           in a row -- all memory must match except the stack below the caller.
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
        var frames = 0, calls = 0
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
            guard let layout = RobotDrawing.layout(in: world.mem) else { continue }
            frames += checkFrames(world, screen)
            calls += checkCalls(world, screen, layout, &rng)
        }
        print("\(frames) frames, \(calls) calls compared; \(failures) differences")
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
