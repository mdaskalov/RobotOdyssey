import Foundation

/// The rooms laid out as they connect: an exit is shown by putting the room
/// it leads to next to its room, on that side.  The links need not form a
/// plane (the sewer mazes lead back into themselves, Level 2's skyway wraps
/// around, some exits are one-way, Level 4's edges all lead to room $3F), so
/// the layout is the one found to show the most exits (a two-way exit counts
/// twice): the rooms are placed best first, each where it shows the most
/// exits to the rooms placed so far, then moved around by simulated annealing
/// with a fixed seed, so a world always gets the same map.  Rooms shown next
/// to each other form an island; exits that don't lead to the room next door
/// are listed in `exits`.
nonisolated struct WorldMap {
    struct Cell: Hashable {
        let column, row: Int

        func step(_ d: Room.Direction) -> Cell {
            switch d {
            case .up: Cell(column: column, row: row - 1)
            case .down: Cell(column: column, row: row + 1)
            case .left: Cell(column: column - 1, row: row)
            case .right: Cell(column: column + 1, row: row)
            }
        }

        func offset(_ columns: Int, _ rows: Int) -> Cell {
            Cell(column: column + columns, row: row + rows)
        }
    }

    /// Rooms that lie next to each other; cell (0, 0) is the top left.
    struct Island {
        let rooms: [Cell: Int]
        let columns, rows: Int
    }

    /// An exit whose room isn't the one next door on the map.
    struct Exit: Hashable {
        let direction: Room.Direction
        let room: Int
    }

    /// The player's island first, the others by size.
    let islands: [Island]
    let exits: [Int: [Exit]]
    /// Rooms without exits that no exit leads to (robot interiors, code
    /// rooms, unused rooms).
    let unconnected: [Int]

    /// Annealing steps per room with exits: twice what every world needs to
    /// find its best layout with any of 8 seeds tried (Level 2, 51 rooms,
    /// is the slowest).
    private static let stepsPerRoom = 4000

    init(world: World) {
        let rooms = (0 ..< World.roomCount).map(world.room)
        var layout = Layout()
        for r in rooms.indices {
            for d in Room.Direction.allCases {
                let t = rooms[r].link(d)
                if t != r, t < World.roomCount { layout.link(r, d, t) }
            }
        }
        let player = world.object(0).room
        let connected = rooms.indices.filter { !layout.neighbours[$0].isEmpty }
        layout.placeBestFirst(seeds: [player] + connected)
        layout.anneal(steps: Self.stepsPerRoom * connected.count)
        islands = layout.islands(first: player)

        var exits: [Int: [Exit]] = [:]
        for island in islands {
            for (cell, r) in island.rooms {
                for d in Room.Direction.allCases {
                    let t = rooms[r].link(d)
                    if t != r, t < World.roomCount, island.rooms[cell.step(d)] != t {
                        exits[r, default: []].append(Exit(direction: d, room: t))
                    }
                }
            }
        }
        self.exits = exits
        unconnected = rooms.indices.filter { layout.neighbours[$0].isEmpty }
    }
}

