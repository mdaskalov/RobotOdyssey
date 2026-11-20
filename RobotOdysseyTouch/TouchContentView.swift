import Apple2Kit
import SwiftUI

/// The game full screen from launch (`TouchGameView`): the world played last,
/// else the first one.  Without disks, the title and a button to open them.
struct TouchContentView: View {
    @State private var model = ViewerModel()
    /// The world played last, kept.
    @AppStorage("lastWorld") private var lastWorld = ""

    var body: some View {
        Group {
            if model.selectedWorld != nil {
                TouchGameView(model: model)
            } else {
                noDisks
            }
        }
        .fileImporter(isPresented: $model.choosingDisks, allowedContentTypes: ViewerModel.diskTypes,
                      allowsMultipleSelection: true) { model.open($0) }
        .task {
            model.openAtLaunch()
            let worlds = model.groups.flatMap(\.worlds)
            model.selectedWorldID = (worlds.first { $0.id == lastWorld } ?? worlds.first)?.id
        }
        // The loader takes the game to other worlds too.
        .onChange(of: model.selectedWorldID) { if let id = model.selectedWorldID { lastWorld = id } }
    }

    private var noDisks: some View {
        ContentUnavailableView {
            VStack(spacing: 20) {
                // The game's title screen (Data/ro_title.py, title_2.png of v1.1)
                Image(.title)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 560)
                Label("No Disks", systemImage: "opticaldisc")
            }
        } description: {
            Text("Open the Robot Odyssey I disk images (side A and side B, v1.0 or v1.1), "
                 + "or a folder containing them.")
        } actions: {
            Button("Open Disk Images…") { model.choosingDisks = true }
        }
    }
}

/// The selected world played full screen, following the player and the
/// loader into the next world.
///
/// Touch: the screen is the Apple's mouse (`touchMouse`, on at first) –
/// a drag moves the player as the Mac's mouse does (`ViewerModel.dragMouse`),
/// a tap is its button (take, drop, solder, the remote).  Mouse off, a
/// swipe is a step (I J K M) and a tap is space.  In the loader a swipe is
/// an arrow key, a tap Return.  The buttons at the top right: the menu
/// (`TouchMenu`, the game paused under it), the next tool (C S R), the
/// keyboard (typed into the game).  A hardware keyboard types as the Mac's.
///
/// Inspecting (not playing, from the menu): a swipe goes to the room next
/// door, the game running on; a tap goes back to the player's room and plays.
struct TouchGameView: View {
    @Bindable var model: ViewerModel
    @FocusState private var focus: Focus?
    @State private var showMenu = false
    /// Paused before the menu opened (the menu pauses the game).
    @State private var pausedBefore = false
    /// The drag's translation at its last change.
    @State private var dragged: CGSize?
    /// The on-screen keyboard's text: `sentinel`, then what was typed after
    /// (or deleted from) it (`typedChanged`).
    @State private var typed = TouchGameView.sentinel
    @AppStorage("touchMouse") private var touchMouse = true

    private enum Focus { case game, keyboard }

    /// The id the screen's taps and the on-screen keyboard type under (`ViewerModel.type`).
    private static let touchKey = "touch"
    private static let sentinel = " "

