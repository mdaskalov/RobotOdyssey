// The world maps (RobotOddyssey/Model/WorldMap.swift) as text: for every
// world on the disks, how many of its exits the map shows as rooms next to
// each other, the time it took, its islands with the room numbers (the
// player's room in brackets) and the exits left as badges.
//
// Build and run with ro_map.sh (compiles this file together with the app's
// sources):
//
//   ./ro_map.sh DISK.dsk...    (program sides A and B)
import Foundation

@main
struct MapTool {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else {
            print("usage: ro_map.sh DISK.dsk... (program sides)")
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
        guard !worlds.isEmpty else {
            print("no worlds on the disks")
            exit(1)
        }
        for world in worlds { printMap(world) }
    }

    static func printMap(_ world: World) {
        let start = Date()
        let map = WorldMap(world: world)
        let time = Date().timeIntervalSince(start)
        let exits = WorldMap.links(world).reduce(0) { $0 + $1.count }
        let badges = map.exits.values.reduce(0) { $0 + $1.count }
        print("\(world.name): \(exits - badges) of \(exits) exits shown, "
              + "islands \(map.islands.map { String($0.rooms.count) }.joined(separator: "+")) rooms, "
              + String(format: "%.0f ms", time * 1000))
        let player = world.object(0).room
        for island in map.islands {
            for row in 0 ..< island.rows {
                let line = (0 ..< island.columns).map { column -> String in
                    guard let r = island.rooms[WorldMap.Cell(column: column, row: row)] else { return " .. " }
                    return r == player ? "[\(hex(r))]" : " \(hex(r)) "
                }
                print("  " + line.joined())
            }
            print()
        }
        let arrows: [Room.Direction: String] = [.up: "↑", .down: "↓", .left: "←", .right: "→"]
        let list = map.exits.keys.sorted().flatMap { r in map.exits[r]!.map { "\(hex(r))\(arrows[$0.direction]!)\(hex($0.room))" } }
        if !list.isEmpty { print("  badges: " + list.joined(separator: " ") + "\n") }
    }

    static func hex(_ n: Int) -> String { String(format: "%02X", n) }
}
