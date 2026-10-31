import SwiftUI

/// The selected room large, with link navigation, and the 8x8 map of all rooms below.
struct WorldView: View {
    @Bindable var model: ViewerModel
    let world: World
    @FocusState private var focused: Bool

    var body: some View {
        let room = world.room(model.selectedRoom)
        VStack {
            RoomHeader(model: model, room: room, code: world.codeRooms[room.id])
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
                .task(id: "\(world.id)#\(model.renderer.rawValue)#\(model.restarts)") {
                    await model.runGame(world: world)
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rooms").font(.headline)
                    RoomMap(model: model, world: world)
                }
                .padding()
            }
            .navigationTitle(world.name)
            .onAppear { focused = true }
        }
    }
}

private struct RoomHeader: View {
    var model: ViewerModel
    let room: Room
    let code: RoomCode?

    var body: some View {
        HStack(spacing: 12) {
            Text(roomTitle(room.id)).font(.title2.monospacedDigit().bold())
            if let code {
                Label("Code room", systemImage: "curlybraces")
                    .foregroundStyle(.orange)
                    .help(String(format: "The wall bytes are 6502 code: routine $%04X, called from $%04X", code.entry, code.caller))
            }
            Spacer()
            ForEach([(Room.Direction.left, "arrow.left"), (.up, "arrow.up"), (.down, "arrow.down"), (.right, "arrow.right")],
                    id: \.1) { dir, icon in
                let target = room.link(dir)
                Button {
                    model.go(dir)
                } label: {
                    Label(target == room.id ? "–" : hex(target), systemImage: icon).monospacedDigit()
                }
                .disabled(target == room.id)
                .help(target == room.id ? "No exit" : "Go to room \(roomTitle(target))")
            }
        }
    }
}

/// The room at 560x384 (scaled to fit), with hover read-out, object selection and tile grid.
struct RoomCanvas: View {
    var model: ViewerModel
    let world: World
    /// Object coordinates under the pointer: x 0-139, y 0-191 counted from the bottom.
    @State private var hover: (x: Int, y: Int)?

    var body: some View {
        let objects = world.objectsInRoom(model.selectedRoom)
        VStack(alignment: .leading, spacing: 4) {
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
                    if let o = model.selectedObject {
                        let ob = world.object(o)
                        Rectangle()
                            .stroke(.yellow, lineWidth: 2)
                            .frame(width: 28 * k + 4, height: 32 * k + 4)
                            .offset(x: CGFloat(ob.x * 4) * k - 2, y: CGFloat((191 - ob.y - 15) * 2) * k - 2)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let p) = phase { hover = logical(p, k: k) } else { hover = nil }
                }
                .onTapGesture { p in
                    let (x, y) = logical(p, k: k)
                    model.selectedObject = objectAt(x, y, objects: objects)
                }
            }
            .aspectRatio(560.0 / 384.0, contentMode: .fit)
            .frame(maxWidth: 1120)
            Text(hoverText(objects: objects))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if model.renderer == .game, !model.loopStatus.isEmpty {
                    Text(model.loopStatus).font(.caption.monospacedDigit())
                }
                Text(model.renderNote(world: world, room: model.selectedRoom))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func logical(_ p: CGPoint, k: CGFloat) -> (x: Int, y: Int) {
        (Int(p.x / k / 4), 191 - Int(p.y / k / 2))
    }

    /// Topmost object whose 7x16 sprite box contains (x, y).
    private func objectAt(_ x: Int, _ y: Int, objects: [Int]) -> Int? {
        objects.reversed().first { o in
            let ob = world.object(o)
            return (ob.x ..< ob.x + 7).contains(x) && (ob.y ..< ob.y + 16).contains(y)
        }
    }

    private func hoverText(objects: [Int]) -> String {
        guard let (x, y) = hover, (0 ..< 140).contains(x), (0 ..< 192).contains(y) else {
            if model.playing {
                return "Playing: I J K M or the arrow keys move (Ctrl or Shift: slowly) · space picks up and drops · ? hints · Esc quits"
            }
            return "Hover for coordinates · click an object to select it · arrow keys follow exits · space pauses"
        }
        var s = String(format: "x=$%02X y=$%02X   tile column %d row %d", x, y, x * 2 / 14, (191 - y) / 16)
        if let o = objectAt(x, y, objects: objects) {
            let ob = world.object(o)
            s += String(format: "   object $%02X: sprite $%02X at ($%02X,$%02X)", o, ob.sprite, ob.x, ob.y)
        }
        return s
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
private struct RoomMap: View {
    var model: ViewerModel
    let world: World

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
            ForEach(0 ..< World.roomCount, id: \.self) { r in
                let isCode = world.codeRooms[r] != nil
                let used = world.isRoomUsed(r) && !isCode
                VStack(spacing: 2) {
                    Group {
                        if isCode {
                            Rectangle().fill(.quaternary)
                                .overlay { Image(systemName: "curlybraces").foregroundStyle(.orange) }
                        } else if used || model.showEmptyRooms, let t = model.thumbnail(room: r) {
                            Image(decorative: t, scale: 1).interpolation(.none).resizable()
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .aspectRatio(280.0 / 192.0, contentMode: .fit)
                    .overlay {
                        if r == model.selectedRoom { Rectangle().stroke(Color.accentColor, lineWidth: 3) }
                    }
                    Text(hex(r)).font(.caption2.monospaced()).foregroundStyle(used ? .primary : .tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { model.selectedRoom = r }
                .help(roomTitle(r) + (isCode ? " – 6502 code" : ""))
            }
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
