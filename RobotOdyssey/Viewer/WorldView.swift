import Apple2Kit
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
                        model.canvasFocused = focused
                        if !focused {
                            model.releaseKeys()
                            model.releaseMouse()
                        }
                    }
                    #if os(macOS)
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                        model.releaseKeys()
                        model.releaseMouse()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                        model.releaseMouse()
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
            .animation(.default, value: model.showWorld)  // as the current room slides
        }
        .onAppear { focused = true }
    }
}
