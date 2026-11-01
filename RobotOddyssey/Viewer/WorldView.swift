import SwiftUI

/// How the rooms below the selected one are arranged.
enum RoomsLayout: String, CaseIterable, Identifiable {
    /// Room n at column n % 8, row n / 8.
    case grid = "Grid"
    /// As they connect (WorldMap).
    case map = "Map"
    var id: String { rawValue }
}

/// The selected room large, and below it, if shown, all rooms in an 8x8 grid
/// or on the map of how they connect (`RoomBrowser`).
struct WorldView: View {
    @Bindable var model: ViewerModel
    let world: World
    @FocusState private var focused: Bool
    @AppStorage("roomsHeight") private var roomsHeight = 320.0

    var body: some View {
        GeometryReader { geo in
            // The canvas keeps at least 160 points.
            let maxRooms = max(geo.size.height - 160, 100)
            VStack(spacing: 0) {
                RoomCanvas(model: model, world: world)
                    .focusable()
                    .focused($focused)
                    .focusEffectDisabled()
                    .onKeyPress(phases: [.down, .repeat]) { press in
                        if model.playing {
                            guard let code = AppleKeyboard.code(for: press) else { return .ignored }
                            model.type(code)
                            return .handled
                        }
                        switch press.key {
                        case .upArrow: model.go(.up)
                        case .downArrow: model.go(.down)
                        case .leftArrow: model.go(.left)
                        case .rightArrow: model.go(.right)
                        case .space: model.paused.toggle()
                        default: return .ignored
                        }
                        return .handled
                    }
                    .task(id: "\(world.id)#\(model.restarts)") {
                        await model.runGame(world: world)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showRooms {
                    VStack(spacing: 0) {
                        ResizeHandle(size: $roomsHeight, range: 100 ... maxRooms, panel: .bottom)
                        RoomBrowser(model: model, world: world)
                            .frame(height: min(roomsHeight, maxRooms))
                    }
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(.default, value: model.showRooms)  // as the inspector slides
        }
        .onAppear { focused = true }
    }
}

/// All rooms, in an 8x8 grid or on the map of how they connect; click one to select it.
private struct RoomBrowser: View {
    var model: ViewerModel
    let world: World
    @AppStorage("roomsLayout") private var layout = RoomsLayout.grid
    /// Map tiles as a fraction of a full-size thumbnail.
    @AppStorage("mapZoom") private var zoom = 0.5

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Rooms").font(.headline)
                Picker("Rooms", selection: $layout) {
                    ForEach(RoomsLayout.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Grid: room n at column n % 8, row n / 8. Map: the rooms as they connect.")
                Spacer()
                if layout == .map {
                    Slider(value: $zoom, in: 0.35 ... 1) { Text("Zoom") }
                        .frame(maxWidth: 200)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            if !model.thumbnailsReady {
                loading("Drawing the rooms…")
            } else if layout == .grid {
                ScrollView {
                    RoomGrid(model: model, world: world).padding([.horizontal, .bottom])
                }
            } else if let map = model.map(world) {
                WorldMapView(model: model, world: world, map: map, zoom: zoom)
            } else {
                loading("Laying out the map…")
            }
        }
        .task(id: "\(world.id)#\(model.mode.rawValue)#\(layout.rawValue)") {
            await model.prepareRooms(world: world, withMap: layout == .map)
        }
    }

    /// In place of the rooms while `prepareRooms` makes them.
    private func loading(_ title: String) -> some View {
        ProgressView(title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The room at 560x384 (scaled to fit), with selection of sprites and wires,
/// and tile grid; the point under the pointer goes to `ViewerModel.pointer`.
struct RoomCanvas: View {
    var model: ViewerModel
    let world: World

    var body: some View {
        let contents = model.contents(world)
        GeometryReader { geo in
            let k = geo.size.width / 560          // view points per image pixel
            ZStack(alignment: .topLeading) {
                if let img = model.image(world: world, room: model.selectedRoom) {
                    Image(decorative: img, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                if model.showGrid { TileGrid(k: k) }
                if let s = model.selection.flatMap(contents.sprite) {
                    Rectangle()
                        .stroke(.yellow, lineWidth: 2)
                        .frame(width: 28 * k + 4, height: 32 * k + 4)
                        .offset(x: CGFloat(s.x * 4) * k - 2, y: CGFloat((191 - s.y - 15) * 2) * k - 2)
                }
                if let w = model.selection.flatMap(contents.wire) {
                    // Through the middle of each unit: 4 x 2 image pixels.
                    Path { path in
                        path.addLines(w.points.map { CGPoint(x: CGFloat($0.x * 4 + 2) * k, y: CGFloat((191 - $0.y) * 2 + 1) * k) })
                    }
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .square))
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                var point: RoomPoint?
                if case .active(let p) = phase { point = logical(p, k: k) }
                if model.pointer != point { model.pointer = point }
            }
            .onTapGesture { p in
                let point = logical(p, k: k)
                model.selection = contents.item(atX: point.x, y: point.y)
            }
        }
        .aspectRatio(560.0 / 384.0, contentMode: .fit)
        .frame(maxWidth: 1120)
    }

    private func logical(_ p: CGPoint, k: CGFloat) -> RoomPoint {
        RoomPoint(x: Int(p.x / k / 4), y: 191 - Int(p.y / k / 2))
    }
}

private struct TileGrid: View {
    let k: CGFloat

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            for c in 1 ..< 20 {
                let x = CGFloat(c * 28) * k
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for r in 1 ..< 12 {
                let y = CGFloat(r * 32) * k
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(path, with: .color(.gray.opacity(0.5)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// All 64 rooms as thumbnails; room n is at column n % 8, row n / 8.
private struct RoomGrid: View {
    var model: ViewerModel
    let world: World

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
            ForEach(0 ..< World.roomCount, id: \.self) { r in
                RoomCell(model: model, world: world, room: r)
                    .onTapGesture { model.selectedRoom = r }
            }
        }
    }
}

/// A room's thumbnail with its number below, outlined when selected.
struct RoomCell: View {
    var model: ViewerModel
    let world: World
    let room: Int

    var body: some View {
        let isCode = world.codeRooms[room] != nil
        VStack(spacing: 2) {
            RoomImage(model: model, world: world, room: room, showEmpty: model.showEmptyRooms)
                .aspectRatio(280.0 / 192.0, contentMode: .fit)
                .overlay {
                    if room == model.selectedRoom { Rectangle().stroke(Color.accentColor, lineWidth: 3) }
                }
            Text(hex(room)).font(.caption2.monospaced())
                .foregroundStyle(world.isRoomUsed(room) && !isCode ? .primary : .tertiary)
        }
        .contentShape(Rectangle())
        .help(roomTitle(room) + (isCode ? " – 6502 code" : ""))
    }
}

/// A room's thumbnail; the selected room as the running loop shows it.
/// Unused rooms are blank unless `showEmpty`, code rooms always.
struct RoomImage: View {
    var model: ViewerModel
    let world: World
    let room: Int
    let showEmpty: Bool

    var body: some View {
        if world.codeRooms[room] != nil {
            Rectangle().fill(.quaternary)
                .overlay { Image(systemName: "curlybraces").foregroundStyle(.orange) }
        } else if showEmpty || world.isRoomUsed(room),
                  let image = (room == model.selectedRoom ? model.liveImage(world: world, room: room) : nil)
                      ?? model.thumbnail(room: room) {
            Image(decorative: image, scale: 1).interpolation(.none).resizable()
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}

/// The Apple IIe key code (bit 7 set) for a key typed on the Mac: characters
/// as ASCII, Ctrl + letter as its control code, Return, Esc, Tab; Delete
/// as ← ($88).  The arrow keys move like I J K M, with Shift slowly like
/// Ctrl-I J K M, as the arrow keys of the PC version do (the Apple's own arrow
/// keys send ^H ^U ^K ^J, which the game reads as other keys).
enum AppleKeyboard {
    static func code(for press: KeyPress) -> UInt8? {
        guard !press.modifiers.contains(.command) else { return nil }
        let slowly = press.modifiers.contains(.shift) || press.modifiers.contains(.control)
        switch press.key {
        case .upArrow: return slowly ? 0x89 : 0xC9
        case .downArrow: return slowly ? 0x8D : 0xCD
        case .leftArrow: return slowly ? 0x8A : 0xCA
        case .rightArrow: return slowly ? 0x8B : 0xCB
        case .return: return 0x8D
        case .escape: return 0x9B
        case .tab: return 0x89
        case .delete: return 0x88
        case .space: return 0xA0
        default: break
        }
        guard let c = press.characters.unicodeScalars.first, c.isASCII else { return nil }
        var v = UInt8(c.value)
        if press.modifiers.contains(.control), (0x40 ..< 0x80).contains(v) { v &= 0x1F }
        return v | 0x80
    }
}

func hex(_ v: Int) -> String { String(format: "$%02X", v) }

func roomTitle(_ r: Int) -> String {
    r == World.nowhere ? "Room $3F (nowhere)" : String(format: "Room $%02X (%d)", r, r)
}