    var body: some View {
        ZStack {
            game
            keyboardField
        }
        .overlay(alignment: .topLeading) { inspecting }
        .overlay(alignment: .topTrailing) { controls }
        .overlay(alignment: .bottom) {
            if model.loopStatus.hasPrefix("Main loop stopped") {
                Text(model.loopStatus).foregroundStyle(.red).padding()
            }
        }
        .overlay { if showMenu { menu } }
        .animation(.default, value: showMenu)
        // Not ignoring the keyboard: with the on-screen keyboard up the game
        // fits the space above it (RoomCanvas keeps its aspect ratio), the
        // black behind it reaching under the keyboard.
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: showMenu) {
            if showMenu {
                pausedBefore = model.paused
                model.releaseKeys()
                model.paused = true
                focus = nil
            } else {
                model.paused = pausedBefore
                focus = .game
            }
        }
        .onChange(of: touchMouse) { if !touchMouse { model.releaseMouse() } }
        .task(id: model.session) {
            await model.runGame()
        }
        .onAppear {
            model.playing = true
            focus = .game
        }
        .onDisappear {
            model.playing = false
        }
    }

    /// The room on black, touched; a hardware keyboard's keys to the game.
    private var game: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let world = model.selectedWorld {
                RoomCanvas(model: model, world: world)
            }
        }
        .contentShape(Rectangle())
        .gesture(touch)
        .focusable()
        .focused($focus, equals: .game)
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
    }

    // MARK: touch

    /// One gesture for both: a touch that hardly moves is a tap (`tapped`),
    /// else a drag – the mouse while it moves, a swipe as it ends (`swiped`).
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let last = dragged ?? .zero
                dragged = value.translation
                guard touchMouse, model.playing, !model.inLoader else { return }
                model.dragMouse(by: value.translation.width - last.width, value.translation.height - last.height)
            }
            .onEnded { value in
                dragged = nil
                let t = value.translation
                if hypot(t.width, t.height) < 12 { tapped() } else { swiped(t) }
            }
    }

    private func tapped() {
        if !model.playing {
            model.playing = true                    // back to the player's room
        } else if model.inLoader {
            tap(0x8D)                               // Return
        } else if !touchMouse {
            tap(0xA0)                               // space: take or drop
        } else if !model.clickMouse() {
            // The mouse isn't the game's yet: space this time, the mouse from now on.
            tap(0xA0)
            model.takeMouse()
        }
    }

    private func swiped(_ t: CGSize) {
        let horizontal = abs(t.width) > abs(t.height)
        let direction: Room.Direction = horizontal ? (t.width > 0 ? .right : .left) : (t.height > 0 ? .down : .up)
        if !model.playing {
            model.go(direction)
        } else if model.inLoader {
            switch direction {                      // the Apple's arrow keys
            case .up: tap(0x8B)
            case .down: tap(0x8A)
            case .left: tap(0x88)
            case .right: tap(0x95)
            @unknown default: break
            }
        } else if !touchMouse {
            switch direction {                      // I J K M
            case .up: tap(0xC9)
            case .down: tap(0xCD)
            case .left: tap(0xCA)
            case .right: tap(0xCB)
            @unknown default: break
            }
        }
    }

    /// A key pressed and let go at once: the Apple's latch keeps it till the game reads it.
    private func tap(_ code: UInt8) {
        model.type(code, key: TouchGameView.touchKey)
        model.release(TouchGameView.touchKey)
    }

    // MARK: the on-screen keyboard

    /// Out of sight: focused, it brings up the on-screen keyboard, whose
    /// keys go to the game (`typedChanged`).  Vertical, so Return types a
    /// line break and the keyboard stays up.
    private var keyboardField: some View {
        TextField("", text: $typed, axis: .vertical)
            .focused($focus, equals: .keyboard)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .onChange(of: typed) { typedChanged(typed) }
    }

    /// What was typed after the sentinel goes to the game (a line break as
    /// Return), the sentinel deleted as ←; then the text is the sentinel again.
    private func typedChanged(_ text: String) {
        guard text != TouchGameView.sentinel else { return }
        if text.count < TouchGameView.sentinel.count {
            tap(0x88)
        } else {
            for c in text.dropFirst(TouchGameView.sentinel.count) {
                if c == "\n" {
                    tap(0x8D)
                } else if let a = c.asciiValue, a >= 0x20, a < 0x7F {
                    tap(a | 0x80)
                }
            }
        }
        typed = TouchGameView.sentinel
    }

    // MARK: overlays

    /// The menu, the next tool, the keyboard.
    private var controls: some View {
        VStack(spacing: 12) {
            Button("Menu", systemImage: "line.3.horizontal") { showMenu = true }
            Button("Next Tool", systemImage: "wrench.and.screwdriver") {
                if let key = model.nextToolKey { tap(key) }
            }
            .disabled(!model.playing || model.inLoader)
            Button("Keyboard", systemImage: focus == .keyboard ? "keyboard.chevron.compact.down" : "keyboard") {
                focus = focus == .keyboard ? .game : .keyboard
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .padding()
        .opacity(showMenu ? 0 : 1)
    }

    @ViewBuilder
    private var inspecting: some View {
        if !model.playing {
            VStack(alignment: .leading, spacing: 4) {
                Label("Inspecting " + roomTitle(model.selectedRoom), systemImage: "eye")
                Text("Swipe: the room next door · Tap: back to the game")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }

    /// The menu over the game, at the side; a tap beside it closes it.
    private var menu: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showMenu = false }
            TouchMenu(model: model, typeKey: tap) { showMenu = false }
                .frame(maxWidth: 420)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding()
                .transition(.move(edge: .trailing))
        }
    }
}

