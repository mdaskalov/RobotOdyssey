import SwiftUI

/// The selected room large, and below it, if shown, the world: its rooms,
/// sprites, sounds… (`WorldPanel`).
struct WorldView: View {
    @Bindable var model: ViewerModel
    let world: World
    @FocusState private var focused: Bool
    @AppStorage("worldHeight") private var worldHeight = 320.0

    var body: some View {
        GeometryReader { geo in
            // The canvas keeps at least 160 points.
            let maxWorld = max(geo.size.height - 160, 100)
            VStack(spacing: 0) {
                RoomCanvas(model: model, world: world)
                    .focusable()
                    .focused($focused)
                    .focusEffectDisabled()
                    .onKeyPress(phases: [.down, .repeat, .up]) { press in
                        if model.playing {
                            let key = press.key.character.lowercased()
                            if press.phase == .up {
                                model.release(key)
                                return .handled
                            }
                            guard let code = AppleKeyboard.code(for: press, appleArrows: model.inLoader) else { return .ignored }
                            model.type(code, key: key, repeated: press.phase == .repeat)
                            return .handled
                        }
                        guard press.phase != .up else { return .ignored }
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
                    // Key ups go elsewhere then: a key held would walk on.
                    .onChange(of: focused) {
                        if !focused { model.releaseKeys() }
                    }
                    #if os(macOS)
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                        model.releaseKeys()
                    }
                    #endif
                    .task(id: model.session) {
                        await model.runGame()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showWorld {
                    VStack(spacing: 0) {
                        ResizeHandle(size: $worldHeight, range: 100 ... maxWorld, panel: .bottom)
                        WorldPanel(model: model, world: world)
                            .frame(height: min(worldHeight, maxWorld))
                    }
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(.default, value: model.showWorld)  // as the inspector slides
        }
        .onAppear { focused = true }
    }
}

/// The room at 560x384 (scaled to fit), with selection of sprites and wires,
/// and tile grid; the point under the pointer goes to `ViewerModel.pointer`.
/// A click selects (in Play, on the player, it is the game's button too), a
/// drag takes hold of the player or an object in the running game
/// (`ViewerModel.beginDrag`, `MouseHand`).
struct RoomCanvas: View {
    var model: ViewerModel
    let world: World
    /// The mouse went down and moved far enough to be a drag.
    @State private var dragged = false

    /// How far the pointer moves before a click is a drag, in points.
    private static let dragDistance: CGFloat = 3

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
                if model.showGrid && !model.inLoader { TileGrid(k: k) }
                if !model.inLoader, let s = model.selection.flatMap(contents.sprite) {
                    Rectangle()
                        .stroke(.yellow, lineWidth: 2)
                        .frame(width: 28 * k + 4, height: 32 * k + 4)
                        .offset(x: CGFloat(s.x * 4) * k - 2, y: CGFloat((191 - s.y - 15) * 2) * k - 2)
                }
                if !model.inLoader, let w = model.selection.flatMap(contents.wire) {
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
            // One gesture for both, so a click doesn't wait for the drag to fail.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let t = value.translation
                        if !dragged, hypot(t.width, t.height) >= RoomCanvas.dragDistance {
                            dragged = true
                            model.beginDrag(at: logical(value.startLocation, k: k))
                        }
                        // Object units: 4 image pixels across, 2 up (y up).
                        if dragged { model.drag(by: t.width / k / 4, -t.height / k / 2) }
                    }
                    .onEnded { value in
                        if dragged {
                            model.endDrag()
                        } else {
                            model.click(at: logical(value.startLocation, k: k), in: world)
                        }
                        dragged = false
                    }
            )
            .pointerStyle(model.dragging ? .grabActive : model.pointer.map(model.canHold) == true ? .grabIdle : nil)
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
/// as ← ($88).  In the worlds the arrow keys move like I J K M, with Shift
/// slowly like Ctrl-I J K M, as the arrow keys of the PC version do (the
/// Apple's own arrow keys send ^H ^U ^K ^J, which the worlds read as other
/// keys); with `appleArrows` (the loader: the menu's cursor, names) they are
/// the Apple's.
enum AppleKeyboard {
    static func code(for press: KeyPress, appleArrows: Bool = false) -> UInt8? {
        guard !press.modifiers.contains(.command) else { return nil }
        if appleArrows {
            switch press.key {
            case .leftArrow: return 0x88
            case .rightArrow: return 0x95
            case .upArrow: return 0x8B
            case .downArrow: return 0x8A
            default: break
            }
        }
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
