// The app's symbol maps (RobotOdyssey/Symbols) as Mariani/AppleWin symbol
// files, and the fingerprints of their routines on the disks.
//
// Build and run with ro_symbols.sh (compiles this file together with the
// app's sources):
//
//   ./ro_symbols.sh [OUTDIR]            write the .sym files (default: this folder)
//   ./ro_symbols.sh --code DISK.dsk...  every routine with code in the map, in
//                                       every world on the disks: the MD5 of its
//                                       ranges there and whether it matches
//
// To map a newly ported routine: give it its code ranges with md5 "" in
// GameSymbols, run --code on the disks of both versions and copy the MD5s.
import Apple2Kit
import Foundation

@main
struct SymbolTool {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--code" {
            try printCode(disks: Array(args.dropFirst()))
        } else {
            try writeSymbolFiles(to: URL(fileURLWithPath: args.first ?? "."))
        }
    }

    // MARK: .sym files

    /// Each file (Apple2Kit's `SymbolFile`): the symbols of an engine in a
    /// version, Level 1's own with the levels' (`L1_`); the loader's.
    static func writeSymbolFiles(to dir: URL) throws {
        let levels = Variant(engine: .levels, version: .v1_1)
        let files: [(String, String, Variant, Bool)] = [
            ("RobotOdyssey.sym", "game symbols, the Robotropolis levels v1.1", levels, true),
            ("RobotOdyssey_v1.0.sym", "game symbols, the Robotropolis levels v1.0", Variant(engine: .levels, version: .v1_0), true),
            ("RobotOdysseyKit.sym", "game symbols, Robot Anatomy and Toolkit", Variant(engine: .kit, version: .v1_1), false),
            ("RobotOdysseyLab.sym", "game symbols, the Innovation Lab and its tutorial", Variant(engine: .lab, version: .v1_1), false),
        ]
        for (name, title, variant, withLevel1) in files {
            var file = SymbolFile(comments: comments(title))
            file.add(variant.symbols.named)
            if withLevel1 { file.add(Level1Symbols.named, prefix: "L1_") }
            try write(file, name, to: dir)
        }
        let loader = SymbolFile(LoaderSymbols.map, comments: comments("boot/menu loader symbols, v1.0 and v1.1"))
        try write(loader, "RobotOdysseyLoader.sym", to: dir)
    }

    static func comments(_ title: String) -> [String] {
        ["Robot Odyssey \(title)",
         "Robot Odyssey I (Apple II) - written by Data/ro_symbols.sh from RobotOdyssey/Symbols",
         "Names ending in _Q are guesses; L1_ names apply to Level 1 code only."]
    }

    static func write(_ file: SymbolFile, _ name: String, to dir: URL) throws {
        try file.write(to: dir.appendingPathComponent(name))
        print("\(name): \(file.symbols.count) symbols")
    }

    // MARK: fingerprints

    static func printCode(disks paths: [String]) throws {
        var sets: [String: DiskSet] = [:]
        for p in paths {
            let d = try DiskImage(name: (p as NSString).lastPathComponent, data: Data(contentsOf: URL(fileURLWithPath: p)))
            guard case .programSide(let side, let version) = d.role else { continue }
            var set = sets[version?.rawValue ?? "1.x"] ?? DiskSet(version: version)
            if side == .a { set.sideA = d } else { set.sideB = d }
            sets[set.versionName] = set
        }
        for (_, set) in sets.sorted(by: { $0.key < $1.key }) {
            guard let version = set.version else {
                print("\(set.title): version not recognized")
                continue
            }
            // Per variant, each routine's digest and the worlds that have it.
            var found: [Variant: [String: [String: [String]]]] = [:]
            for world in WorldBuilder(disks: set).buildAll().worlds {
                let v = Variant(engine: world.engine, version: version)
                for (name, symbol) in v.symbols.named {
                    guard let routine = symbol as? Routine, let code = routine.code else { continue }
                    found[v, default: [:]][name, default: [:]][code.digest(world.mem), default: []].append(world.name)
                }
            }
            for (v, routines) in found.sorted(by: { $0.key.description < $1.key.description }) {
                print("\(set.title), \(v):")
                for (name, digests) in routines.sorted(by: { $0.key < $1.key }) {
                    let routine = v.symbols.named.first { $0.name == name }!.symbol as! Routine
                    let code = routine.code!
                    let ranges = code.ranges.map { String(format: "$%04X-$%04X", $0.lowerBound, $0.upperBound - 1) }
                    for (digest, worlds) in digests.sorted(by: { $0.key < $1.key }) {
                        let status = code.md5.isEmpty ? "new" : (digest == code.md5 ? "ok" : "DIFFERS")
                        let which = digests.count > 1 ? "  (\(worlds.joined(separator: ", ")))" : ""
                        print("  \(name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(ranges.joined(separator: " "))  \(digest)  \(status)\(which)")
                    }
                }
            }
        }
    }
}
