import Foundation

/// The program disk (side A and/or B) of one version, plus optional storage disks.
struct DiskSet {
    /// nil: a version the loader's file table doesn't tell (`LoaderSymbols`).
    var version: Version?
    var sideA: DiskImage?
    var sideB: DiskImage?

    func disk(_ side: DiskSide) -> DiskImage? { side == .a ? sideA : sideB }

    var versionName: String { version?.rawValue ?? "1.x" }

    var title: String {
        let names = [sideA?.name, sideB?.name].compactMap { $0 }.joined(separator: " + ")
        return "Robot Odyssey I v\(versionName) (\(names))"
    }
}

/// Builds world memory images the way the game's loader does.  It knows
/// which engine it loads with a world and the disks' version, so it checks
/// the engine code against the symbols' fingerprints right away (`CodeCheck`):
/// the natives replace only the routines whose code is the version's.
struct WorldBuilder {
    let disks: DiskSet

    private func load(_ segments: [Segment], into mem: inout [UInt8]) throws {
        for s in segments {
            guard let disk = disks.disk(s.side) else { throw DiskError.missingSide(s.side.rawValue) }
            let length = disks.version == .v1_0 ? GameCatalog.lengthsV10[s.side]?[s.page] ?? s.length : s.length
            mem.replaceSubrange(s.address ..< s.address + length, with: disk.read(page: s.page, length: length))
        }
    }

    /// The engine font/colour tables, from whichever side is available (they are identical).
    private func loadEngineMain(into mem: inout [UInt8]) throws {
        let s = GameCatalog.engineMain
        guard let disk = disks.sideA ?? disks.sideB else { throw DiskError.missingSide("A or B") }
        mem.replaceSubrange(s.address ..< s.address + s.length, with: disk.read(page: s.page, length: s.length))
    }

    /// All worlds whose disk side is present; ids are prefixed to keep versions apart.
    func buildAll(idPrefix: String = "") -> (worlds: [World], errors: [String]) {
        var cache: [String: [UInt8]] = [:]
        var worlds: [World] = []
        var errors: [String] = []
        for def in GameCatalog.worlds where disks.disk(def.side) != nil {
            do {
                var mem = try memory(for: def.id, cache: &cache)
                let bank1 = try setUpChips(def.chips, mem: &mem)
                WorldBuilder.passCopyProtection(&mem)
                worlds.append(World(id: idPrefix + def.id, name: def.name, kind: def.kind, mem: mem,
                                    bank1: bank1, engine: def.engine, codeCheck: check(mem, def.engine)))
            } catch {
                errors.append("\(def.name): \(error.localizedDescription)")
            }
        }
        return (worlds, errors)
    }

    /// The engine code in `mem` checked as the code of `engine` in the disks' version.
    func check(_ mem: [UInt8], _ engine: EngineBuild) -> CodeCheck? {
        disks.version.map { CodeCheck(mem, Variant(engine: engine, version: $0)) }
    }

    /// The loader's chip set-up on a loaded world; returns language card bank 1
    /// ($D000-$DFFF), which nothing else loads.
    func setUpChips(_ chips: ChipSetup, mem: inout [UInt8]) throws -> [UInt8] {
        var bank1 = [UInt8](repeating: 0, count: 0x1000)
        try chips.apply(to: &mem, bank1: &bank1) { s in
            guard let disk = disks.disk(s.side) else { throw DiskError.missingSide(s.side.rawValue) }
            return disk.read(page: s.page, length: s.length)
        }
        return bank1
    }

    /// The copy protection: the loader's last step before it starts a world
    /// (START_WORLD $4563, RESTORE_GAME $452D) is COPY_PROTECTION_OK = $03FE
    /// AND $02CE, the results of the checks at boot and in the menu (bit 7 set:
    /// passed).  The app runs neither, so it sets the flag as an original disk
    /// leaves it.  On the disk the byte is $00, and with bit 7 clear every world
    /// but Robot Anatomy skips the soldering pen (Docs/CopyProtection.md).
    static func passCopyProtection(_ mem: inout [UInt8]) {
        mem[\.copyProtectionOK] = 0x80
    }

    func memory(for id: String, cache: inout [String: [UInt8]]) throws -> [UInt8] {
        if let m = cache[id] { return m }
        guard let def = GameCatalog.world(id) else { return [] }
        var mem: [UInt8]
        if let baseID = def.base, let base = GameCatalog.world(baseID) {
            // Levels 2-5 inherit the object table left by the previous level's exit code.
            mem = try memory(for: baseID, cache: &cache)
            try WorldBuilder.runExitCode(&mem, worldName: base.name)
            mem.replaceSubrange(0x0803 ..< 0x2000, with: repeatElement(0, count: 0x2000 - 0x0803))
        } else {
            mem = [UInt8](repeating: 0, count: 0x10000)
        }
        try loadEngineMain(into: &mem)
        try load(GameCatalog.segments(of: def.engine), into: &mem)
        try load(def.segments, into: &mem)
        try load(def.code, into: &mem)
        cache[id] = mem
        return mem
    }

