// The game's sounds: the worlds' sound tables against the sound map
// (RobotOdyssey/Symbols/GameSounds.swift), every sound of the map as the
// original code plays it and as the native PLAY_SOUNDS does, and, to listen
// to, as WAV files.
//
// Build and run with ro_sounds.sh (compiles this file together with the
// app's sources):
//
//   ./ro_sounds.sh DISK.dsk...              every world's sound table by name, then
//                                           each sound: cycles, clicks, native check
//   ./ro_sounds.sh --wav DIR DISK.dsk...    the same, and the sounds as DIR/<name>.wav
//
// A sound: PLAY_SOUNDS ($9F3C) runs on the emulator, all 6502 code, with the
// sound alone in the queue, from its generator's entry to its RTS, and the
// speaker's clicks are taken by CPU cycle.  The native PLAY_SOUNDS plays the
// same sound: its cycles and clicks must be the same.  A noise starts with
// the shift register at 0 and the sweep counter (Y) at 0, as FLIP_PAGE leaves
// it every other tick; in the game both go on from what came before.  The
// files are what the app plays (SpeakerRenderer), 16-bit mono.
import Foundation

@main
struct SoundTool {
    static func main() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        var wavs: URL?
        if args.first == "--wav", args.count > 1 {
            wavs = URL(fileURLWithPath: args[1])
            args.removeFirst(2)
        }
        guard !args.isEmpty else {
            print("usage: ro_sounds.sh [--wav DIR] DISK.dsk... (program sides)")
            exit(2)
        }
        var set = DiskSet(version: nil)
        for p in args {
            let d = try DiskImage(name: (p as NSString).lastPathComponent, data: Data(contentsOf: URL(fileURLWithPath: p)))
            guard case .programSide(let side, let version) = d.role else { continue }
            set.version = version
            if side == .a { set.sideA = d } else { set.sideB = d }
        }
        let worlds = WorldBuilder(disks: set).buildAll().worlds
        guard let first = worlds.first else {
            print("no worlds on the disks")
            exit(1)
        }
        var failures = printTables(worlds)
        failures += try checkSounds(in: first, wavs: wavs)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: the worlds' tables

    /// Each world's sound table by number and name; returns the entries not in the map.
    static func printTables(_ worlds: [World]) -> Int {
        var unmapped = 0
        for world in worlds {
            guard let table = soundTable(world.mem) else {
                print("\(world.name): no sound table found at WORLD_SOUND")
                unmapped += 1
                continue
            }
            let names = table.enumerated().map { n, p -> String in
                guard let name = GameSounds.name(for: p) else {
                    unmapped += 1
                    return "\(n) NOT MAPPED: \(p)"
                }
                return "\(n) \(name)"
            }
            print("\(world.name): " + names.joined(separator: ", "))
        }
        return unmapped
    }

    /// The world's sound table: WORLD_SOUND jumps to its own routine
    /// `STA SOUND_ROOMS`, then `LDA table,X / STA` slot 0's flags, length,
    /// sweep and pitch, the four tables one after the other.
    static func soundTable(_ mem: [UInt8]) -> [Sound.Parameters]? {
        func word(_ a: Int) -> Int { Int(mem[a]) | Int(mem[a + 1]) << 8 }
        let vector = GameSymbols.address(\.worldSound)
        guard mem[vector] == 0x4C else { return nil }
        let h = word(vector + 1)
        guard mem[h] == 0x8D, word(h + 1) == GameSymbols.address(\.soundRooms) else { return nil }
        let slots: [KeyPath<GameSymbols, Table>] = [\.soundFlags, \.soundLengths, \.soundSweeps, \.soundPitches]
        var tables: [Int] = []
        for (i, slot) in slots.enumerated() {
            let at = h + 3 + 6 * i
            guard mem[at] == 0xBD, mem[at + 3] == 0x8D, word(at + 4) == GameSymbols.address(slot) else { return nil }
            tables.append(word(at + 1))
        }
        let count = tables[1] - tables[0]
        guard count > 0, count < 64, tables[2] - tables[1] == count, tables[3] - tables[2] == count else { return nil }
        return (0 ..< count).map { n in
            Sound.Parameters(kind: Sound.Kind(flags: mem[tables[0] + n]), length: mem[tables[1] + n],
                             sweep: mem[tables[2] + n], pitch: mem[tables[3] + n])
        }
    }

