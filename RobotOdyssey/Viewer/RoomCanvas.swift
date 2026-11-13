import Apple2Kit
import SwiftUI

/// The room at 560x384 (scaled to fit), with selection of sprites and wires,
/// and tile grid; the point under the pointer goes to `ViewerModel.pointer`.
/// In Play a press of ⌘ alone gives the game the mouse and takes it back
/// (`ViewerModel.takeMouse`): the pointer hidden, the mouse moves the
/// player, its button is the game's.  With Option or Control a click
/// selects what is there.
struct RoomCanvas: View {
    var model: ViewerModel
    let world: World

    #if os(macOS)
    /// Option or Control is held now: a click selects.
    private static var selects: Bool {
        !NSEvent.modifierFlags.intersection([.option, .control]).isEmpty
    }
    #endif

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
                if !model.inLoader {
                    let layer = model.liveItems(world: world, room: model.selectedRoom)
                    if !layer.items.isEmpty {
                        NativeLayer(items: layer.items, pixels: model.liveImage(world: world, room: model.selectedRoom),
                                    afterTexts: layer.afterTexts, mono: model.mode == .monochrome)
                            .equatable()
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                if model.showGrid && !model.inLoader { TileGrid(k: k) }
                if !model.inLoader, let s = model.selection.flatMap(contents.sprite) {
                    Rectangle()
                        .stroke(.yellow, lineWidth: 2)
                        .frame(width: 28 * k + 4, height: 32 * k + 4)
                        .offset(x: CGFloat(s.x * 4) * k - 2, y: CGFloat((191 - s.y - 15) * 2) * k - 2)
                        .allowsHitTesting(false)
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
            #if os(macOS)
            .onContinuousHover { phase in
                var point: RoomPoint?
                if case .active(let p) = phase { point = logical(p, k: k) }
                if model.pointer != point { model.pointer = point }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    if RoomCanvas.selects { model.select(at: logical(value.location, k: k), in: world) }
                }
            )
            #endif
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.canvasFrame = $0 }
        .aspectRatio(560.0 / 384.0, contentMode: .fit)
        .frame(maxWidth: 1120)
        .onAppear { model.canvasAppeared() }
        .onDisappear { model.canvasDisappeared() }
    }

    #if os(macOS)
    private func logical(_ p: CGPoint, k: CGFloat) -> RoomPoint {
        RoomPoint(x: Int(p.x / k / 4), y: 191 - Int(p.y / k / 2))
    }
    #endif
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