    /// Run the level's "leave for the next level" code on the 6502 emulator.
    ///
    /// It moves objects in/out of the world (room $3F = nowhere), shows a text
    /// screen, waits for a key and jumps to the next-level handler
    /// (`LDA #2 / STA MENU_MODE`), where we stop.  ESC is reported as held down.
    static func runExitCode(_ mem: inout [UInt8], worldName: String) throws {
        let startUpEnd = [0xA9, 0x00] + instruction(0x8D, \.flag9C51)             // LDA #0 / STA FLAG_9C51
        guard let entry = exitEntry(in: mem),
              let handler = find(nextLevelHandler, in: mem, from: 0x0803, to: 0x2000),
              let initEnd = find(startUpEnd, in: mem, from: 0x0816, to: 0x0900)
        else { throw DiskError.exitCodeNotFound(worldName) }
        let cpu = CPU6502(memory: mem)
        cpu.ioRead = { $0 == 0xC000 ? 0x9B : 0 }
        // The level start-up code sets engine vectors used by the exit code.
        try cpu.call(UInt16(GameSymbols.address(\.worldStart)), stopAt: [UInt16(initEnd + startUpEnd.count)])
        cpu.sp = 0xFF
        try cpu.call(UInt16(entry), stopAt: [UInt16(handler)])
        mem = cpu.mem
    }

    /// Entry of the level's exit code, or nil (level 5 has none).
    ///
    /// The exit code ends with LDY #next / JMP handler.  Its entry is the lowest
    /// address before that which a JMP/JSR elsewhere targets and from which
    /// straight-line code (no RTS/RTI/BRK, no JMP away) runs into the LDY.
    /// The addresses differ between v1.0 and v1.1 (level 2: $0B6F vs $0B76).
    static func exitEntry(in mem: [UInt8]) -> Int? {
        guard let handler = find(nextLevelHandler, in: mem, from: 0x0803, to: 0x2000) else { return nil }
        let regions = [0x0803 ..< 0x2000, 0x8EF0 ..< 0x9500]
        let jmp: [UInt8] = [0x4C, UInt8(handler & 0xFF), UInt8(handler >> 8)]
        let sites = regions.flatMap { r in
            (r.lowerBound + 2 ..< r.upperBound - 2).filter { Array(mem[$0 ..< $0 + 3]) == jmp && mem[$0 - 2] == 0xA0 }
        }.map { $0 - 2 }
        guard sites.count == 1, let site = sites.first else { return nil }
        var targets = Set<Int>()
        for r in regions {
            for i in r.lowerBound ..< r.upperBound - 2 where mem[i] == 0x4C || mem[i] == 0x20 {
                let t = Int(mem[i + 1]) | Int(mem[i + 2]) << 8
                if (site - 0x200 ... site).contains(t), !(t ... site).contains(i) { targets.insert(t) }
            }
        }
        for t in targets.sorted() {
            var pc = t
            scan: while pc < site {
                guard let info = CPU6502.table[Int(mem[pc])] else { break }
                switch info.op {
                case .rts, .rti, .brk: break scan
                case .jmp where info.mode == .ind: break scan
                case .jmp where Int(mem[pc + 1]) | Int(mem[pc + 2]) << 8 != pc + 3: break scan
                default: pc += CPU6502.length(info.mode)
                }
            }
            if pc == site { return t }
        }
        return nil
    }

    /// `LDA #2 / STA MENU_MODE`: a level's way to the next level.
    private static let nextLevelHandler = [0xA9, 0x02] + instruction(0x8D, \.menuMode)

    /// An instruction with a symbol's address as its operand, as code has it:
    /// `instruction(0xAD, \.objRoom)` is `LDA OBJ_ROOM`.
    static func instruction<S: Symbol>(_ opcode: UInt8, _ s: KeyPath<GameSymbols, S>) -> [UInt8] {
        let a = GameSymbols.address(s)
        return [opcode, UInt8(a & 0xFF), UInt8(a >> 8)]
    }

    static func find(_ pattern: [UInt8], in mem: [UInt8], from: Int, to: Int) -> Int? {
        guard to - pattern.count >= from else { return nil }
        for i in from ... to - pattern.count where mem[i] == pattern[0] {
            if Array(mem[i ..< i + pattern.count]) == pattern { return i }
        }
        return nil
    }

