import Apple2Kit
import GameController
import SwiftUI

/// The game full screen from launch (`TVGameView`): the world played last,
/// else the first one.  Without disks, the title and a note.
struct TVContentView: View {
    @State private var model = ViewerModel()
    /// The world played last, kept.
    @AppStorage("tvWorld") private var lastWorld = ""

    var body: some View {
        Group {
            if model.selectedWorld != nil {
                TVGameView(model: model)
            } else {
                HStack(spacing: 60) {
                    // The game's title screen (Data/ro_title.py, title_2.png of v1.1)
                    Image(.title)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 700)
                    ContentUnavailableView("No Disks", systemImage: "opticaldisc",
                                           description: Text("The Robot Odyssey I disk images (side A and side B) "
                                                             + "go in the app's resources."))
                }
            }
        }
        .task {
            model.openAtLaunch()
            let worlds = model.groups.flatMap(\.worlds)
            model.selectedWorldID = (worlds.first { $0.id == lastWorld } ?? worlds.first)?.id
        }
        // The loader takes the game to other worlds too.
        .onChange(of: model.selectedWorldID) { if let id = model.selectedWorldID { lastWorld = id } }
    }
}

/// The selected world played full screen, following the player and the
/// loader into the next world.
///
/// The Siri Remote: the clickpad's arrows step the player (I J K M; in the
/// loader the Apple's arrow keys), select is space (take or drop; in the
/// loader Return), play/pause the next tool (C S R: the cursor, the
/// soldering pen, the remote control; in the loader it pauses), Menu the
/// menu (`TVMenu`: the levels, the rooms, the game's keys…).
///
/// Inspecting (not playing, from the menu): the arrows go to the room next
/// door (`ViewerModel.go`), the game running on; select goes back to the
/// player's room and plays.
///
/// A game controller is the Apple's joystick (Apple2Kit's
/// `GameControllers`: the stick or the d-pad, A or X button 0, B or Y
/// button 1); the shoulders take the tools (left the cursor, right the pen,
/// a trigger the remote), its menu button opens the menu.  What the system
/// makes of its presses (select, arrows, B as Menu) is left out.
struct TVGameView: View {
    @Bindable var model: ViewerModel
    @FocusState private var focused: Bool
    @State private var showMenu = false
    /// Paused before the menu opened (the menu pauses the game).
    @State private var pausedBefore = false
    @State private var pad = PadButtons()

    /// The id the remote's presses type under (`ViewerModel.type`).
    private static let remoteKey = "siri-remote"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let world = model.selectedWorld {
                RoomCanvas(model: model, world: world)
            }
        }
        .overlay(alignment: .topLeading) {
            if !model.playing {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Inspecting " + roomTitle(model.selectedRoom), systemImage: "eye")
                    Text("Arrows: the room next door · Select: back to the game")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(40)
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.paused && !showMenu {
                Label("Paused", systemImage: "pause.fill")
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(40)
            }
        }
        .overlay(alignment: .bottom) {
            if model.loopStatus.hasPrefix("Main loop stopped") {
                Text(model.loopStatus).foregroundStyle(.red).padding()
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat, .up]) { press in
            let key = press.key.character.lowercased()
            if press.phase == .up {
                model.release(key)
                return .handled
            }
            guard let code = AppleKeyboard.code(for: press, appleArrows: model.inLoader) else { return .ignored }
            model.type(code, key: key, repeated: press.phase == .repeat)
            return .handled
        }
        .onMoveCommand { direction in
            guard !fromGamepad else { return }
            if !model.playing {
                switch direction {
                case .up: model.go(.up)
                case .down: model.go(.down)
                case .left: model.go(.left)
                case .right: model.go(.right)
                @unknown default: break
                }
                return
            }
            switch direction {
            case .up: tap(model.inLoader ? 0x8B : 0xC9)
            case .down: tap(model.inLoader ? 0x8A : 0xCD)
            case .left: tap(model.inLoader ? 0x88 : 0xCA)
            case .right: tap(model.inLoader ? 0x95 : 0xCB)
            @unknown default: break
            }
        }
        .onTapGesture {
            guard !fromGamepad else { return }
            if model.playing {
                tap(model.inLoader ? 0x8D : 0xA0)
            } else {
                model.playing = true                // back to the player's room
            }
        }
        .onPlayPauseCommand {
            guard !fromGamepad else { return }
            if model.playing, let key = model.nextToolKey {
                tap(key)
            } else {
                model.paused.toggle()
            }
        }
        .onExitCommand {
            guard !fromGamepad else { return }
            showMenu = true
        }
        .sheet(isPresented: $showMenu) {
            TVMenu(model: model, typeKey: tap)
        }
        .onChange(of: showMenu) {
            if showMenu {
                pausedBefore = model.paused
                model.releaseKeys()
                model.paused = true
            } else {
                model.paused = pausedBefore
                focused = true
            }
        }
        .task(id: model.session) {
            await model.runGame()
        }
        .task { await readPad() }
        .onAppear {
            model.playing = true
            focused = true
        }
        .onDisappear {
            model.playing = false
        }
    }

    /// The press came from a game controller (the one used last): the
    /// joystick has it already, or the shoulders (`readPad`).
    private var fromGamepad: Bool {
        GCController.current?.extendedGamepad != nil
    }

    /// A key pressed and let go at once: the Apple's latch keeps it till the game reads it.
    private func tap(_ code: UInt8) {
        model.type(code, key: TVGameView.remoteKey)
        model.release(TVGameView.remoteKey)
    }

    /// Every display frame, the game controller's buttons the joystick
    /// doesn't use: a new press of a shoulder takes a tool, of the menu
    /// button opens or closes the menu.
    private func readPad() async {
        for await _ in DisplayFrames.stream() {
            let gamepad = GCController.current?.extendedGamepad
                ?? GCController.controllers().lazy.compactMap(\.extendedGamepad).first
            let pressed = pad.newPresses(gamepad)
            if pressed.contains(.menu) { showMenu.toggle() }
            guard model.playing, !showMenu, !model.inLoader else { continue }
            if pressed.contains(.cursor) { tap(0xC3) }
            if pressed.contains(.pen) { tap(0xD3) }
            if pressed.contains(.remote) { tap(0xD2) }
        }
    }
}

