import SwiftUI

/// How the world panel shows the rooms.
enum RoomsLayout: String, CaseIterable, Identifiable {
    /// Room n at column n % 8, row n / 8.
    case grid = "Grid"
    /// As they connect (WorldMap).
    case map = "Map"
    var id: String { rawValue }
}

/// The selected world below the canvas, each part a section that folds as
/// the current room's do: its rooms (in an 8x8 grid or on the map of how they
/// connect), wall types, sprites, sounds (to play), texts, objects, robots
/// and wires, as the running loop last drew the selected room
/// (`ViewerModel.contents`).  Click one to go to its room.
struct WorldPanel: View {
    var model: ViewerModel
    let world: World
    @State private var scrolled = Scrolled()

    /// The coordinate space of the panel's contents, which scroll with them.
    static let contents = "WorldPanel.contents"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("World").font(.headline)
                Text(world.name).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            GeometryReader { geo in
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                            RoomsSection(model: model, world: world, width: geo.size.width - 32) { row, map in
                                follow(row, map: map, scroll)
                            }
                            WallTypesSection(model: model, world: world)
                            SpritesSection(model: model, world: world)
                            SoundsSection(model: model, world: world)
                            TextsSection(model: model, world: world)
                            ObjectsSection(model: model, world: world)
                            if world.engine == .levels {
                                RobotsSection(model: model, world: world)
                            }
                            WiresSection(model: model, world: world)
                        }
                        .coordinateSpace(.named(Self.contents))
                    }
                    .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { scrolled.geometry = $1 }
                }
            }
        }
    }

    /// If the map (`map`, its frame in the contents) is what the panel shows
    /// – it covers the middle – scrolls the panel to have `row` (the selected
    /// room's) in the middle, and is true; scrolled to the other sections,
    /// the panel stays there.
    private func follow(_ row: RoomRow, map: CGRect, _ scroll: ScrollViewProxy) -> Bool {
        guard let g = scrolled.geometry, map.height > 0, (map.minY ... map.maxY).contains(g.visibleRect.midY) else {
            return false
        }
        scroll.scrollTo(row, anchor: .center)
        return true
    }
}

/// How the panel is scrolled, as it scrolls: not observed, so that
/// scrolling doesn't draw the panel again.
private final class Scrolled {
    var geometry: ScrollGeometry?
}

/// A part of the world panel: a header that folds it, as the current room's
/// disclosure groups do, with a summary and, while open, controls of its
/// own; it stays at the top while its contents scroll by.
private struct WorldSection<Content: View, Controls: View>: View {
    let title: String
    let summary: String
    @Binding var isExpanded: Bool
    let content: () -> Content
    let controls: () -> Controls

    init(_ title: String, summary: String, isExpanded: Binding<Bool>,
         @ViewBuilder content: @escaping () -> Content, @ViewBuilder controls: @escaping () -> Controls) {
        self.title = title
        self.summary = summary
        _isExpanded = isExpanded
        self.content = content
        self.controls = controls
    }

    var body: some View {
        Section {
            if isExpanded {
                content().padding(.bottom, 12)
            }
        } header: {
            header
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                    Text(title).fontWeight(.semibold)
                    Text(summary).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if isExpanded { controls() }
        }
        .frame(minHeight: 22)
        .padding(.horizontal)
        .padding(.vertical, 5)
        .background(.windowBackground)
        .overlay(alignment: .top) { Divider() }
    }
}

private extension WorldSection where Controls == EmptyView {
    init(_ title: String, summary: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, summary: summary, isExpanded: isExpanded, content: content) { EmptyView() }
    }
}

/// A grid of cells at least `minimum` wide, as many as fit across.
private func cells(_ minimum: CGFloat) -> [GridItem] {
    [GridItem(.adaptive(minimum: minimum), spacing: 8, alignment: .topLeading)]
}

/// The one after `current` in `items`, round, else the first.
private func next<T: Equatable>(after current: T?, in items: [T]) -> T? {
    guard let i = current.flatMap(items.firstIndex) else { return items.first }
    return items[(i + 1) % items.count]
}

/// Highlights what is selected, as a list does.
private extension View {
    func selected(_ isSelected: Bool) -> some View {
        padding(4)
            .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
    }
}

// MARK: rooms