    // MARK: saved games

    /// Saved games on a storage diskette.
    ///
    /// The directory is at page 32 (16-character names); slot k occupies 107
    /// pages from page 117 + 107k: $5E00 (1 page), $D000-$EFFF (32),
    /// $6000-$94FF (53), $0B00-$1FFF (21).  Byte $44 of the $5E00 page is the
    /// menu's world index ($02D2) but is not always right, so the level is
    /// identified by comparing the room walls with the `reference` worlds.
    func savedGames(on storage: DiskImage, reference: [World]) -> [World] {
        guard let engine = disks.sideA ?? disks.sideB else { return [] }
        let directory = storage.read(page: 32, length: 256)
        var games: [World] = []
        for slot in 0 ..< 4 {
            let first = 117 + 107 * slot
            guard first + 107 <= 560, storage.hasWorld(atPage: first + 33) else { continue }
            let nameBytes = directory[slot * 16 ..< slot * 16 + 16].map { $0 & 0x7F }
            let name = String(decoding: nameBytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            var mem = [UInt8](repeating: 0, count: 0x10000)
            let s = GameCatalog.engineMain
            mem.replaceSubrange(s.address ..< s.address + s.length, with: engine.read(page: s.page, length: s.length))
            let header = storage.read(page: first, length: 256)
            mem.replaceSubrange(0x5E00 ..< 0x5F00, with: header)
            mem.replaceSubrange(0xD000 ..< 0xF000, with: storage.read(page: first + 1, length: 32 * 256))
            mem.replaceSubrange(0x6000 ..< 0x9500, with: storage.read(page: first + 33, length: 53 * 256))
            mem.replaceSubrange(0x0B00 ..< 0x2000, with: storage.read(page: first + 86, length: 21 * 256))
            let wallBytes = GameSymbols.address(\.roomWalls) ..< GameSymbols.address(\.roomWalls) + World.roomCount * 30
            let walls = mem[wallBytes]
            let match = reference.max { a, b in
                zip(a.mem[wallBytes], walls).count { $0 == $1 } < zip(b.mem[wallBytes], walls).count { $0 == $1 }
            }
            let level = match.map { $0.name.components(separatedBy: " – ").first ?? $0.name } ?? "?"
            // The save holds language card bank 1 at $D000.  Restoring reloads the
            // engine and the level code from the program disk; take them from the
            // matching world (the saved $0B00-$1FFF stays).
            let bank1 = Array(mem[0xD000 ..< 0xE000])
            if let match {
                for r in [0x0803 ..< 0x0B00, 0xB8E0 ..< 0xC000, 0xD000 ..< 0xE000, 0xF000 ..< 0x10000] {
                    mem.replaceSubrange(r, with: match.mem[r])
                }
            }
            // RESTORE_GAME ($450C) puts back the chip table and four engine variables,
            // HELD_OBJECT first.  Some saves have an empty header (not written by the
            // v1.0/v1.1 save code); restored, the player would hold itself (object 0)
            // and the main loop hang, so they keep the program disk's values.
            if header[0 ..< 0x44].contains(where: { $0 != 0 }) {
                let chipPins = GameSymbols.address(\.chipPins)
                mem.replaceSubrange(chipPins ..< chipPins + 0x40, with: header[0 ..< 0x40])
                let restored: [ByteSymbol] = [\.heldObject, \.held9C27, \.buttonEdgesA5C9, \.buttonEdgesA5CA]
                for (i, variable) in restored.enumerated() {
                    mem[variable] = header[0x40 + i]
                }
            }
            WorldBuilder.passCopyProtection(&mem)
            // Code below $0B00 is not saved (Level 5 calls its code rooms from $08DA),
            // so take the matching world's code rooms whose bytes are unchanged.
            var codeRooms = World.findCodeRooms(in: mem)
            for (r, code) in match?.codeRooms ?? [:] where codeRooms[r] == nil {
                let w = wallBytes.lowerBound + r * 30 ..< wallBytes.lowerBound + r * 30 + 30
                if mem[w] == match?.mem[w] { codeRooms[r] = code }
            }
            let engine = match?.engine ?? .levels
            games.append(World(id: "\(storage.name)#\(slot)",
                               name: "\(name.isEmpty ? "Slot \(slot + 1)" : name) (\(level))",
                               kind: .savedGame, mem: mem, bank1: bank1, codeRooms: codeRooms,
                               engine: engine, codeCheck: check(mem, engine)))
        }
        return games
    }
}
