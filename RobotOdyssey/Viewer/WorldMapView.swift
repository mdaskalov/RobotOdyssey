import SwiftUI

/// The rooms as they connect (WorldMap), scrollable both ways: each island of
/// rooms side by side with their numbers, exits that lead elsewhere as badges
/// on the room's edge, then the rooms without exits as in the grid.  Keeps the
/// selected room in view, so it follows the player.
struct WorldMapView: View {
    var model: ViewerModel
    let world: World
    let map: WorldMap
    /// Tiles as a fraction of a full-size thumbnail (280 x 192).
    let zoom: Double
    /// The room just clicked on the map: already in view.
    @State private var clicked: Int?

    private static let gap: CGFloat = 2

    var body: some View {
        let tile = CGSize(width: 280 * zoom, height: 192 * zoom)
        GeometryReader { geo in
            let widest = CGFloat(map.islands.map(\.columns).max() ?? 1) * (tile.width + Self.gap)
            let width = max(geo.size.width - 32, widest)
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
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
                                    RoomCell(model: model, world: world, room: r)
                                        .frame(width: tile.width)
                                        .onTapGesture { click(r) }
                                        .id(RoomAnchor(room: r))
                                }
                            }
                        }
                    }
                    .padding()
                }
                .task(id: world.id) {
                    await Task.yield()                  // once laid out
                    proxy.scrollTo(RoomAnchor(room: model.selectedRoom), anchor: .center)
                }
                .onChange(of: model.selectedRoom) { _, room in
                    if room != clicked {
                        withAnimation { proxy.scrollTo(RoomAnchor(room: room), anchor: .center) }
                    }
                    clicked = nil
                }
            }
        }
    }

    private func island(_ island: WorldMap.Island, tile: CGSize) -> some View {
        Grid(horizontalSpacing: Self.gap, verticalSpacing: Self.gap) {
            ForEach(0 ..< island.rows, id: \.self) { row in
                GridRow {
                    ForEach(0 ..< island.columns, id: \.self) { column in
                        if let r = island.rooms[WorldMap.Cell(column: column, row: row)] {
                            MapRoom(model: model, world: world, room: r, exits: map.exits[r] ?? [])
                                .frame(width: tile.width, height: tile.height)
                                .onTapGesture { click(r) }
                                .id(RoomAnchor(room: r))
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