nonisolated extension WorldMap {
    /// The rooms with exits on an endless grid.
    private struct Layout {
        /// The rooms each room should lie next to, in the direction they
        /// lie in: where its exits lead, and the rooms whose exits lead to
        /// it.  A two-way exit is listed twice.
        private(set) var neighbours = [[(room: Int, direction: Room.Direction)]](repeating: [], count: World.roomCount)
        private var at = [Cell?](repeating: nil, count: World.roomCount)
        private var cells: [Cell: Int] = [:]

        mutating func link(_ r: Int, _ d: Room.Direction, _ t: Int) {
            neighbours[r].append((t, d))
            neighbours[t].append((r, d.opposite))
        }

        /// How many of the exits from and to `r` it shows at `cell`.
        private func shown(_ r: Int, at cell: Cell) -> Int {
            neighbours[r].count { at[$0.room] == cell.step($0.direction) }
        }

        /// How many exits from and to `rooms` they show, doubled: an exit
        /// between two of them counts once from each side.
        private func shown(_ rooms: [Int], inside: [Bool]) -> Int {
            var n = 0
            for r in rooms {
                for (t, d) in neighbours[r] where at[t] == at[r]!.step(d) { n += inside[t] ? 1 : 2 }
            }
            return n
        }

        private mutating func put(_ rooms: [Int], _ to: [Cell]) {
            for r in rooms { cells[at[r]!] = nil }
            for (r, cell) in zip(rooms, to) {
                at[r] = cell
                cells[cell] = r
            }
        }

        /// Places the rooms one at a time, each next to a placed room where
        /// it shows the most exits to the rooms placed so far.  When none
        /// is left that leads to or from them, the next seed starts a new
        /// area far to the right.
        mutating func placeBestFirst(seeds: [Int]) {
            var unplaced = (0 ..< World.roomCount).filter { !neighbours[$0].isEmpty }
            var origin = 0
            for seed in seeds where at[seed] == nil && !neighbours[seed].isEmpty {
                at[seed] = Cell(column: origin, row: 0)
                cells[at[seed]!] = seed
                unplaced.removeAll { $0 == seed }
                while true {
                    var best: (shown: Int, room: Int, cell: Cell)?
                    for r in unplaced {
                        for (t, d) in neighbours[r] {
                            guard let cell = at[t]?.step(d.opposite), cells[cell] == nil else { continue }
                            let n = shown(r, at: cell)
                            if n > best?.shown ?? 0 { best = (n, r, cell) }
                        }
                    }
                    guard let best else { break }
                    at[best.room] = best.cell
                    cells[best.cell] = best.room
                    unplaced.removeAll { $0 == best.room }
                }
                origin = cells.keys.map(\.column).max()! + World.roomCount
            }
        }

        /// Simulated annealing: each step moves a room to where it would
        /// show one of its exits (or one leading to it), alone, swapping
        /// with the room there, or with some or all of the rooms it shows
        /// exits to, into free cells.  A move that shows fewer exits is
        /// kept with a chance that shrinks as the temperature drops; the
        /// layout that showed the most is the result.
        mutating func anneal(steps: Int) {
            let rooms = (0 ..< World.roomCount).filter { at[$0] != nil }
            guard !rooms.isEmpty else { return }
            let sizes = [1, 1, 1, 2, 3, 5, 8, World.roomCount]
            var random = SplitMix64(state: 1)
            var inside = [Bool](repeating: false, count: World.roomCount)
            var total = rooms.reduce(0) { $0 + shown($1, at: at[$1]!) }
            var best = (shown: total, at: at)
            for step in 0 ..< steps {
                let temperature = 3 * Double(steps - step) / Double(steps) + 0.04
                let r = rooms[random.below(rooms.count)]
                let (t, d) = neighbours[r][random.below(neighbours[r].count)]
                let from = at[r]!, to = at[t]!.step(d.opposite)
                guard to != from else { continue }
                // r and the rooms it shows exits to, breadth first, not t
                let size = sizes[random.below(sizes.count)]
                var group = [r]
                inside[r] = true
                var i = 0
                while i < group.count, group.count < size {
                    let u = group[i]
                    for (v, e) in neighbours[u] where group.count < size && v != t && !inside[v] && at[v] == at[u]!.step(e) {
                        group.append(v)
                        inside[v] = true
                    }
                    i += 1
                }
                let columns = to.column - from.column, rows = to.row - from.row
                let moved = group.map { at[$0]!.offset(columns, rows) }
                let displaced = moved.compactMap { cells[$0] }.filter { !inside[$0] }
                let affected = group + displaced
                defer { for u in affected { inside[u] = false } }
                guard displaced.count <= (group.count == 1 ? 1 : 0) else { continue }
                for u in displaced { inside[u] = true }

                let before = shown(affected, inside: inside), old = affected.map { at[$0]! }
                put(affected, moved + displaced.map { _ in from })
                let change = shown(affected, inside: inside) - before
                if change >= 0 || random.unit() < exp(Double(change) / temperature) {
                    total += change
                    if total > best.shown { best = (total, at) }
                } else {
                    put(affected, old)
                }
            }
            at = best.at
            cells = [:]
            for r in rooms { cells[at[r]!] = r }
        }

        /// The rooms that show exits to each other, each from (0, 0): the
        /// island of `first` first, the others by size.
        func islands(first: Int) -> [Island] {
            var seen = [Bool](repeating: false, count: World.roomCount)
            var islands: [[Int]] = []
            for seed in [first] + Array(0 ..< World.roomCount) where at[seed] != nil && !seen[seed] {
                var island = [seed]
                seen[seed] = true
                var i = 0
                while i < island.count {
                    let r = island[i]
                    for (t, d) in neighbours[r] where !seen[t] && at[t] == at[r]!.step(d) {
                        island.append(t)
                        seen[t] = true
                    }
                    i += 1
                }
                islands.append(island)
            }
            return islands.enumerated()
                .sorted { ($0.element.contains(first) ? 1 : 0, $0.element.count, -$0.offset)
                    > ($1.element.contains(first) ? 1 : 0, $1.element.count, -$1.offset) }
                .map { _, rooms in
                    let columns = rooms.map { at[$0]!.column }, rows = rooms.map { at[$0]!.row }
                    let left = columns.min()!, top = rows.min()!
                    return Island(rooms: Dictionary(uniqueKeysWithValues: rooms.map { (at[$0]!.offset(-left, -top), $0) }),
                                  columns: columns.max()! - left + 1, rows: rows.max()! - top + 1)
                }
        }
    }

    /// SplitMix64, so the annealing makes the same moves on every run.
    private struct SplitMix64 {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }

        /// In 0 ..< 1.
        mutating func unit() -> Double { Double(next() >> 11) * 0x1p-53 }
    }
}

nonisolated extension Room.Direction {
    var opposite: Room.Direction {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }
}