/// All rooms, in an 8x8 grid or on the map of how they connect; click one to
/// select it.  The map keeps the selected room in view while it is what the
/// panel shows (`follow`), so it follows the player.
private struct RoomsSection: View {
    var model: ViewerModel
    let world: World
    /// The width the map lays its islands out in.
    let width: CGFloat
    let follow: WorldMapView.Follow
    @AppStorage("worldShowRooms") private var isExpanded = true
    @AppStorage("roomsLayout") private var layout = RoomsLayout.grid
    /// Map tiles as a fraction of a full-size thumbnail.
    @AppStorage("mapZoom") private var zoom = 0.5

    var body: some View {
        let used = (0 ..< World.roomCount).count { world.isRoomUsed($0) && world.codeRooms[$0] == nil }
        WorldSection("Rooms", summary: "\(used) used", isExpanded: $isExpanded) {
            Group {
                if !model.thumbnailsReady {
                    loading("Drawing the rooms…")
                } else if layout == .grid {
                    RoomGrid(model: model, world: world).padding(.horizontal)
                } else if let map = model.map(world) {
                    WorldMapView(model: model, world: world, map: map, zoom: zoom, width: width, follow: follow)
                } else {
                    loading("Laying out the map…")
                }
            }
            .task(id: "\(world.id)#\(model.mode.rawValue)#\(layout.rawValue)") {
                await model.prepareRooms(world: world, withMap: layout == .map)
            }
        } controls: {
            if layout == .map {
                Slider(value: $zoom, in: 0.35 ... 1) { Text("Zoom") }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 160)
                    .help("Zoom")
            }
            Picker("Rooms", selection: $layout) {
                ForEach(RoomsLayout.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("Grid: room n at column n % 8, row n / 8. Map: the rooms as they connect.")
        }
    }

    /// In place of the rooms while `prepareRooms` makes them.
    private func loading(_ title: String) -> some View {
        ProgressView(title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
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

// MARK: wall types

/// A colour the world's rooms draw their walls or floor in (the engine's
/// colour table: 0-7 plain, 8-$13 dithered, $14 not drawn), with those rooms.
private struct WallType: Identifiable {
    let id: Int
    let pattern: [UInt8]
    var walls: [Int] = []
    var floors: [Int] = []

    /// The colours of the used rooms' walls and floors (but code rooms'), in order.
    static func all(in world: World) -> [WallType] {
        let renderer = RoomRenderer(world: world)
        var types: [Int: WallType] = [:]
        let base = GameSymbols.address(\.roomWalls)
        for r in 0 ..< World.roomCount where world.codeRooms[r] == nil && world.isRoomUsed(r) {
            let bytes = world.mem[base + r * 30 ..< base + r * 30 + 30]
            if bytes.contains(where: { $0 != 0 }) {
                let c = Int(world.mem[\.roomWallColour, r])
                types[c, default: WallType(id: c, pattern: renderer.colour(c))].walls.append(r)
            }
            if bytes.contains(where: { $0 != 0xFF }) {
                let c = Int(world.mem[\.roomFloorColour, r])
                types[c, default: WallType(id: c, pattern: renderer.colour(c))].floors.append(r)
            }
        }
        return types.values.sorted { $0.id < $1.id }
    }

    var drawn: Bool { TileSwatch.drawn(pattern) }

    var rooms: [Int] { Array(Set(walls + floors)).sorted() }
}

/// The tile patterns of the world's walls and floors as it starts, each with
/// the rooms that use it; click one to go to these rooms one after the other.
private struct WallTypesSection: View {
    var model: ViewerModel
    let world: World
    @AppStorage("worldShowWallTypes") private var isExpanded = false

    var body: some View {
        let types = WallType.all(in: world)
        WorldSection("Wall types", summary: "\(types.count)", isExpanded: $isExpanded) {
            LazyVGrid(columns: cells(110), alignment: .leading, spacing: 8) {
                ForEach(types) { type in
                    let rooms = type.rooms
                    VStack(alignment: .leading, spacing: 3) {
                        TileSwatch(pattern: type.pattern, mode: model.mode)
                        Text(hex(type.id)).font(.caption.monospaced())
                        Text(usage(type)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .selected(rooms.contains(model.selectedRoom))
                    .onTapGesture {
                        if let r = next(after: model.selectedRoom, in: rooms) { model.show(room: r) }
                    }
                    .help(help(type))
                }
            }
            .padding(.horizontal)
        }
    }

    private func usage(_ type: WallType) -> String {
        [type.walls.isEmpty ? nil : "walls \(type.walls.count)", type.floors.isEmpty ? nil : "floor \(type.floors.count)"]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func help(_ type: WallType) -> String {
        let pattern = type.pattern.map { String(format: "%02X", $0) }.joined(separator: " ")
        var s = "Colour \(hex(type.id)): pattern \(pattern)" + (type.drawn ? "" : " (not drawn: the tile is left as it is)")
        if !type.walls.isEmpty { s += "\nThe walls of " + type.walls.map(hex).joined(separator: " ") }
        if !type.floors.isEmpty { s += "\nThe floor of " + type.floors.map(hex).joined(separator: " ") }
        return s + "\nClick to go to these rooms one after the other"
    }
}

/// Two by two tiles in a wall type's pattern (a colour's 4 bytes), as the
/// engine draws them (DRAW_ROOM_TILES: pattern[b % 4] on even lines,
/// [(b + 2) % 4] on odd); in the world panel and the current room's colours.
struct TileSwatch: View {
    let pattern: [UInt8]
    let mode: HiresImage.Mode
    /// A tile's size on screen: 28 x 32, the canvas's at 560 wide; half that
    /// is the Apple's pixels at 2x.
    var tile = CGSize(width: 28, height: 32)

    /// The swatches made so far, by pattern and mode: the panels ask every tick.
    private static var made: [String: CGImage] = [:]

    /// Colour $14 ($F0): the tile is left as it is.
    static func drawn(_ pattern: [UInt8]) -> Bool { pattern.first != 0xF0 }

    var body: some View {
        if Self.drawn(pattern), let image = Self.image(pattern, mode: mode) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: tile.width * 2, height: tile.height * 2)
        } else {
            Rectangle()
                .fill(.quaternary)
                .frame(width: tile.width * 2, height: tile.height * 2)
                .overlay {
                    if tile.width >= 28 {
                        Text("not drawn").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "nosign").font(.caption2).foregroundStyle(.secondary)
                    }
                }
        }
    }

    /// The whole screen in the pattern, then two tiles each way from its
    /// middle: the colours as next to other tiles of the pattern.
    private static func image(_ pattern: [UInt8], mode: HiresImage.Mode) -> CGImage? {
        let key = pattern.map { String(format: "%02X", $0) }.joined() + mode.rawValue
        if let image = made[key] { return image }
        var screen = HiresScreen()
        for line in 0 ..< HiresScreen.height {
            for b in 0 ..< HiresScreen.bytesPerLine {
                screen.bytes[line * 40 + b] = pattern[(b + (line & 1 == 1 ? 2 : 0)) % 4]
            }
        }
        // Scale 2: a tile is 28 x 32.
        let image = HiresImage.make(screen, mode: mode)?.cropping(to: CGRect(x: 4 * 28, y: 4 * 32, width: 56, height: 64))
        made[key] = image
        return image
    }
}

// MARK: sprites

/// The world's 64 sprites ($6A00) as it starts, each in the colour of the
/// first object that shows it then (white if none): the colours a wire or
/// a pin takes as it runs don't show here.  Click one to select the objects
/// that show it now, one after the other.
private struct SpritesSection: View {
    var model: ViewerModel
    let world: World
    @AppStorage("worldShowSprites") private var isExpanded = false

    var body: some View {
        let colours = Dictionary(placedObjects(world).map { ($0.sprite, $0.color) }) { first, _ in first }
        let users = Dictionary(grouping: placedObjects(model.contents(world).world), by: \.sprite)
        WorldSection("Sprites", summary: "64 · \(users.count) shown by objects", isExpanded: $isExpanded) {
            LazyVGrid(columns: cells(44), alignment: .leading, spacing: 8) {
                ForEach(0 ..< 64, id: \.self) { n in
                    let objects = users[n] ?? []
                    VStack(spacing: 2) {
                        if let image = SpriteImage.make(rows: Array(world.sprite(n)), colour: colours[n] ?? 3) {
                            Image(decorative: image, scale: 1)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 28, height: 32)
                                .background(Color(white: 0.15))
                        }
                        Text(hex(n)).font(.caption2.monospaced())
                            .foregroundStyle(objects.isEmpty ? .tertiary : .primary)
                    }
                    .selected(objects.contains { model.selection == .object($0.id) })
                    .onTapGesture { select(objects) }
                    .help(help(n, objects))
                }
            }
            .padding(.horizontal)
        }
    }

    /// The object after the one selected among `objects`, in its room.
    private func select(_ objects: [GameObject]) {
        let current = objects.first { model.selection == .object($0.id) }
        guard let o = next(after: current?.id, in: objects.map(\.id)), let object = objects.first(where: { $0.id == o })
        else { return }
        model.show(room: object.room, item: .object(object.id))
    }

    private func help(_ n: Int, _ objects: [GameObject]) -> String {
        let s = "Sprite \(hex(n)) at " + String(format: "$%04X", GameSymbols.address(\.sprites) + n * 16)
        guard !objects.isEmpty else { return s + ": no object in a room shows it" }
        return s + "\nObjects " + objects.map { "\(hex($0.id)) (room \(hex($0.room)))" }.joined(separator: ", ")
            + "\nClick to select them one after the other"
    }
}

/// The objects in a room (not $3F, nowhere), by number.
private func placedObjects(_ world: World) -> [GameObject] {
    (0 ..< World.objectCount).map(world.object).filter { $0.room != World.nowhere }
}

// MARK: sounds

/// The world's sound table (WORLD_SOUND), each sound with its number, its
/// name in the map (GameSounds; ? a guess), its parameters and length; ▶
/// plays it as the game does.
private struct SoundsSection: View {
    var model: ViewerModel
    let world: World
    @AppStorage("worldShowSounds") private var isExpanded = false
    /// Each sound's length in seconds (nil: it could not be played), for `world`.
    @State private var lengths: (world: World.ID, seconds: [Double?])?

    var body: some View {
        let sounds = world.sounds
        WorldSection("Sounds", summary: sounds.map { "\($0.count)" } ?? "no sound table found", isExpanded: $isExpanded) {
            LazyVGrid(columns: cells(280), alignment: .leading, spacing: 4) {
                ForEach(Array((sounds ?? []).enumerated()), id: \.offset) { n, sound in
                    HStack(spacing: 8) {
                        Button("Play", systemImage: "play.fill") { model.play(sound, in: world) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Play it as the game does (also when muted)")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(n)  " + name(sound)).font(.caption.monospaced())
                            Text(details(sound, seconds: lengths?.world == world.id ? lengths?.seconds[n] : nil))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .task(id: world.id) {
                lengths = (world.id, await Self.lengths(world))
            }
        }
    }

    private func name(_ sound: Sound.Parameters) -> String {
        guard let name = GameSounds.name(for: sound) else { return "not in the map" }
        return name + (GameSounds.named.first { $0.name == name }?.sound.guess == true ? " ?" : "")
    }

    private func details(_ sound: Sound.Parameters, seconds: Double?) -> String {
        let s = String(format: "%@ $%02X $%02X $%02X", "\(sound.kind)", sound.length, sound.sweep, sound.pitch)
        return s + (seconds.map { String(format: " · %.0f ms", $0 * 1000) } ?? "")
    }

    /// Plays each sound off the main thread to see how long it takes.
    @concurrent
    private nonisolated static func lengths(_ world: World) async -> [Double?] {
        (world.sounds ?? []).map { p in (try? Sound.play(p, in: world)).map { Double($0.cycles) / GameLoop.clock } }
    }
}

// MARK: texts

/// The world's texts by room, with their place and style; click one to go to its room.
private struct TextsSection: View {
    var model: ViewerModel
    let world: World
    @AppStorage("worldShowTexts") private var isExpanded = false

    var body: some View {
        let live = model.contents(world).world
        let texts = (0 ..< World.roomCount).filter { $0 != World.nowhere }.flatMap(live.textsInRoom).map(live.text)
        WorldSection("Texts", summary: "\(texts.count)", isExpanded: $isExpanded) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(texts) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "#%02X  room $%02X at ($%02X,$%02X)", t.id, t.room, t.x, t.y)
                             + (t.style == 2 ? " big, colour \(t.color)" : t.style == 0 ? "" : " style \(t.style)"))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Text(t.string.isEmpty ? "(empty)" : t.string).font(.caption.monospaced())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .selected(t.room == model.selectedRoom)
                    .onTapGesture { model.show(room: t.room) }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: objects

/// The objects in the world's rooms, by number; click one to select it in its room.
private struct ObjectsSection: View {
    var model: ViewerModel
    let world: World
    @AppStorage("worldShowObjects") private var isExpanded = false

    var body: some View {
        let live = model.contents(world).world
        let objects = placedObjects(live)
        let held = Int(live.mem[\.heldObject])
        WorldSection("Objects", summary: "\(objects.count) in rooms · \(World.objectCount - objects.count) nowhere",
                     isExpanded: $isExpanded) {
            LazyVGrid(columns: cells(180), alignment: .leading, spacing: 4) {
                ForEach(objects) { o in
                    ObjectCell(world: live, object: o, note: o.id == held ? "held" : nil)
                        .selected(model.selection == .object(o.id))
                        .onTapGesture { model.show(room: o.room, item: .object(o.id)) }
                }
            }
            .padding(.horizontal)
        }
    }
}

/// An object: its sprite in its colour, number, sprite, room and place.
private struct ObjectCell: View {
    let world: World
    let object: GameObject
    var note: String?

    var body: some View {
        let o = object
        HStack(spacing: 6) {
            if let image = SpriteImage.make(rows: Array(world.sprite(o.sprite)), colour: o.color) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 21, height: 24)
                    .background(Color(white: 0.15))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "$%02X  sprite $%02X", o.id, o.sprite) + (note.map { " · \($0)" } ?? ""))
                    .font(.caption.monospaced())
                Text(String(format: "room $%02X at ($%02X,$%02X)", o.room, o.x, o.y))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(String(format: "Object $%02X: sprite $%02X colour %d flags $%02X", o.id, o.sprite, o.color, o.flags)
              + (o.link == World.noObject ? "" : String(format: ", follows $%02X", o.link)))
    }
}

// MARK: robots

/// The four robots (ROBOT_BODY, ROBOT_INTERIOR; the levels' tables): click
/// one to select its body, Inside to go to its interior.
private struct RobotsSection: View {
    var model: ViewerModel
    let world: World
    @AppStorage("worldShowRobots") private var isExpanded = false

    var body: some View {
        let live = model.contents(world).world
        let robots = live.robots
        WorldSection("Robots", summary: "\(robots.count { live.object($0.object).room != World.nowhere }) in rooms",
                     isExpanded: $isExpanded) {
            LazyVGrid(columns: cells(260), alignment: .leading, spacing: 4) {
                ForEach(robots.indices, id: \.self) { i in
                    let robot = live.object(robots[i].object)
                    HStack(spacing: 8) {
                        ObjectCell(world: live, object: robot, note: "robot \(i + 1)")
                            .selected(model.selection == .object(robot.id))
                            .onTapGesture {
                                if robot.room != World.nowhere { model.show(room: robot.room, item: .object(robot.id)) }
                            }
                        Button("Inside") { model.show(room: robots[i].interior) }
                            .controlSize(.small)
                            .help("Go to its interior, \(roomTitle(robots[i].interior))")
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: wires

/// The wires of the objects in the world's rooms, hot or off; click one to
/// select it in its room.
private struct WiresSection: View {
    var model: ViewerModel
    let world: World
    @AppStorage("worldShowWires") private var isExpanded = false

    var body: some View {
        let live = model.contents(world).world
        let wires = placedObjects(live).compactMap { o in live.wire(o.id).map { (object: o, wire: $0) } }
        WorldSection("Wires", summary: "\(wires.count) · \(wires.count { $0.wire.hot }) hot", isExpanded: $isExpanded) {
            LazyVGrid(columns: cells(200), alignment: .leading, spacing: 4) {
                ForEach(wires, id: \.object.id) { o, w in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(w.hot ? Color.orange : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(String(format: "$%02X → $%02X  %@  room $%02X", o.id, w.to, w.hot ? "hot" : "off", o.room))
                            .font(.caption.monospaced())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .selected(model.selection == .wire(o.id))
                    .onTapGesture { model.show(room: o.room, item: .wire(o.id)) }
                    .help(String(format: "From ($%02X,$%02X) to ($%02X,$%02X)", w.ax, w.ay, w.bx, w.by))
                }
            }
            .padding(.horizontal)
        }
    }
}
