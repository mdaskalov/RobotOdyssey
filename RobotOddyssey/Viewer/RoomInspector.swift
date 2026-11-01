import SwiftUI

/// The selected room's properties, the running game (tick, how the room is
/// drawn, the native routines), then the room's objects, the other sprites
/// drawn, wires and texts (folded; select a sprite or wire to highlight it),
/// as the loop last drew it (`ViewerModel.contents`).
struct RoomInspector: View {
    @Bindable var model: ViewerModel
    let world: World
    @AppStorage("showNatives") private var showNatives = false
    @AppStorage("showObjects") private var showObjects = false
    @AppStorage("showWires") private var showWires = false
    @AppStorage("showTexts") private var showTexts = false

    var body: some View {
        let contents = model.contents(world)
        let live = contents.world
        let room = live.room(model.selectedRoom)
        List(selection: $model.selection) {
            Section(roomTitle(room.id)) {
                if let code = world.codeRooms[room.id] {
                    let walls = GameSymbols.address(\.roomWalls) + room.id * 30
                    row("Walls", String(format: "6502 code $%04X–$%04X", walls, walls + 29))
                    row("Routine", String(format: "$%04X, called from $%04X", code.entry, code.caller))
                }
                row("Floor colour", hex(room.floorColor))
                row("Wall colour", hex(room.wallColor))
                row("Exits ↑ ↓ ← →", [room.up, room.down, room.left, room.right]
                    .map { $0 == room.id ? "–" : hex($0) }.joined(separator: " "))
                row("First object", room.firstObject == World.noObject ? "none" : hex(room.firstObject))
                if let robot = live.robots.firstIndex(where: { $0.interior == room.id }) {
                    row("Inside robot", "\(robot + 1) (object \(hex(live.robots[robot].object)))")
                }
            }
            Section("Game") {
                if !model.loopStatus.isEmpty {
                    Text(model.loopStatus).monospacedDigit()
                }
                Text(model.renderNote(world: world, room: room.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                natives
            }
            Section("Contents") {
                sprites(contents)
                wires(contents)
                texts(live, room: room.id)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).monospaced() }
    }

    /// The room's objects, and the other sprites drawn: recorded only while
    /// open (`ViewerModel.showSprites`).  Both folded by default.
    @ViewBuilder
    private func sprites(_ contents: RoomContents) -> some View {
        DisclosureGroup(isExpanded: $showObjects) {
            ForEach(contents.objects) { s in
                SpriteRow(world: contents.world, sprite: s, drawn: contents.recorded).tag(s.id)
            }
        } label: {
            LabeledContent("Objects") {
                Text("\(contents.objects.count)" + (contents.live ? "" : " · as the world starts")).monospacedDigit()
            }
        }
        DisclosureGroup(isExpanded: $model.showSprites) {
            ForEach(contents.others) { s in
                SpriteRow(world: contents.world, sprite: s, drawn: true).tag(s.id)
            }
        } label: {
            LabeledContent("Other sprites drawn") {
                Text(!contents.live ? "room not drawn" : contents.recorded ? "\(contents.others.count)" : "").monospacedDigit()
            }
        }
        .help("Robots and the world's own code: while open, the room is drawn once more each tick to record them")
    }

    /// The wires of the room's objects, hot or off.
    @ViewBuilder
    private func wires(_ contents: RoomContents) -> some View {
        if !contents.wires.isEmpty {
            DisclosureGroup(isExpanded: $showWires) {
                ForEach(contents.wires) { w in
                    WireRow(wire: w).tag(w.id)
                }
            } label: {
                LabeledContent("Wires") {
                    Text("\(contents.wires.count) · \(contents.wires.count { $0.wire.hot }) hot").monospacedDigit()
                }
            }
        }
    }

    /// The room's texts.
    @ViewBuilder
    private func texts(_ world: World, room: Int) -> some View {
        let texts = world.textsInRoom(room)
        if !texts.isEmpty {
            DisclosureGroup(isExpanded: $showTexts) {
                ForEach(texts.map(world.text)) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "#%02X at ($%02X,$%02X) style %d colour %d", t.id, t.x, t.y, t.style, t.color))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Text(t.string).font(.caption.monospaced())
                    }
                }
            } label: {
                LabeledContent("Texts") { Text("\(texts.count)").monospacedDigit() }
            }
        }
    }

    /// The native routines with their entry points, and the routines the
    /// loader found modified (they run as the original code).
    private var natives: some View {
        let natives = model.natives(world: world)
        let differing = world.codeCheck?.differing ?? []
        let summary = world.codeCheck.map { "\(natives.count) · \($0.variant)" } ?? "none: unknown version"
        return DisclosureGroup(isExpanded: $showNatives) {
            ForEach(natives, id: \.name) { native in
                LabeledContent(native.name) { Text(String(format: "$%04X", native.entry)) }
                    .font(.caption.monospaced())
            }
            ForEach(differing, id: \.self) { name in
                LabeledContent(name) { Text("differs: 6502 code") }
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
            }
        } label: {
            LabeledContent("Native routines") { Text(summary).monospacedDigit() }
        }
    }
}

