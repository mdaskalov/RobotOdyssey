import SwiftUI

/// The rooms as they connect (WorldMap), in the world panel: each island of
/// rooms side by side with their numbers, exits that lead elsewhere as badges
/// on the room's edge, then the rooms without exits as in the grid; wider
/// than the panel, it scrolls across.  It keeps the selected room in view
/// while the panel shows it (`follow`), so it follows the player.
struct WorldMapView: View {
    /// Scrolls the world panel to a room's row if it shows the map (its
    /// frame in the panel's contents); false if it doesn't.
    typealias Follow = (_ row: RoomRow, _ map: CGRect) -> Bool

    var model: ViewerModel
    let world: World
    let map: WorldMap
    /// Tiles as a fraction of a full-size thumbnail (280 x 192).
    let zoom: Double
    /// The width to lay the islands out in (wider if an island is).
    let width: CGFloat
    let follow: Follow
    /// The room just clicked on the map: already in view.
    @State private var clicked: Int?
    /// The rooms' middles (y) in the map, where their rows are.
    @State private var rows: [Int: CGFloat] = [:]
    @State private var placed = Placed()

    private static let gap: CGFloat = 2
    /// The map's coordinate space, which scrolls across but not up or down.
    private static let space = "WorldMapView"

    var body: some View {
        let tile = CGSize(width: 280 * zoom, height: 192 * zoom)
        let widest = CGFloat(map.islands.map(\.columns).max() ?? 1) * (tile.width + Self.gap)
        let width = max(self.width, widest)
        ScrollViewReader { across in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 16) {
                    FlowLayout(width: width, spacing: 24) {
                        ForEach(map.islands.indices, id: \.self) { i in
                            island(map.islands[i], tile: tile)
                        }
                    }
                    let others = map.unconnected.filter { world.isRoomUsed($0) || model.showEmptyRooms }
                    if !others.isEmpty {
                        Text("Not connected").font(.subheadline).foregroundStyle(.secondary)
                        FlowLayout(width: width, spacing: 6) {
                            ForEach(others, id: \.self) { r in
                                place(RoomCell(model: model, world: world, room: r).frame(width: tile.width), r)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .coordinateSpace(.named(Self.space))
            .background(alignment: .topLeading) {
                // Outside the map's own scroll view, which would take the scroll itself.
                ZStack(alignment: .topLeading) {
                    ForEach(rows.keys.sorted(), id: \.self) { r in
                        Color.clear
                            .frame(width: 1, height: 1)
                            .id(RoomRow(room: r))
                            .padding(.top, max(rows[r, default: 0] - 0.5, 0))
                    }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(WorldPanel.contents)) } action: { placed.map = $0 }
            .task(id: world.id) {
                await Task.yield()                      // once laid out
                reveal(model.selectedRoom, across)
            }
            .onChange(of: model.selectedRoom) { _, room in
                if room != clicked {
                    withAnimation { reveal(room, across) }
                }
                clicked = nil
            }
        }
    }

    /// Brings `room` into view: up or down in the panel (`follow`), and
    /// across in the map.
    private func reveal(_ room: Int, _ across: ScrollViewProxy) {
        if follow(RoomRow(room: room), placed.map) {
            across.scrollTo(RoomAnchor(room: room), anchor: .center)
        }
    }

    /// A room of the map: click it to select it; notes its row (`rows`).
    private func place(_ view: some View, _ room: Int) -> some View {
        view
            .onTapGesture { click(room) }
            .id(RoomAnchor(room: room))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).midY } action: { rows[room] = $0 }
    }

    private func island(_ island: WorldMap.Island, tile: CGSize) -> some View {
        Grid(horizontalSpacing: Self.gap, verticalSpacing: Self.gap) {
            ForEach(0 ..< island.rows, id: \.self) { row in
                GridRow {
                    ForEach(0 ..< island.columns, id: \.self) { column in
                        if let r = island.rooms[WorldMap.Cell(column: column, row: row)] {
                            place(MapRoom(model: model, world: world, room: r, exits: map.exits[r] ?? [])
                                .frame(width: tile.width, height: tile.height), r)
                        } else {
                            Color.clear.frame(width: tile.width, height: tile.height)
                        }
                    }
                }
            }
        }
    }

    private func click(_ room: Int) {
        clicked = room
        model.selectedRoom = room
    }
}

/// A room's place to scroll to; plain numbers would also match the islands,
/// rows and columns (their ForEach ids).
private struct RoomAnchor: Hashable {
    let room: Int
}

/// A room's row on the map: where the world panel scrolls to, to show it.
struct RoomRow: Hashable {
    let room: Int
}

/// Where the map is in the world panel's contents: not observed, as the
/// panel asks only when a room is to be shown.
private final class Placed {
    var map = CGRect.zero
}

/// A room on the map: its number in the corner, and a badge on each edge
/// whose exit leads to a room that isn't next to it (click to go there).
private struct MapRoom: View {
    var model: ViewerModel
    let world: World
    let room: Int
    let exits: [WorldMap.Exit]

    var body: some View {
        RoomImage(model: model, world: world, room: room, showEmpty: true)
            .overlay(alignment: .topLeading) {
                Text(hex(room))
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .background(.black.opacity(0.6))
            }
            .overlay {
                ForEach(exits, id: \.self) { exit in
                    Button {
                        model.selectedRoom = exit.room
                    } label: {
                        Text(exit.direction.arrow + hex(exit.room))
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 3)
                            .background(.yellow.opacity(0.85), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Exit \(exit.direction.arrow) leads to \(roomTitle(exit.room))")
                    .padding(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: exit.direction.edge)
                }
            }
            .overlay {
                if room == model.selectedRoom { Rectangle().stroke(Color.accentColor, lineWidth: 3) }
            }
            .contentShape(Rectangle())
            .help(roomTitle(room))
    }
}

private extension Room.Direction {
    var arrow: String {
        switch self {
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        }
    }

    var edge: Alignment {
        switch self {
        case .up: .top
        case .down: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }
}

/// Places its subviews left to right at their ideal size, starting a new row
/// where the next one would pass `width`.
private struct FlowLayout: Layout {
    let width: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, origin) in zip(subviews, arrange(subviews).origins) {
            view.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, right: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            right = max(right, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (origins, CGSize(width: right, height: y + rowHeight))
    }
}
