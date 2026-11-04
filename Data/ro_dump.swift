// Writes every world's memory as its main loop starts (after the world's
// start-up code, as the app runs it): DIR/<id>.main.bin (64K, language card
// bank 2 at $D000) and DIR/<id>.bank1.bin ($D000-$DFFF bank 1), to
// disassemble with dis6502.py.  Build and run with ro_dump.sh.
import Foundation
import MOS6502

@main
struct Dump {
    static func main() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2 else {
            print("usage: ro_dump DIR DISK.dsk... (program sides, storage disks)")
            exit(2)
        }
        let dir = URL(fileURLWithPath: args.removeFirst())
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var set = DiskSet(version: nil)
        var storage: [DiskImage] = []
        for p in args {
            let d = try DiskImage(name: (p as NSString).lastPathComponent, data: Data(contentsOf: URL(fileURLWithPath: p)))
            switch d.role {
            case .programSide(let side, let version):
                set.version = version
                if side == .a { set.sideA = d } else { set.sideB = d }
            case .storage: storage.append(d)
            default: break
            }
        }
        let builder = WorldBuilder(disks: set)
        let (worlds, errors) = builder.buildAll()
        errors.forEach { print("build error: \($0)") }
        for world in worlds + storage.flatMap(builder.savedGames) {
            let loop = try GameScreen(world: world).loop(room: nil)
            let name = world.id.replacingOccurrences(of: "/", with: "_")
            try Data(loop.memory).write(to: dir.appendingPathComponent("\(name).main.bin"))
            try Data(loop.bank1).write(to: dir.appendingPathComponent("\(name).bank1.bin"))
            print("\(name): \(world.name), \(world.engine)")
        }
    }
}