/// The menu over the game (the menu button; Close or a tap beside it closes
/// it): back to the game, the levels, inspecting the rooms, the game's own
/// keys (Esc, ?, Ctrl-S), the display, the controls, the disks.
struct TouchMenu: View {
    @Bindable var model: ViewerModel
    /// Types a key into the game (as a tap does).
    let typeKey: (UInt8) -> Void
    let close: () -> Void
    @AppStorage("touchMouse") private var touchMouse = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Back to the Game", systemImage: "gamecontroller") {
                        model.playing = true
                        close()
                    }
                    NavigationLink {
                        TouchLevels(model: model, done: close)
                    } label: {
                        Label("Levels", systemImage: "building.2")
                    }
                    NavigationLink {
                        TouchRooms(model: model, done: close)
                    } label: {
                        Label("Inspect Rooms", systemImage: "square.grid.3x3")
                    }
                    Button("Inspect This Room", systemImage: "eye") {
                        model.playing = false
                        close()
                    }
                    Button("Restart World", systemImage: "arrow.counterclockwise") {
                        model.restartGame()
                        model.playing = true
                        close()
                    }
                }
                Section("The Game's Keys") {
                    key("Esc – the Game's Menu", "escape", 0x9B)
                    key("? – Help", "questionmark", 0xBF)
                    key("Ctrl-S – Sound On or Off", "speaker.wave.2", 0x93)
                }
                Section("Display") {
                    Picker(selection: $model.mode) {
                        ForEach(Screen.Style.allCases) { Text($0.rawValue).tag($0) }
                    } label: {
                        Label("Display", systemImage: "paintpalette")
                    }
                    Toggle(isOn: $model.smooth) { Label("Smooth Movement", systemImage: "figure.walk.motion") }
                    Toggle(isOn: $model.showGrid) { Label("Tile Grid", systemImage: "grid") }
                    Toggle(isOn: $model.showEmptyRooms) { Label("Empty Rooms", systemImage: "square.dashed") }
                    Toggle(isOn: $model.sound) { Label("Sound", systemImage: "speaker.wave.2") }
                    Slider(value: $model.volume, in: 0 ... 1) {
                        Text("Volume")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill")
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .disabled(!model.sound)
                }
                Section {
                    Toggle(isOn: $touchMouse) { Label("Touch Mouse", systemImage: "hand.draw") }
                } header: {
                    Text("Controls")
                } footer: {
                    Text(touchMouse
                         ? "Drag on the screen to walk, tap for the mouse button (take, drop, solder). "
                           + "The wrench takes the next tool, the keyboard types into the game."
                         : "Swipe to step, tap to take or drop. "
                           + "The wrench takes the next tool, the keyboard types into the game.")
                }
                Section("Disks") {
                    Button("Open Disk Images…", systemImage: "opticaldiscdrive") {
                        close()
                        model.choosingDisks = true
                    }
                }
            }
            .navigationTitle(model.selectedWorld?.name ?? "Robot Odyssey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
    }

    /// A key of the game's, typed as the menu closes (the game reads it when it runs on).
    private func key(_ title: String, _ image: String, _ code: UInt8) -> some View {
        Button(title, systemImage: image) {
            model.playing = true
            close()
            typeKey(code)
        }
        .disabled(model.inLoader)
    }
}

/// The worlds of the disks and the saved games; one chosen is played.
struct TouchLevels: View {
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

/// The selected world's rooms (with Empty Rooms, all of them); one chosen
/// is inspected, the game running on.
struct TouchRooms: View {
    var model: ViewerModel
    let done: () -> Void

    var body: some View {
        if let world = model.selectedWorld {
            let rooms = (0 ..< World.roomCount).filter {
                model.showEmptyRooms || world.isRoomUsed($0) || world.codeRooms[$0] != nil
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                    ForEach(rooms, id: \.self) { r in
                        Button {
                            model.playing = false
                            model.show(room: r)
                            done()
                        } label: {
                            RoomCell(model: model, world: world, room: r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Rooms")
            .task(id: world.id) { await model.prepareRooms(world: world, withMap: false) }
        }
    }
}
