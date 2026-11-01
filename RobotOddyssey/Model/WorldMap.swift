import Foundation

/// The rooms laid out as they connect: each exit puts its room next to the
/// one it leads from.  The links need not form a plane (mazes lead back into
/// themselves, some exits are one-way, Level 4's edges all lead to room $3F),
/// so the layout grows from the player's room along two-way links first,
/// then one-way links, and never puts two rooms in one cell.  Exits that
/// don't lead to the room next door are listed in `exits`; rooms that can't
/// be reached from there start islands of their own.
struct WorldMap {
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

    init(world: World) {
        let rooms = (0 ..< World.roomCount).map(world.room)
        func target(_ r: Int, _ d: Room.Direction) -> Int? {
            let t = rooms[r].link(d)
            return t == r || t >= World.roomCount ? nil : t
        }
        var connected = Set<Int>()
        for r in rooms.indices {
            for d in Room.Direction.allCases {
                if let t = target(r, d) { connected.formUnion([r, t]) }
            }
        }

        var placed = Set<Int>()
        var islands: [Island] = []
        let player = world.object(0).room
        for seed in [player] + connected.sorted() where connected.contains(seed) && !placed.contains(seed) {
            var cells = [Cell(column: 0, row: 0): seed]
            var at = [seed: Cell(column: 0, row: 0)]
            var order = [seed]
            func place(_ r: Int, _ cell: Cell) -> Bool {
                guard !placed.contains(r), at[r] == nil, cells[cell] == nil else { return false }
                cells[cell] = r
                at[r] = cell
                order.append(r)
                return true
            }
            // Breadth first along two-way exits from `start` on in `order`.
            func grow(from start: Int) {
                var i = start
                while i < order.count {
                    let r = order[i]
                    for d in Room.Direction.allCases {
                        if let t = target(r, d), target(t, d.opposite) == r { _ = place(t, at[r]!.step(d)) }
                    }
                    i += 1
                }
            }
            grow(from: 0)
            // Then one-way exits: a room goes where its own exit leads from,
            // else where an exit leads to it.
            let candidates = connected.sorted()
            var added = true
            while added {
                added = false
                for own in [true, false] where !added {
                    for r in order {
                        for d in Room.Direction.allCases {
                            let next = at[r]!.step(d)
                            if own {
                                for u in candidates where target(u, d.opposite) == r && place(u, next) { added = true }
                            } else if let t = target(r, d), place(t, next) {
                                added = true
                            }
                        }
                    }
                }
                if added { grow(from: 0) }
            }
            placed.formUnion(order)
            let minColumn = cells.keys.map(\.column).min()!, minRow = cells.keys.map(\.row).min()!
            let shifted = Dictionary(uniqueKeysWithValues: cells.map { cell, r in
                (Cell(column: cell.column - minColumn, row: cell.row - minRow), r)
            })
            islands.append(Island(rooms: shifted,
                                  columns: cells.keys.map(\.column).max()! - minColumn + 1,
                                  rows: cells.keys.map(\.row).max()! - minRow + 1))
        }
        if let first = islands.first {
            islands = [first] + islands.dropFirst().enumerated()
                .sorted { ($0.element.rooms.count, -$0.offset) > ($1.element.rooms.count, -$1.offset) }
                .map(\.element)
        }

        var exits: [Int: [Exit]] = [:]
        for island in islands {
            for (cell, r) in island.rooms {
                for d in Room.Direction.allCases {
                    if let t = target(r, d), island.rooms[cell.step(d)] != t {
                        exits[r, default: []].append(Exit(direction: d, room: t))
                    }
                }
            }
        }
        self.islands = islands
        self.exits = exits
        unconnected = (0 ..< World.roomCount).filter { !connected.contains($0) }
    }
}

extension Room.Direction {
    var opposite: Room.Direction {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }
}