/// A wire: its object, the object at the other end, hot (orange) or off, and its ends.
private struct WireRow: View {
    let wire: RoomWire

    var body: some View {
        let w = wire.wire
        HStack(spacing: 6) {
            Circle()
                .fill(w.hot ? Color.orange : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(String(format: "$%02X → $%02X  %@  ($%02X,$%02X)–($%02X,$%02X)",
                        wire.object, w.to, w.hot ? "hot" : "off", w.ax, w.ay, w.bx, w.by))
                .font(.caption.monospaced())
        }
        .help(w.hot ? "Hot: carries a signal (orange, colour 5)" : "Off: colour \(w.colour)")
    }
}

/// A sprite as drawn: an object with its number, sprite, colour, place, flags
/// and link, or another sprite with the routine that drew it.
private struct SpriteRow: View {
    let world: World
    let sprite: RoomSprite
    /// The sprites drawn were recorded: an object without a draw was not on the page.
    let drawn: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let img = SpriteImage.make(rows: sprite.rows(in: world), colour: sprite.colour) {
                Image(decorative: img, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 21, height: 24)
                    .background(Color(white: 0.15))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.monospaced())
                Text(details).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        let name = sprite.spriteName(in: world)
        if let object = sprite.object {
            return String(format: "$%02X  %@  colour %d", object.id, name, object.color)
        }
        guard let d = sprite.drawn else { return name }
        return name + (d.colour.map { "  colour \($0)" } ?? String(format: "  patterns $%02X $%02X", d.patterns.even, d.patterns.odd))
    }

    private var details: String {
        var s = String(format: "at ($%02X,$%02X)", sprite.x, sprite.y)
        guard let object = sprite.object else {
            return s + " · " + (sprite.drawnBy(in: world) ?? "?")
        }
        s += String(format: " flags $%02X", object.flags)
        if object.link != World.noObject {
            s += String(format: " · follows $%02X %+d,%+d", object.link, Int8(truncatingIfNeeded: object.dx),
                        Int8(truncatingIfNeeded: object.dy))
        }
        if drawn && sprite.drawn == nil { s += " · not drawn" }
        return s
    }
}

/// A sprite as a tiny image, in the flat colour closest to the engine's colour.
enum SpriteImage {
    /// Approximate RGB of the engine's colours 0-7 (black, green, purple, white, black, orange, blue, white).
    private static let colours: [(UInt8, UInt8, UInt8)] = [(90, 90, 90), (20, 245, 60), (255, 68, 253), (255, 255, 255),
                                                          (90, 90, 90), (255, 106, 60), (20, 207, 253), (255, 255, 255)]

    /// 16 rows, row 0 at the bottom; other colours than 0-7 (patterns) light grey.
    static func make(rows: [UInt8], colour: Int?) -> CGImage? {
        let c = colour.flatMap { $0 < 8 ? colours[$0] : nil } ?? (200, 200, 200)
        var rgba = [UInt8](repeating: 0, count: 14 * 16 * 4)
        for (r, bits) in rows.enumerated() {
            let line = 15 - r                                  // row 0 is the bottom
            for i in 0 ..< 7 where bits & (0x40 >> i) != 0 {
                for dx in 0 ..< 2 {
                    let o = (line * 14 + i * 2 + dx) * 4
                    rgba[o] = c.0
                    rgba[o + 1] = c.1
                    rgba[o + 2] = c.2
                    rgba[o + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: 14, height: 16, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 14 * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