/// The game controller's buttons besides the joystick's, and which were
/// down at the last look, for new presses.
struct PadButtons {
    enum Button: CaseIterable { case cursor, pen, remote, menu }

    private var down: Set<Button> = []

    mutating func newPresses(_ pad: GCExtendedGamepad?) -> Set<Button> {
        var now: Set<Button> = []
        if let pad {
            if pad.leftShoulder.isPressed { now.insert(.cursor) }
            if pad.rightShoulder.isPressed { now.insert(.pen) }
            if pad.leftTrigger.isPressed || pad.rightTrigger.isPressed { now.insert(.remote) }
            if pad.buttonMenu.isPressed { now.insert(.menu) }
        }
        defer { down = now }
        return now.subtracting(down)
    }
}

/// The menu over the game (Menu on the remote; Menu again closes it):
/// back to the game, the levels, inspecting the rooms, the game's own keys
/// (Esc, ?, Ctrl-S), the display.
struct TVMenu: View {
    @Bindable var model: ViewerModel
    /// Types a key into the game (as the remote does).
    let typeKey: (UInt8) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Back to the Game", systemImage: "gamecontroller") {
                        model.playing = true
                        dismiss()
                    }
                    NavigationLink {
                        TVLevels(model: model) { dismiss() }
                    } label: {
                        Label("Levels", systemImage: "building.2")
                    }
                    NavigationLink {
                        TVRooms(model: model) { dismiss() }
                    } label: {
                        Label("Inspect Rooms", systemImage: "square.grid.3x3")
                    }
                    Button("Inspect This Room", systemImage: "eye") {
                        model.playing = false
                        dismiss()
                    }
                    Button("Restart World", systemImage: "arrow.counterclockwise") {
                        model.restartGame()
                        model.playing = true
                        dismiss()
                    }
                }
                Section("The Game's Keys") {
                    key("Esc – the Game's Menu", "escape", 0x9B)
                    key("? – Help", "questionmark", 0xBF)
                    key("Ctrl-S – Sound On or Off", "speaker.wave.2", 0x93)
                }
                Section("Display") {
                    Button("Display: \(model.mode.rawValue)", systemImage: "paintpalette") {
                        let all = Screen.Style.allCases
                        model.mode = all[(all.firstIndex(of: model.mode)! + 1) % all.count]
                    }
                    Toggle(isOn: $model.smooth) { Label("Smooth", systemImage: "figure.walk.motion") }
                    Toggle(isOn: Binding { !model.sound } set: { model.sound = !$0 }) {
                        Label("Mute", systemImage: "speaker.slash")
                    }
                }
                Section("Controls") {
                    Text("Siri Remote: arrows walk · select takes or drops · play/pause the next tool "
                         + "(cursor, soldering pen, remote control) · Menu this menu")
                    Text("Game controller: stick or d-pad walks · A or X, B or Y the buttons · "
                         + "left shoulder the cursor, right shoulder the pen, a trigger the remote · ☰ this menu")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .navigationTitle(model.selectedWorld?.name ?? "Robot Odyssey")
        }
    }

    /// A key of the game's, typed as the menu closes (the game reads it when it runs on).
    private func key(_ title: String, _ image: String, _ code: UInt8) -> some View {
        Button(title, systemImage: image) {
            model.playing = true
            dismiss()
            typeKey(code)
        }
        .disabled(model.inLoader)
    }
}

/// The worlds of the disks and the saved games; one chosen is played.
struct TVLevels: View {
    var model: ViewerModel
    let done: () -> Void

    var body: some View {
        List {
            ForEach(model.groups) { group in
                Section(group.title) {
                    ForEach(group.worlds) { world in
                        Button {
                            model.selectedWorldID = world.id
                            model.playing = true
                            done()
                        } label: {
                            Label(world.name, systemImage: world.kind.systemImage)
                        }
                    }
                }
            }
            if !model.messages.isEmpty {
                Section("Notes") {
                    ForEach(model.messages, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Levels")
    }
}

/// The selected world's rooms in the grid of the world panel (room n at
/// column n % 8, row n / 8); one chosen is inspected, the game running on.
struct TVRooms: View {
    var model: ViewerModel
    let done: () -> Void

    var body: some View {
        if let world = model.selectedWorld {
            let rooms = (0 ..< World.roomCount).filter { world.isRoomUsed($0) || world.codeRooms[$0] != nil }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 30), count: 6), spacing: 30) {
                    ForEach(rooms, id: \.self) { r in
                        Button {
                            model.playing = false
                            model.show(room: r)
                            done()
                        } label: {
                            RoomCell(model: model, world: world, room: r)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(40)
            }
            .navigationTitle(world.name + " – Rooms")
            .task(id: world.id) { await model.prepareRooms(world: world, withMap: false) }
        }
    }
}
