import Apple2Kit
import SwiftUI

/// The Mac's menus, as Apple2Emu's: the disks in File; the display, the
/// game view (View ▸ Game) and the panels in View; the game running in
/// Machine.
struct GameCommands: Commands {
    @Bindable var model: ViewerModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Disk Images…") { model.choosingDisks = true }
                .keyboardShortcut("o")
            Divider()
            Button("Close All Disks") { model.closeAll() }
                .disabled(model.disks.isEmpty)
        }
        CommandGroup(before: .toolbar) {
            Picker("Display", selection: $model.mode) {
                ForEach(Screen.Style.allCases) { Text($0.rawValue).tag($0) }
            }
            Menu("Game") {
                Toggle("Tile Grid", isOn: $model.showGrid)
                Toggle("Smooth Movement", isOn: $model.smooth)
                Toggle("Empty Rooms", isOn: $model.showEmptyRooms)
            }
            // Toggles, not a picker: choosing the zoom shown sizes the window again.
            Menu("Zoom") {
                ForEach(0 ... 5, id: \.self) { z in
                    Toggle(z == 0 ? "Fit" : "\(z)×", isOn: Binding(get: { model.zoom == z },
                                                                set: { _ in model.chooseZoom(z) }))
                }
            }
            Divider()
            Toggle("Levels", isOn: $model.showLevels)
                .keyboardShortcut("1")
            Toggle("World", isOn: $model.showWorld)
                .keyboardShortcut("2")
            Toggle("Current Room", isOn: $model.showCurrentRoom)
                .keyboardShortcut("3")
            Divider()
        }
        CommandMenu("Machine") {
            Group {
                Toggle("Play", isOn: $model.playing)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button(model.paused ? "Run" : "Pause") { model.paused.toggle() }
                    .keyboardShortcut("p")
                Button("Step Tick") { model.stepTick() }
                    .keyboardShortcut("t")
                    .disabled(!model.paused)
                Divider()
                Button("Restart World") { model.restartGame() }
                    .keyboardShortcut("r")
            }
            .disabled(model.selectedWorld == nil)
            Divider()
            Menu("Sound") {
                Toggle("Enable Sound", isOn: $model.sound)
                Button(VolumeMenuItem.title) {}     // becomes the slider: VolumeMenuItem
            }
            Button(model.mouseTaken ? "Release the Mouse (⌘)" : "Give the Game the Mouse (⌘)") {
                if model.mouseTaken { model.releaseMouse() } else { model.takeMouse() }
            }
            .disabled(!model.mouseTaken && (!model.playing || model.inLoader || model.selectedWorld == nil))
        }
    }
}
