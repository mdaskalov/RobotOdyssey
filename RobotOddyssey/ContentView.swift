import SwiftUI

struct ContentView: View {
    @State private var model = ViewerModel()
    @State private var importing = false
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            WorldList(model: model)
                .navigationTitle("Robot Odyssey")
                .toolbar {
                    ToolbarItem {
                        Button("Open Disk Images…", systemImage: "opticaldiscdrive") { importing = true }
                    }
                }
        } detail: {
            if let world = model.selectedWorld {
                WorldView(model: model, world: world)
                    .inspector(isPresented: $showInspector) {
                        RoomInspector(model: model, world: world)
                            .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
                    }
                    .toolbar {
                        ToolbarItemGroup {
                            Picker("Renderer", selection: $model.renderer) {
                                ForEach(ViewerModel.Renderer.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .help("Game: the world's main loop running on the 6502 emulator. Static: tiles, texts, objects and wires only.")
                            if model.renderer == .game {
                                Toggle("Play", systemImage: "gamecontroller", isOn: $model.playing)
                                    .help("Play: the keyboard goes to the game (I J K M or the arrow keys, space, ?, Esc…) and the view follows the player")
                                Button(model.paused ? "Run" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill") {
                                    model.paused.toggle()
                                }
                                .help(model.paused ? "Run the world's main loop" : "Pause the world's main loop")
                                Button("Step", systemImage: "forward.frame.fill") { model.stepTick() }
                                    .disabled(!model.paused)
                                    .help("Run one tick")
                                Button("Restart", systemImage: "arrow.counterclockwise") { model.restartGame() }
                                    .help("Start the main loop again from the world's start-up state")
                            }
                            Picker("Display", selection: $model.mode) {
                                ForEach(HiresImage.Mode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Toggle("Tile Grid", systemImage: "grid", isOn: $model.showGrid)
                            Toggle("Empty Rooms", systemImage: "square.dashed", isOn: $model.showEmptyRooms)
                            Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                        }
                    }
            } else {
                ContentUnavailableView {
                    Label("No Disks", systemImage: "opticaldisc")
                } description: {
                    Text("Open the Robot Odyssey I disk images (side A and side B, v1.0 or v1.1), "
                         + "or a folder containing them. Storage disks with saved games can be added too.")
                } actions: {
                    Button("Open Disk Images…") { importing = true }
                }
            }
        }
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
                model.open(urls: args[(i + 1)...].prefix { !$0.hasPrefix("-") }.map { URL(fileURLWithPath: $0) })
                return
            }
            #endif
            model.reopenLastDisks()
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

#Preview {
    ContentView()
}
