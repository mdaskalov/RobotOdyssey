import Foundation

/// The program disk (side A and/or B) of one version, plus optional storage disks.
nonisolated struct DiskSet {
    /// nil: a version the loader's file table doesn't tell (`LoaderSymbols`).
    var version: Version?
    var sideA: DiskImage?
    var sideB: DiskImage?

    func disk(_ side: DiskSide) -> DiskImage? { side == .a ? sideA : sideB }

    var versionName: String { version?.rawValue ?? "1.x" }

    /// A file's bytes as the loader loads them (v1.0's lengths for v1.0);
    /// nil if its side is missing.
    func read(_ s: Segment) -> [UInt8]? {
        let length = version == .v1_0 ? GameCatalog.lengthsV10[s.side]?[s.page] ?? s.length : s.length
        return disk(s.side)?.read(page: s.page, length: length)
    }

    var title: String {
        let names = [sideA?.name, sideB?.name].compactMap { $0 }.joined(separator: " + ")
        return "Robot Odyssey I v\(versionName) (\(names))"
    }
}

/// Builds world memory images the way the game's loader does.  It knows
/// which engine it loads with a world and the disks' version, so it checks
/// the engine code against the symbols' fingerprints right away (`CodeCheck`):
/// the natives replace only the routines whose code is the version's.
nonisolated struct WorldBuilder {
    let disks: DiskSet

    private func load(_ segments: [Segment], into mem: inout [UInt8]) throws {
        for s in segments {
            guard let bytes = disks.read(s) else { throw DiskError.missingSide(s.side.rawValue) }
            mem.replaceSubrange(s.address ..< s.address + bytes.count, with: bytes)
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

    /// What boot stage 2 and the menu leave for the worlds: the reset vector
    /// at the disk controller's boot ROM, where a world hands back to the
    /// loader (BOOT2_ENTRY: $C600 and the power-up byte), and the copy
    /// protection passed.  The loader's last step before it starts a world
    /// (COPY_FLAG_START $4563, COPY_FLAG_RESTORE $452D) is COPY_PROTECTION_OK =
    /// BOOT_CHECK_RESULT AND MENU_CHECK_RESULT, the results of the checks at
    /// boot and in the menu (bit 7 set: passed).  The app starts its worlds
    /// without either, so it sets all three as an original disk leaves them.
    /// On the disk the flag is $00, and with bit 7 clear every world but Robot
    /// Anatomy skips the soldering pen (Docs/CopyProtection.md).
    static func passCopyProtection(_ mem: inout [UInt8]) {
        let reset = GameSymbols.address(\.resetVector)
        mem.replaceSubrange(reset ..< reset + 3, with: [0x00, 0xC6, 0xC6 ^ 0xA5])
        mem[LoaderSymbols.address(\.bootCheckResult)] = 0x80
        mem[LoaderSymbols.address(\.menuCheckResult)] = 0x80
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

    /// Saved games on a storage diskette, each as RESTORE_GAME restores it.
    ///
    /// The directory is page 32: an entry of 18 letters per slot.  Slot k
    /// occupies 107 pages from page 118 + 107k (SAVE_GAME_WRITE): $D000-$EFFF
    /// (32, language card bank 1, then $E000), $6000-$94FF (53), $0B00-$1FFF
    /// (21) and the header page $5E00: the chip table, four engine variables,
    /// WORLD_INDEX at $44 (Docs/DiskLayout.md).  Restoring loads these, then
    /// the engine from the program disk (but the levels' $1A50 piece, saved
    /// with $0B00-$1FFF), puts back the header's values and loads the world's
    /// code at $0803 (RESTORE_LOAD_CODE).
    func savedGames(on storage: DiskImage) -> [World] {
        let directory = storage.read(page: 32, length: 256)
        var games: [World] = []
        for slot in 0 ..< 4 {
            let first = 118 + 107 * slot
            guard storage.hasWorld(atPage: first + 32) else { continue }
            let header = storage.read(page: first + 106, length: 256)
            let index = Int(header[0x44])
            guard index < GameCatalog.byWorldIndex.count, let def = GameCatalog.world(GameCatalog.byWorldIndex[index]),
                  let engineMain = disks.read(GameCatalog.engineMain) else { continue }
            let nameBytes = directory[slot * 18 ..< slot * 18 + 18].map { $0 & 0x7F }
            let name = String(decoding: nameBytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            var mem = [UInt8](repeating: 0, count: 0x10000)
            mem.replaceSubrange(0xD000 ..< 0xF000, with: storage.read(page: first, length: 32 * 256))
            mem.replaceSubrange(0x6000 ..< 0x9500, with: storage.read(page: first + 32, length: 53 * 256))
            mem.replaceSubrange(0x0B00 ..< 0x2000, with: storage.read(page: first + 85, length: 21 * 256))
            mem.replaceSubrange(0x5E00 ..< 0x5F00, with: header)
            let bank1 = Array(mem[0xD000 ..< 0xE000])
            let s = GameCatalog.engineMain
            mem.replaceSubrange(s.address ..< s.address + engineMain.count, with: engineMain)
            do {
                try load(GameCatalog.segments(of: def.engine).filter { $0.address > 0x2000 }, into: &mem)
                try load(def.code.filter { $0.address == GameSymbols.address(\.worldStart) }, into: &mem)
            } catch {
                continue
            }
            // RESTORE_GAME ($450C) puts back the chip table and four engine
            // variables, HELD_OBJECT first.  A header of zeros (the save code
            // never writes one: HELD_OBJECT is $FF when nothing is held) would
            // have the player hold itself (object 0) and the main loop hang, so
            // such a header leaves the program disk's values.
            if header[0 ..< 0x44].contains(where: { $0 != 0 }) {
                let chipPins = GameSymbols.address(\.chipPins)
                mem.replaceSubrange(chipPins ..< chipPins + 0x40, with: header[0 ..< 0x40])
                let restored: [ByteSymbol] = [\.heldObject, \.grabbedObject, \.heldDX, \.heldDY]
                for (i, variable) in restored.enumerated() {
                    mem[variable] = header[0x40 + i]
                }
            }
            mem[\.worldIndex] = UInt8(index)
            WorldBuilder.passCopyProtection(&mem)
            let level = def.name.components(separatedBy: " – ").first ?? def.name
            games.append(World(id: "\(storage.name)#\(slot)",
                               name: "\(name.isEmpty ? "Slot \(slot + 1)" : name) (\(level))",
                               kind: .savedGame, mem: mem, bank1: bank1, engine: def.engine, codeCheck: check(mem, def.engine)))
        }
        return games
    }
}