    // MARK: the sounds

    /// Every sound of the map by the original code and by the native; with
    /// `wavs`, as files.  Returns the sounds where the two differ.
    static func checkSounds(in world: World, wavs: URL?) throws -> Int {
        if let wavs { try FileManager.default.createDirectory(at: wavs, withIntermediateDirectories: true) }
        let native = Native.all.first { $0.routine == \.playSounds }!
        var failures = 0, bytes = 0
        for (name, parameters) in GameSounds.pitches {
            let original = try play(parameters, in: world)
            var status = ""
            if let ported = nativePlay(parameters, in: world, native) {
                if ported.cycles != original.cycles || ported.clicks != original.clicks {
                    status = "  NATIVE DIFFERS: \(ported.cycles) cycles, \(ported.clicks.count) clicks"
                    failures += 1
                }
            }
            if let wavs {
                let wav = wave(SpeakerRenderer.samples([original]))
                try wav.write(to: wavs.appendingPathComponent(name + ".wav"))
                bytes += wav.count
            }
            let ms = Double(original.cycles) / GameLoop.clock * 1000
            print("\(name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(parameters)  "
                  + String(format: "%8d cycles %7.1f ms %6d clicks", original.cycles, ms, original.clicks.count) + status)
        }
        if let wavs { print("\(GameSounds.pitches.count) files, \(bytes / 1024) KB in \(wavs.path)") }
        return failures
    }

    /// The sound alone in the queue, as every main loop plays it.
    static func machine(for p: Sound.Parameters, in world: World, variant: Variant?) -> Machine {
        let machine = Machine(memory: world.mem, bank1: world.bank1, variant: variant)
        let cpu = machine.cpu
        let slot = 7
        cpu.mem[\.soundFlags, slot] = p.kind.rawValue
        cpu.mem[\.soundLengths, slot] = p.length
        cpu.mem[\.soundSweeps, slot] = p.sweep
        cpu.mem[\.soundPitches, slot] = p.pitch
        cpu.mem[\.soundRooms, slot] = 0xFF
        cpu.mem[\.soundQueue] = UInt8(slot)
        cpu.mem[\.soundOn] = 1
        cpu.mem[\.lastKey] = 0
        cpu.mem[\.noiseLow] = 0
        cpu.mem[\.noiseHigh] = 0
        cpu.y = 0
        cpu.sp = 0xF0
        return machine
    }

    /// The sound by the original code: its clicks by cycle from the entry of
    /// PLAY_TONE or PLAY_NOISE, and the cycles up to its RTS.
    static func play(_ p: Sound.Parameters, in world: World) throws -> Sound.Played {
        let machine = machine(for: p, in: world, variant: nil)
        let cpu = machine.cpu
        let generators = [GameSymbols.address(\.playTone), GameSymbols.address(\.playNoise)].map { UInt16($0) }
        try cpu.call(UInt16(GameSymbols.address(\.playSounds)), stopAt: Set(generators))
        let start = cpu.cycles
        let sp = cpu.sp
        machine.clicks = []
        while cpu.sp <= sp { try cpu.step() }          // up to its RTS
        return Sound.Played(parameters: p, name: GameSounds.name(for: p), start: 0, cycles: cpu.cycles - start,
                            clicks: machine.clicks!.map { UInt32($0 - start) })
    }

    /// The sound by the native PLAY_SOUNDS, if the world has it.
    static func nativePlay(_ p: Sound.Parameters, in world: World, _ native: Native) -> Sound.Played? {
        guard let check = world.codeCheck, check.natives.contains(where: { $0.routine == \.playSounds }) else { return nil }
        let machine = machine(for: p, in: world, variant: check.variant)
        machine.call(native.run)
        return machine.takeSounds().first
    }

    /// A 16-bit mono WAV file.
    static func wave(_ samples: [Float]) -> Data {
        var d = Data()
        func put(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func put32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
        func put16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
        let rate = SpeakerRenderer.sampleRate
        put("RIFF"); put32(36 + 2 * samples.count); put("WAVE")
        put("fmt "); put32(16); put16(1); put16(1); put32(rate); put32(2 * rate); put16(2); put16(16)
        put("data"); put32(2 * samples.count)
        for s in samples { put16(Int(UInt16(bitPattern: Int16((s * 32767).rounded())))) }
        return d
    }
}
