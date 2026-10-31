import SwiftUI

/// Room properties, objects (select to highlight), wires and texts of the selected room.
struct RoomInspector: View {
    @Bindable var model: ViewerModel
    let world: World

    var body: some View {
        let room = world.room(model.selectedRoom)
        let objects = world.objectsInRoom(room.id)
        List(selection: $model.selectedObject) {
            Section(roomTitle(room.id)) {
                row("Floor colour", hex(room.floorColor))
                row("Wall colour", hex(room.wallColor))
                row("Exits ↑ ↓ ← →", [room.up, room.down, room.left, room.right]
                    .map { $0 == room.id ? "–" : hex($0) }.joined(separator: " "))
                row("First object", room.firstObject == World.noObject ? "none" : hex(room.firstObject))
                if let robot = world.robots.firstIndex(where: { $0.interior == room.id }) {
                    row("Inside robot", "\(robot + 1) (object \(hex(world.robots[robot].object)))")
                }
            }
            Section("Objects (\(objects.count))") {
                ForEach(objects, id: \.self) { o in
                    ObjectRow(world: world, object: world.object(o)).tag(o)
                }
            }
            let wires = objects.compactMap { o in world.wire(o).map { (o, $0) } }
            if !wires.isEmpty {
                Section("Wires") {
                    ForEach(wires, id: \.0) { o, w in
                        Text(String(format: "$%02X → $%02X  ($%02X,$%02X)–($%02X,$%02X)", o, w.to, w.ax, w.ay, w.bx, w.by))
                            .font(.caption.monospaced())
                    }
                }
            }
            let texts = world.textsInRoom(room.id).map(world.text)
            if !texts.isEmpty {
                Section("Texts") {
                    ForEach(texts) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "#%02X at ($%02X,$%02X) style %d colour %d", t.id, t.x, t.y, t.style, t.color))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(t.string).font(.caption.monospaced())
                        }
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).monospaced() }
    }
}

private struct ObjectRow: View {
    let world: World
    let object: GameObject

    var body: some View {
        HStack(spacing: 8) {
            if let img = SpriteImage.make(world: world, object: object) {
                Image(decorative: img, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 21, height: 24)
                    .background(Color(white: 0.15))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "$%02X  sprite $%02X  colour %d", object.id, object.sprite, object.color))
                    .font(.caption.monospaced())
                Text(details).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    private var details: String {
        var s = String(format: "at ($%02X,$%02X) flags $%02X", object.x, object.y, object.flags)
        if object.link != World.noObject {
            s += String(format: " · follows $%02X %+d,%+d", object.link, Int8(truncatingIfNeeded: object.dx),
                        Int8(truncatingIfNeeded: object.dy))
        }
        return s
    }
}

/// A sprite as a tiny image, in the flat colour closest to the object's colour.
enum SpriteImage {
    /// Approximate RGB of the engine's colours 0-7 (black, green, purple, white, black, orange, blue, white).
    private static let colours: [(UInt8, UInt8, UInt8)] = [(90, 90, 90), (20, 245, 60), (255, 68, 253), (255, 255, 255),
                                                          (90, 90, 90), (255, 106, 60), (20, 207, 253), (255, 255, 255)]

    static func make(world: World, object: GameObject) -> CGImage? {
        let rows = Array(world.sprite(object.sprite))
        let c = object.color < 8 ? colours[object.color] : (200, 200, 200)
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
