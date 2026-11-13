import Apple2Kit
import Foundation
import MOS6502

/// The loader as the app runs it.  A world hands back to the loader by
/// rebooting (`JMP (RESET_VECTOR)` to the disk controller's boot ROM); the
/// disk in the drive boots, and boot stage 2, the loader on track 1 and the
/// menu run as original 6502 code (LoaderSymbols): on to the next level, the
/// menu and its worlds, saving and restoring games, loading and saving chips.
/// Natives stand in for what the app has no hardware for: the boot ROM and
/// boot stage 1 (`boot`), RWTS on a `DiskDrive` (`rwts`), the copy
/// protection's two nibble checks, which pass as on an original disk, and the
/// disk swaps: where the loader waits for a disk (AWAIT_SIDE), the drive takes
/// it.  One skips: Robotropolis' intro, unless switched off
/// (`Machine.switchedOff`, `skipIntro`): then it plays as on the Apple.
/// And the menu program's drawing runs as Swift (`menuNatives`, MenuDrawing).
/// `GameLoop` follows the loader into the world it starts.
/// Docs/Loader.md.
nonisolated enum Loader {
    /// The name of the native that steps over the intro: PLAY_INTRO.
    static let skipIntro = LoaderSymbols.name(of: \.playIntro)

    /// Puts the loader's natives on `machine`, with `drive`.
    static func install(on machine: Machine, drive: DiskDrive) {
        machine.drive = drive
        machine.hook(LoaderSymbols.address(\.slot6Boot), boot)
        machine.hook(LoaderSymbols.address(\.rwts), rwts)
        // The checks read the drive's nibbles; they find the signature, as on an original disk.
        machine.hook(LoaderSymbols.address(\.bootCopyCheck)) { m in
            m.apple.cpu.p |= CPU6502.Flag.carry
            m.apple.cpu.pc = UInt16(LoaderSymbols.address(\.bootCopyDone))
            return true
        }
        machine.hook(LoaderSymbols.address(\.menuCopyCheck)) { m in
            m.apple.cpu.p |= CPU6502.Flag.carry
            m.apple.cpu.returnFromSubroutine()
            return true
        }
        // Robotropolis' intro: stepped over, as a key press ends it at once.
        machine.hook(LoaderSymbols.address(\.playIntro), name: skipIntro) { m in
            m.apple.cpu.pc = UInt16(LoaderSymbols.address(\.playIntro) + 3)
            return true
        }
        // The disk asked for goes in before the loader reads which it is.
        machine.hook(LoaderSymbols.address(\.awaitSide)) { m in
            if let disk = DiskDrive.Disk(rawValue: Int(m.apple.cpu.mem[LoaderSymbols.address(\.wantedSide)])) {
                m.drive?.insert(disk)
            }
            return false
        }
        installMenuNatives(on: machine)
    }

    /// The boot ROM and boot stage 1 (DOS 3.3's, track 0 sector 0): sector 0
    /// to $0800, sectors 1-15 to BOOT2 ($4F00-$5DFF), then BOOT2_ENTRY with X
    /// the slot × 16.  Boot 1 also calls the monitor's SETKBD, SETVID and,
    /// past the display switches, SETWND (the loader's CHAR_OUT keeps to its
    /// window); it leaves the display alone.  A storage disk in the drive
    /// asks for the program disk: the drive takes a program side.
    static func boot(_ m: Machine) -> Bool {
        guard let drive = m.drive else { return false }
        if drive.inserted == .storage {
            _ = drive.insert(.sideA) || drive.insert(.sideB)
        }
        guard let track = drive.trackZero, drive.inserted != .storage else { return false }
        let cpu = m.apple.cpu
        cpu.mem.replaceSubrange(0x0800 ..< 0x0900, with: track[0 ..< 0x100])
        let boot2 = LoaderSymbols.address(\.boot2)
        cpu.mem.replaceSubrange(boot2 ..< boot2 + 0xF00, with: track[0x100 ..< 0x1000])
        let monitor: [(Int, UInt8)] = [
            (0x36, 0xF0), (0x37, 0xFD), (0x38, 0x1B), (0x39, 0xFD),     // CSW, KSW: COUT1, KEYIN
            (0x20, 0x00), (0x21, 0x28), (0x22, 0x00), (0x23, 0x18),     // the window: 40 × 24
            (0x25, 0x17), (0x28, 0xD0), (0x29, 0x07),                   // CV and BASL/BASH: the last line
            (0x2B, 0x60),                                               // the boot slot × 16
        ]
        for (address, value) in monitor { cpu.mem[address] = value }
        cpu.x = 0x60
        cpu.pc = UInt16(LoaderSymbols.address(\.boot2Entry))
        return true
    }

    /// RWTS ($5A00, DOS 3.3's; the IOB at A:Y, RWTS_IOB): seeks (0), reads
    /// (1), writes (2) or formats (4) on the drive's disk at once, and returns
    /// as RWTS does: the IOB's return code ($10 write-protected, $40 drive
    /// error) and the carry set on an error.
    static func rwts(_ m: Machine) -> Bool {
        guard let drive = m.drive else { return false }
        let cpu = m.apple.cpu
        let iob = Int(cpu.a) << 8 | Int(cpu.y)
        let track = Int(cpu.mem[iob + 4]), sector = Int(cpu.mem[iob + 5])
        let buffer = Int(cpu.mem[iob + 8]) | Int(cpu.mem[iob + 9]) << 8
        let sectorOK = track < 35 && sector < 16 && buffer <= 0xFF00
        var error: UInt8 = 0
        switch cpu.mem[iob + 12] {
        case 1:
            if sectorOK, let bytes = drive.read(track: track, sector: sector) {
                cpu.mem.replaceSubrange(buffer ..< buffer + 256, with: bytes)
            } else {
                error = DiskDrive.driveError
            }
        case 2:
            error = sectorOK ? drive.write(track: track, sector: sector, bytes: Array(cpu.mem[buffer ..< buffer + 256])) : DiskDrive.driveError
        case 4:
            error = drive.format()
        default:
            break
        }
        cpu.mem[iob + 13] = error
        if error == 0 { cpu.p &= ~CPU6502.Flag.carry } else { cpu.p |= CPU6502.Flag.carry }
        cpu.returnFromSubroutine()
        return true
    }

    /// The world whose code is at WORLD_START, as the loader loaded it from `disks`.
    static func world(in mem: [UInt8], disks: DiskSet) -> WorldDefinition? {
        let start = GameSymbols.address(\.worldStart)
        return GameCatalog.worlds.first { def in
            guard let code = def.code.first(where: { $0.address == start }), let bytes = disks.read(code) else { return false }
            return mem[start ..< start + bytes.count].elementsEqual(bytes)
        }
    }
}
