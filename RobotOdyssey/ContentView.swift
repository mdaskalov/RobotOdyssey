import SwiftUI

/// The window: the worlds on the left, the selected world's room with the
/// rooms below it (`WorldView`), the inspector on the right; each panel
/// shown or hidden from the toolbar.
struct ContentView: View {
    @State private var model = ViewerModel()
    @State private var importing = false
    @AppStorage("levelsWidth") private var levelsWidth = 230.0

    var body: some View {
        HStack(spacing: 0) {
            if model.showLevels {
                HStack(spacing: 0) {
                    WorldList(model: model)
                        .frame(width: levelsWidth)
                    ResizeHandle(size: $levelsWidth, range: 160 ... 400, panel: .leading)
                }
                .transition(.move(edge: .leading))
                .zIndex(1)                          // the handle above the room
            }
            Group {
                if let world = model.selectedWorld {
                    WorldView(model: model, world: world)
                } else {
                    noWorld
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.default, value: model.showLevels)  // as the inspector slides
        .inspector(isPresented: $model.showInspector) {
            Group {
                if let world = model.selectedWorld {
                    RoomInspector(model: model, world: world)
                } else {
                    ContentUnavailableView("No World", systemImage: "sidebar.trailing")
                }
            }
            .overlay(alignment: .leading) {
                HStack { Divider() }                // the inspector has none of its own
            }
            .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
        }
        .navigationTitle(model.selectedWorld?.name ?? "Robot Odyssey")
        .toolbar { toolbar }
        .fileImporter(isPresented: $importing, allowedContentTypes: ViewerModel.diskTypes,
                      allowsMultipleSelection: true) { model.open($0) }
        .dropDestination(for: URL.self) { urls, _ in
            model.open(urls: urls)
            return true
        }
        .task {
            #if DEBUG
            // Development: -openDisks <path>... (needs the app sandbox off, e.g. ENABLE_APP_SANDBOX=NO)
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-openDisks") {
                model.openAtLaunch(args[(i + 1)...].prefix { !$0.hasPrefix("-") }.map { URL(fileURLWithPath: $0) })
                return
            }
            #endif
            model.openAtLaunch()
        }
    }

    /// From left to right: the disks, the game, the display options, the panels.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button("Open Disk Images…", systemImage: "opticaldiscdrive") { importing = true }
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Group {
                Toggle("Play", systemImage: "gamecontroller", isOn: $model.playing)
                    .help("Play: the keyboard goes to the game (I J K M or the arrow keys, space, ?, Esc…) and the loader, "
                          + "and the view follows the player into the next level or the world chosen in the menu")
                Button(model.paused ? "Run" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill") {
                    model.paused.toggle()
                }
                .help(model.paused ? "Run the world's main loop" : "Pause the world's main loop")
                Button("Step", systemImage: "forward.frame.fill") { model.stepTick() }
                    .disabled(!model.paused)
                    .help("Run one tick")
                Button("Restart", systemImage: "arrow.counterclockwise") { model.restartGame() }
                    .help("Start the selected world again from its start-up state")
            }
            .disabled(model.selectedWorld == nil)
            Toggle("Mute", systemImage: "speaker.slash", isOn: Binding { !model.sound } set: { model.sound = !$0 })
                .help("Mute the game's sounds (in the game, Ctrl-S turns them off and on)")
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Toggle("Mono", systemImage: "circle.lefthalf.filled",
                   isOn: Binding { model.mode == .monochrome } set: { model.mode = $0 ? .monochrome : .color })
                .help("Mono: as on a green monochrome monitor (off: the Apple II's colours)")
            Toggle("Tile Grid", systemImage: "grid", isOn: $model.showGrid)
                .help("The tile grid over the room: 20 columns, 12 rows")
            Toggle("Empty Rooms", systemImage: "square.dashed", isOn: $model.showEmptyRooms)
                .help("Show the rooms the world doesn't use in the rooms panel (blank otherwise)")
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Toggle("Levels", systemImage: "sidebar.leading", isOn: $model.showLevels)
                .help("Show or hide the levels")
            Toggle("Rooms", systemImage: "rectangle.bottomthird.inset.filled", isOn: $model.showRooms)
                .help("Show or hide the rooms")
            Toggle("Inspector", systemImage: "sidebar.trailing", isOn: $model.showInspector)
                .help("Show or hide the inspector")
        }
    }

    private var noWorld: some View {
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
                 + "or a folder containing them. Storage disks with saved games can be added too.")
        } actions: {
            Button("Open Disk Images…") { importing = true }
        }
    }
}

private struct WorldList: View {
    @Bindable var model: ViewerModel

    var body: some View {
        List(selection: $model.selectedWorldID) {
            ForEach(model.groups) { group in
                Section(group.title) {
                    ForEach(group.worlds) { world in
                        Label(world.name, systemImage: icon(world.kind)).tag(world.id)
                    }
                }
            }
            if !model.messages.isEmpty {
                Section("Notes") {
                    ForEach(model.messages, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !model.disks.isEmpty {
                Button("Close All Disks", role: .destructive) { model.closeAll() }
            }
        }
    }

    private func icon(_ kind: WorldKind) -> String {
        switch kind {
        case .level: "building.2"
        case .tutorial: "graduationcap"
        case .lab: "flask"
        case .savedGame: "tray.and.arrow.down"
        }
    }
}

/// The line between a panel and the rest of the window; drag it to resize
/// the panel (`size`: its width, or its height for a bottom panel).
struct ResizeHandle: View {
    @Binding var size: Double
    let range: ClosedRange<Double>
    /// Where the panel is: .leading (left of the line) or .bottom (below it).
    let panel: Edge
    /// `size` when the drag started.
    @State private var start: Double?

    var body: some View {
        let vertical = panel != .bottom
        Divider()
            .overlay {
                Color.clear
                    .frame(width: vertical ? 7 : nil, height: vertical ? nil : 7)
                    .contentShape(Rectangle())
                    .pointerStyle(.frameResize(position: vertical ? .trailing : .top))
                    .gesture(
                        // Global: the handle moves with the drag.
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = start ?? size
                                self.start = start
                                let delta = vertical ? drag.translation.width : -drag.translation.height
                                size = min(max(start + delta, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in start = nil }
                    )
            }
            .zIndex(1)                              // above the views next to it
    }
}

#Preview {
    ContentView()
}
